# HybridBank Demo Runbook — Part 2: Intelligent Automated Placement

## Prerequisites

- **Part 1 fully deployed** (`01-deploy-argocd.sh` completed, all workloads running)
- Portworx installed with ClusterPairs configured across all clusters
- Gatekeeper operator installed on ARO (built-in as `openshift-azure-guardrails`). OSD does not have Gatekeeper — the PII constraint will only be enforced on clusters where it is installed.
- ACM Hub with ManagedClusters labeled: `environment=demo`, `cloud=on-prem|azure|gcp`
- All four kubeconfig contexts active: `hub`, `hybrid`, `aro`, `osd`

> **Note:** The upgrade script (`06-upgrade-to-intelligent.sh`) automatically handles:
> - Creating `ManagedClusterSetBinding` in the `hybridbank` namespace (required for policy Placements)
> - Enabling `governance-policy-framework` and `config-policy-controller` addons on all managed clusters (required for ACM ConfigurationPolicies)

## What Part 2 Changes

| Capability | Part 1 (Manual) | Part 2 (Intelligent) |
|-----------|-----------------|---------------------|
| Cloud failover | Patch ApplicationSet + scale postgres | Remove label → automatic |
| On-prem failover | Remove label + scale postgres | Remove label → automatic |
| Postgres on cloud | replicas=0 (manual scale up/down) | replicas=1 always (ArgoCD selfHeal from git) |
| Cloud selection | Single-cloud (ARO only) + separate lifeboat | Multi-cloud (ARO + OSD via Steady prioritizer) |
| Data sovereignty | ACM inform policy only | Gatekeeper admission control (enforce) |
| ClusterPair tokens | Short-lived kubeconfig tokens | Long-lived SA tokens |
| Outage tolerance | Immediate | 30s grace period (tolerations) |

---

## Act 1: Upgrade to Intelligent Placement

```bash
./hybridbank/scripts/06-upgrade-to-intelligent.sh
```

**What to show the audience:**
- Placement now has `tolerations` (30s grace for transient outages)
- Steady prioritizer (weight 3) prevents unnecessary flapping
- Multi-cloud selector (`cloud In [azure, gcp]`) replaces separate lifeboat placement
- Postgres on cloud is at replicas=1 (ArgoCD enforces git manifest via selfHeal)

**Important behavior to be aware of:**
- When the Placement selector changes from `cloud=azure` to `cloud In [azure, gcp]`,
  ACM re-evaluates cluster selection. The Steady prioritizer has no prior decision to
  anchor to, so ACM picks the cluster with the highest ResourceAllocatable scores.
  In practice, **OSD usually wins over ARO** due to higher allocatable resources.
  This means cloud workloads may move from ARO to OSD during the upgrade.
- Only the selected cloud cluster gets workloads (api-gateway, frontend, postgres-core).
  The other cloud cluster has zero pods — ArgoCD only deploys where the Placement points.
- The ApplicationSet `requeueAfterSeconds: 180` means PlacementDecision changes take
  up to ~3 minutes to propagate. The script waits for this.

**Talking points:**
- Part 1 required 4 manual commands per failover (label change + AppSet patch + postgres scale + rollout wait)
- Part 2 reduces this to 1 label change — everything else is automatic
- Steady prioritizer means workloads stay put unless forced to move
- 30s toleration prevents false alarms from brief network blips

**Verify:**
```bash
oc --context=hub get placement -n openshift-gitops
oc --context=hub get placementdecisions -n openshift-gitops \
  -o jsonpath='{range .items[*]}{.metadata.name}: {range .status.decisions[*]}{.clusterName} {end}{"\n"}{end}'
oc --context=hub get policy -n hybridbank
# Check which cloud cluster has workloads:
oc --context=aro get pods -n hybridbank
oc --context=osd get pods -n hybridbank
```

---

## Act 2: Policy Enforcement

**Show Gatekeeper blocking PII on unrestricted clusters:**

> **Note:** The Gatekeeper policy is deployed via ACM (`remediationAction: enforce`), which
> pushes the ConstraintTemplate and Constraint to managed clusters. Allow ~2 minutes after
> the upgrade script for the policy to propagate before testing.
>
> **Prerequisite:** Gatekeeper operator must be installed on the target cluster. ARO has
> Gatekeeper built-in (in `openshift-azure-guardrails`). OSD and on-prem may not — install
> it via OperatorHub if needed. The constraint only works on clusters that have the CRDs.
>
> The constraint checks **Deployments** (not Pods), so use `oc create --dry-run=server`
> with a Deployment manifest to test.

```bash
# This should be DENIED on ARO (no data-zone=restricted ConfigMap)
cat <<'EOF' | oc --context=aro create -f - --dry-run=server
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pii-test
  namespace: hybridbank
  labels:
    data-sensitivity: pii
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pii-test
  template:
    metadata:
      labels:
        app: pii-test
    spec:
      containers:
      - name: test
        image: busybox
        command: ["sleep", "3600"]
EOF
# Expected: admission webhook "validation.gatekeeper.sh" denied the request

# This should SUCCEED on on-prem (has data-zone=restricted)
cat <<'EOF' | oc --context=hybrid create -f - --dry-run=server
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pii-test
  namespace: hybridbank
  labels:
    data-sensitivity: pii
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pii-test
  template:
    metadata:
      labels:
        app: pii-test
    spec:
      containers:
      - name: test
        image: busybox
        command: ["sleep", "3600"]
EOF
# Expected: deployment.apps/pii-test created (server dry run)
```

**Show PX data readiness:**
```bash
oc --context=hub get policy px-data-readiness -n hybridbank
# Compliant on clusters where pgdata-core PVC is Bound
```

**Talking points:**
- Gatekeeper enforces data sovereignty at the admission level — PII Deployments are blocked on clusters without `data-zone=restricted`
- PX data readiness policy validates Portworx replication is complete before workloads start
- These are preventive controls, not just monitoring
- The overall `gatekeeper-pii-constraint` policy may show NonCompliant if some clusters don't have Gatekeeper installed (e.g. OSD)

---

## Act 3: On-Prem Outage (Automatic)

```bash
./hybridbank/scripts/07-simulate-onprem-outage.sh
```

> Press `Ctrl+C` to exit the `watch` command at the end of the script.

**What to show:**
- Single label removal triggers automatic failover
- Placement decisions update immediately (onprem decision becomes empty)
- ArgoCD withdraws on-prem pods (account-service, transaction-service, postgres-core, postgres-archive)
- ArgoCD pruning takes ~3-4 minutes total (up to 3 min AppSet requeue + ~60s pod termination)
- Cloud cluster is unaffected — postgres already at replicas=1, api-gateway running
- No manual postgres scaling needed (Part 1 required `oc scale`)
- Gateway on cloud switches to limited mode (no account/transaction services available)

**Talking points:**
- In Part 1, this required `oc scale` to bring up standby postgres
- In Part 2, postgres is already running on the cloud cluster — ArgoCD manages replicas from git
- Tolerations give 30s before ACM reacts, preventing flapping

**Verify:**
```bash
# Placement should show empty onprem decision (immediate)
oc --context=hub get placementdecisions -n openshift-gitops \
  -o jsonpath='{range .items[*]}{.metadata.name}: {range .status.decisions[*]}{.clusterName} {end}{"\n"}{end}'
# On-prem pods should be gone (wait ~3-4 minutes for full withdrawal)
oc --context=hybrid get pods -n hybridbank
```

---

## Act 4: On-Prem Restore (Automatic)

```bash
./hybridbank/scripts/08-simulate-onprem-restore.sh
```

**What to show:**
- Single label addition restores on-prem services
- Cloud cluster unaffected (postgres stays at replicas=1, managed by ArgoCD)
- Gateway switches back to normal mode

> **Timing:** The PlacementDecision updates immediately, but the ApplicationSet
> requeue interval (`requeueAfterSeconds: 180`) means ArgoCD may take up to
> ~3 minutes to generate the Application and deploy pods to hybrid.

**Verify:**
```bash
# Wait up to 3 minutes, then check
oc --context=hybrid get pods -n hybridbank
```

---

## Act 5: Cloud Outage (Automatic)

```bash
./hybridbank/scripts/09-simulate-cloud-outage.sh
```

> Press `Ctrl+C` to exit the `watch` command at the end of the script.

**What to show:**
- Remove the current cloud cluster's label → Placement drops it
- If workloads were on ARO, they move to OSD (and vice versa)
- If workloads were already on OSD (Steady kept it there since Act 1), removing
  ARO's label has no workload impact — OSD stays selected, ARO had no pods anyway
- No ApplicationSet patching needed (Part 1 required AppSet patch)
- No postgres scaling needed (Part 1 required `oc scale`)
- Postgres on the new cloud cluster deploys at replicas=1 automatically (from git manifest)

> **Note:** After the Act 1 upgrade, the Steady prioritizer typically anchors cloud
> workloads on OSD. Removing ARO's label in this scenario doesn't cause visible workload
> movement. To demonstrate an actual cloud failover with pod migration, you would need
> to first force workloads to ARO (by temporarily removing OSD's label), then simulate
> the ARO outage.

**Talking points:**
- Part 1 required patching the ApplicationSet generator to switch from cloud to lifeboat placement
- Part 2 uses a single multi-cloud Placement — just remove the failed cluster's label
- This is the key improvement: the intelligence is in the Placement, not in manual scripts

---

## Act 6: Cloud Restore (Automatic)

```bash
./hybridbank/scripts/10-simulate-cloud-restore.sh
```

**What to show:**
- Re-add the cloud label — both ARO and OSD now match the cloud Placement
- Steady prioritizer (weight 3) keeps workloads on the current cluster (prevents unnecessary migration)
- To force back: temporarily remove the other cluster's label (instructions printed by the script)

**Talking points:**
- Steady prioritizer is intentionally sticky — avoids thrashing
- In production, you'd let workloads stay on the surviving cluster
- Force-back is available when you explicitly want to rebalance

---

## Summary: Part 1 vs Part 2

| Action | Part 1 Commands | Part 2 Commands |
|--------|----------------|-----------------|
| On-prem failover | `label cloud-` + `scale postgres` | `label cloud-` |
| On-prem failback | `scale postgres 0` + `label cloud=on-prem` | `label cloud=on-prem` |
| Cloud failover | `scale postgres` + `patch appset` | `label cloud-` |
| Cloud failback | `patch appset` + `scale postgres 0` | `label cloud=azure` |

Part 2 eliminates all manual postgres scaling and ApplicationSet patching.

---

## Timing Expectations

| Event | Expected Delay |
|-------|---------------|
| PlacementDecision update after label change | Immediate (~seconds) |
| ApplicationSet picks up new PlacementDecision | Up to 180s (`requeueAfterSeconds`) |
| ArgoCD deploys/prunes pods after Application change | 30-60s |
| Gatekeeper policy propagation to managed clusters | ~2 minutes |
| Total failover (label change → pods running) | ~3-4 minutes |

---

## Troubleshooting

```bash
# Check placement decisions (use --context=hub for all hub commands)
oc --context=hub get placementdecisions -n openshift-gitops \
  -o jsonpath='{range .items[*]}{.metadata.name}: {range .status.decisions[*]}{.clusterName} {end}{"\n"}{end}'

# Check placement status
oc --context=hub get placement -n openshift-gitops -o wide

# Check ApplicationSet status (shows generated Applications)
oc --context=hub get applicationset -n openshift-gitops \
  -o jsonpath='{range .items[*]}{.metadata.name}: {range .status.resources[*]}{.name}={.status} {end}{"\n"}{end}'

# Check policy compliance
oc --context=hub get policy -n hybridbank

# Check Gatekeeper constraints on a managed cluster
oc --context=aro get constraints
oc --context=aro get constrainttemplate piirestrictedzone

# Check ClusterPair status
oc --context=hybrid get clusterpair -n hybridbank

# Check pods on cloud clusters (only the selected one will have pods)
for ctx in aro osd; do
  echo "=== ${ctx} ==="
  oc --context=${ctx} get pods -n hybridbank 2>/dev/null || echo "  (no access or no pods)"
done

# If ApplicationSet isn't generating Applications, check cluster secrets
oc --context=hub get secrets -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster \
  -o jsonpath='{range .items[*]}{.metadata.name} {end}'

# If policy Placements show 0 selected clusters, check ManagedClusterSetBinding
oc --context=hub get managedclustersetbinding -n hybridbank
# If missing: oc --context=hub apply -f hybridbank/acm/clusterset-binding.yaml

# If ConfigurationPolicies aren't being processed on spokes, check governance addons
for cluster in aro osd hybrid; do
  echo "$cluster:"
  oc --context=hub get managedclusteraddon -n $cluster | grep -E 'governance|config-policy'
done
# Both governance-policy-framework and config-policy-controller must show Available=True

# If Gatekeeper constraint isn't enforcing, check if CRDs exist on the cluster
oc --context=aro get crd constrainttemplates.templates.gatekeeper.sh
# If missing, Gatekeeper operator is not installed on that cluster
```
