# HybridBank Demo Runbook

## Architecture Overview

- **3 clusters**: On-prem OCP (`hybrid`), ARO on Azure (`aro`), OSD on GCP (`osd`)
- **Hub ArgoCD** pushes workloads to spoke clusters via ApplicationSets + ACM Placements
- **Portworx** replicates PostgreSQL data across all clusters
- **PII policy** enforces data locality — archive DB only runs on `data-zone=restricted` clusters

### Workload Distribution (steady state)

| Cluster | Workloads |
|---------|-----------|
| hybrid (on-prem) | postgres-core, postgres-archive, account-service, transaction-service |
| aro (Azure) | api-gateway, frontend, postgres-core (standby, replicas=0) |
| osd (GCP) | empty (lifeboat standby) |

---

## Prerequisites

- `oc` logged into all clusters with contexts: `hub`, `hybrid`, `aro`, `osd`
- Portworx installed and ClusterPair configured across all clusters
- OpenShift GitOps operator installed on hub
- ACM managing all spoke clusters in `hybrid-cloud-demo` ManagedClusterSet
- ArgoCD cluster secrets registered for each managed cluster
- ArgoCD repository secret for the private git repo

## Scripts

```
hybridbank/scripts/
  config.sh              # Cluster names, contexts, image registry
  00-push-images.sh      # Build & push container images
  01-deploy-argocd.sh    # Deploy HybridBank via ArgoCD
  02-failover-onprem.sh  # Act 2: Simulate on-prem outage
  03-failback-onprem.sh  # Act 3: Restore on-prem
  04-failover-cloud.sh   # Act 4: Cloud failover ARO → OSD
  05-failback-cloud.sh   # Act 5: Restore ARO
```

---

## Act 1 — Deploy HybridBank

```bash
./hybridbank/scripts/01-deploy-argocd.sh
```

- Labels on-prem cluster `data-zone=restricted`
- Creates ManagedClusterSetBinding + GitOpsCluster in `openshift-gitops`
- Applies 3 ApplicationSets (base, onprem, cloud) with bundled Placements
- Applies lifeboat placement for cloud failover
- Applies PII data locality policy
- Grants `anyuid` SCC for postgres, scales standby to 0

**Key talking points:**
- ArgoCD push model — hub pushes to spokes, no agent needed on spokes
- `clusterDecisionResource` generator reads ACM PlacementDecisions
- Placement selects clusters by labels (`cloud=on-prem`, `cloud=azure`, `environment=demo`)
- PII policy: `mustnothave` rule — Deployments with `data-sensitivity: pii` blocked on unrestricted clusters

**Verify:**
```bash
oc get applicationsets -n openshift-gitops
oc get applications.argoproj.io -n openshift-gitops
oc get placementdecisions -n openshift-gitops -o wide
```

---

## Act 2 — On-Prem Outage (Failover)

```bash
./hybridbank/scripts/02-failover-onprem.sh
```

- Removes `cloud=on-prem` label from `hybrid` ManagedCluster
- Placement no longer matches → ArgoCD prunes on-prem workloads
- Scales up standby postgres on ARO (Portworx replica data)

**Key talking points:**
- Label-driven failover — single label change triggers full workload migration
- ArgoCD auto-prunes removed resources (no manual cleanup)
- Portworx async replication means standby postgres has near-real-time data
- API gateway detects missing services → switches to `limited` mode
- PII data (archive DB) unavailable — enforced by data locality

**Verify:**
```bash
oc --context=hybrid get pods -n hybridbank          # should be empty
oc --context=aro get pods -n hybridbank             # standby postgres running
curl https://$(oc --context=aro get route hybridbank -n hybridbank -o jsonpath='{.spec.host}')/api/health
```

---

## Act 3 — On-Prem Restored (Failback)

```bash
./hybridbank/scripts/03-failback-onprem.sh
```

- Scales down standby postgres on ARO
- Re-adds `cloud=on-prem` label → placement matches again
- ArgoCD redeploys all on-prem workloads
- Waits for postgres, account-service, transaction-service to be ready

**Key talking points:**
- Symmetric operation — re-add label and services come back
- Portworx data persists across failover/failback cycles
- API gateway detects services restored → back to `normal` mode

**Verify:**
```bash
oc --context=hybrid get pods -n hybridbank           # all services running
oc --context=aro get pods -n hybridbank              # api-gateway + frontend only
```

---

## Act 4 — Cloud Failover (ARO → OSD)

```bash
./hybridbank/scripts/04-failover-cloud.sh
```

- Scales up standby postgres on OSD
- Patches `hybridbank-cloud` ApplicationSet generator: `hybridbank-cloud` → `hybridbank-lifeboat` placement
- Lifeboat placement selects OSD (matches `cloud In [azure, gcp]`, tolerates unreachable)
- ArgoCD moves api-gateway + frontend from ARO to OSD

**Key talking points:**
- Single JSON patch swaps the entire cloud workload to a different cluster
- Lifeboat placement has `tolerationSeconds: 30` for unreachable clusters
- Different failover mechanism than on-prem — patches the ApplicationSet, not cluster labels
- Demonstrates multi-cloud portability (Azure → GCP)

**Verify:**
```bash
oc --context=aro get pods -n hybridbank              # should be empty
oc --context=osd get pods -n hybridbank              # api-gateway + frontend + postgres
```

---

## Act 5 — Cloud Restored (Failback to ARO)

```bash
./hybridbank/scripts/05-failback-cloud.sh
```

- Patches ApplicationSet back: `hybridbank-lifeboat` → `hybridbank-cloud` placement
- Scales down standby postgres on OSD
- ArgoCD moves workloads back to ARO

**Key talking points:**
- Reverse patch restores normal state
- OSD returns to empty standby

**Verify:**
```bash
oc --context=aro get pods -n hybridbank              # api-gateway + frontend
oc --context=osd get pods -n hybridbank              # empty
oc get applications.argoproj.io -n openshift-gitops  # all Synced/Healthy
```

---

## Verification Commands (anytime)

```bash
# ArgoCD state
oc get applicationsets -n openshift-gitops
oc get applications.argoproj.io -n openshift-gitops

# Placement decisions
oc get placementdecisions -n openshift-gitops -o wide

# Cluster labels
oc get managedclusters --show-labels

# PII policy compliance
oc get policy pii-data-locality -n hybridbank

# Pods across all clusters
for ctx in hybrid aro osd; do echo "=== $ctx ==="; oc --context=$ctx get pods -n hybridbank; done
```

---

## Timing Notes

- ArgoCD ApplicationSet requeue: **180 seconds** — label/patch changes take up to 3 min to reconcile
- Portworx replication interval: **1 minute**
- Lifeboat unreachable toleration: **30 seconds**
