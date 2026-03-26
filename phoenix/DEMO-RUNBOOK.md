# Phoenix Burst-to-Cloud Demo Runbook

## Overview

This demo shows **Arize Phoenix** (open-source AI observability platform) running on-prem under heavy trace ingestion load, then **automatically bursting Phoenix server pods to OSD (GCP)** via KEDA -- all while keeping PostgreSQL on-prem with data accessed through Submariner.

### Architecture

```
                    +--------------------------------------------------+
                    |                 ACM Hub (virt)                    |
                    |  Manages both clusters, Submariner addon         |
                    +----------+-----------------------+---------------+
                               |                       |
              +----------------+                       +----------------+
              |                                                        |
              v                                                        v
+---------------------------+                        +---------------------------+
|     ON-PREM (hybrid)      |                        |       OSD (GCP)           |
|                           |                        |                           |
| +---------------------+  |   Submariner IPsec      | +---------------------+  |
| | Phoenix Server      |  |   Globalnet enabled     | | Phoenix Burst       |  |
| | 2-6 pods (HPA)      |  |   <ON-PREM-PUBLIC-IP>           | | 0-3 pods (KEDA)     |  |
| +---------------------+  |  <--------------------> | +---------------------+  |
|                           |   <OSD-GATEWAY-IP>         |                           |
| +---------------------+  |                        | +---------------------+  |
| | PostgreSQL          |  |   clusterset.local DNS  | | metrics-proxy       |  |
| | (persistent PVC)    |<-+------------------------+-| queries on-prem     |  |
| +---------------------+  |                        | | Phoenix /metrics    |  |
|                           |                        | +---------------------+  |
| +---------------------+  |                        |                           |
| | Load Generator      |  |                        | KEDA ScaledObject         |
| | (OTLP traces)       |  |                        | polls metrics-proxy       |
| +---------------------+  |                        | scales phoenix 0-3        |
|                           |                        |                           |
| +---------------------+  |                        +---------------------------+
| | Submariner Gateway  |  |
| +---------------------+  |
+---------------------------+
```

### Demo Flow

1. Load generator sends OTLP traces to on-prem Phoenix
2. On-prem HPA scales Phoenix from 2 to 6 pods as CPU crosses 60%
3. KEDA on OSD detects high request rate via metrics-proxy (queries on-prem Phoenix metrics through Submariner tunnel)
4. KEDA auto-scales OSD Phoenix from 0 to 3 burst pods
5. OSD burst pods connect to on-prem PostgreSQL via Submariner clusterset DNS (`phoenix-postgres.phoenix.svc.clusterset.local`)
6. Load stops -- KEDA scales OSD back to 0, on-prem HPA scales back to 2

### Routes

| Cluster | URL |
|---------|-----|
| On-prem | https://<ON-PREM-PHOENIX-ROUTE> |
| OSD     | https://<OSD-PHOENIX-ROUTE> |

### Key Concepts

| Concept | Implementation |
|---------|---------------|
| **Workload** | Arize Phoenix -- OTLP trace ingestion + AI observability UI |
| **Contention trigger** | Load generator floods Phoenix with OTLP traces |
| **On-prem scaling** | HPA scales Phoenix pods 2 to 6 based on CPU (60% threshold) |
| **Cloud burst** | KEDA on OSD auto-scales burst pods 0 to 3 based on on-prem request rate |
| **Cross-cluster metrics** | metrics-proxy on OSD queries on-prem Phoenix `/metrics` via Submariner |
| **Data stays on-prem** | PostgreSQL remains on-prem only; burst pods connect via Submariner DNS |
| **Networking** | Submariner IPsec tunnel with Globalnet between on-prem and OSD |

---

## Prerequisites

### Cluster Access

```bash
# On-prem
export KUBECONFIG=$ONPREM_KUBECONFIG  # path to on-prem kubeconfig
oc get nodes

# OSD
oc --context=osd get nodes

# ACM Hub
oc --context=hub get managedclusters
```

### Infrastructure Requirements

- ACM installed on hub (virt) managing both on-prem and OSD clusters
- Submariner configured with Globalnet between on-prem (<ON-PREM-PUBLIC-IP>) and OSD (<OSD-GATEWAY-IP>)
- Red Hat Custom Metrics Autoscaler (KEDA) v2.18 installed on OSD
- ArgoCD (OpenShift GitOps) installed on hub

---

## Act 1: Deploy Phoenix (Steady State)

### Step 1: Deploy via Ansible (full automation)

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/07-phoenix.yml
```

### Or deploy via script (manual)

```bash
cd phoenix/scripts
./01-deploy-phoenix.sh
```

### Step 2: Verify deployment

```bash
# Check pods on on-prem
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix get pods

# Expected output:
# NAME                        READY   STATUS    RESTARTS
# phoenix-7f8b9c6d4-abc12    1/1     Running   0
# phoenix-7f8b9c6d4-def34    1/1     Running   0
# phoenix-postgres-0          1/1     Running   0

# Check HPA
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix get hpa

# Expected output:
# NAME          REFERENCE            TARGETS   MINPODS   MAXPODS
# phoenix-hpa   Deployment/phoenix   5%/60%    2         6

# Check KEDA on OSD (should show 0 replicas)
oc --context=osd -n phoenix get scaledobject,hpa,pods

# Check metrics-proxy on OSD
oc --context=osd -n phoenix get deploy metrics-proxy
```

### Step 3: Open Phoenix UI

Open the on-prem route in a browser:
```
https://<ON-PREM-PHOENIX-ROUTE>
```

You should see the Phoenix AI observability dashboard with no traces yet.

---

## Act 2: Generate Load (Create Contention)

### Step 1: Start load generator

```bash
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix scale deploy phoenix-loadgenerator --replicas=3
```

### Step 2: Watch contention build

Open **separate terminals** and watch:

```bash
# Terminal 1: Watch on-prem HPA react to increasing CPU
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix get hpa -w

# Terminal 2: Watch KEDA on OSD auto-scale burst pods
oc --context=osd -n phoenix get scaledobject,hpa,pods -w

# Terminal 3: Check metrics-proxy output
oc --context=osd -n phoenix logs deploy/metrics-proxy -f
```

### What to observe

1. **HPA scales up**: On-prem Phoenix pods go from 2 to 3 to 4 to 5 to 6 as CPU crosses 60%
2. **KEDA detects load**: metrics-proxy starts reporting non-zero `request_rate` from on-prem Phoenix
3. **KEDA scales burst pods**: OSD Phoenix goes from 0 to 1 to 2 to 3 as request_rate exceeds threshold (5)
4. **Burst pods connect to on-prem DB**: OSD pods use `phoenix-postgres.phoenix.svc.clusterset.local` via Submariner
5. **Phoenix UI fills up**: Traces visible on both on-prem and OSD routes (shared database)

### Talking points

> "We're running Arize Phoenix on-prem to handle AI trace observability for our LLM applications. Under normal load, 2 pods handle all incoming traces. But we've just simulated a spike -- maybe a new model rollout, a batch evaluation, or just increased user traffic. The HPA has scaled us to our on-prem maximum of 6 pods, and we're still under pressure."
>
> "But here's where it gets interesting -- KEDA on our OSD cluster in GCP is watching the on-prem metrics through a Submariner tunnel. It detects the high request rate and automatically spins up burst pods in the cloud. No manual intervention, no label changes -- pure metrics-driven autoscaling across clusters."

---

## Act 3: Verify Multi-Cluster Operation

### Check burst pods on OSD

```bash
# See burst pods running on OSD
oc --context=osd -n phoenix get pods

# Check KEDA ScaledObject status
oc --context=osd -n phoenix get scaledobject phoenix-burst-scaler

# Verify burst pods can reach on-prem PostgreSQL
oc --context=osd -n phoenix exec deploy/phoenix -- \
  curl -s phoenix-postgres.phoenix.svc.clusterset.local:5432 2>&1 || true
```

### Check Phoenix on both routes

Both URLs should show the same Phoenix UI with the same traces (shared database):

- On-prem: https://<ON-PREM-PHOENIX-ROUTE>
- OSD: https://<OSD-PHOENIX-ROUTE>

---

## Act 4: Scale Down (Return to Steady State)

### Step 1: Stop load generator

```bash
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix scale deploy phoenix-loadgenerator --replicas=0
```

### Step 2: Watch automatic scale down

```bash
# Watch KEDA scale OSD back to 0 (cooldown: 120 seconds)
oc --context=osd -n phoenix get scaledobject,hpa,pods -w

# Watch on-prem HPA scale back to 2
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix get hpa -w
```

### What to observe

1. **Load generator stopped**: Replicas set to 0
2. **Request rate drops**: metrics-proxy reports decreasing `request_rate`
3. **KEDA cooldown**: After 120 seconds of low metrics, KEDA scales OSD Phoenix from 3 to 0
4. **HPA relaxes**: On-prem Phoenix scales back to 2 pods as CPU drops
5. **Back to steady state**: Only on-prem running Phoenix + PostgreSQL, zero cloud cost

### Talking points

> "When the spike passes, everything scales down automatically. KEDA's cooldown period ensures we don't thrash, and within a couple of minutes the burst pods in GCP are gone. We only use cloud compute when we need it -- no idle resources, no over-provisioned hardware. This is true hybrid cloud elasticity driven entirely by real application metrics."

---

## Troubleshooting

### Submariner Connectivity

```bash
# Check Submariner gateway status on on-prem
KUBECONFIG=$ONPREM_KUBECONFIG oc -n submariner-operator get gateway

# Check Submariner gateway status on OSD
oc --context=osd -n submariner-operator get gateway

# Verify ServiceExport exists on on-prem for PostgreSQL
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix get serviceexport

# Test DNS resolution from OSD
oc --context=osd -n phoenix exec deploy/metrics-proxy -- \
  nslookup phoenix-postgres.phoenix.svc.clusterset.local

# Check Submariner connection details
# On-prem gateway: <ON-PREM-PUBLIC-IP>
# OSD gateway: <OSD-GATEWAY-IP>
# Globalnet: enabled
```

### KEDA Not Scaling

```bash
# Check ScaledObject status
oc --context=osd -n phoenix get scaledobject phoenix-burst-scaler -o yaml

# Check KEDA operator logs
oc --context=osd -n openshift-keda logs deploy/keda-operator --tail=50

# Test metrics-proxy directly
oc --context=osd -n phoenix exec deploy/metrics-proxy -- curl -s http://localhost:8080/

# Check if metrics-proxy can reach on-prem Phoenix
oc --context=osd -n phoenix logs deploy/metrics-proxy

# Verify KEDA HPA was created
oc --context=osd -n phoenix get hpa
```

### Firewall Rules

If Submariner tunnels are not establishing:

```bash
# Required ports between gateway nodes:
# - UDP 4500 (IPsec NAT-T)
# - UDP 4800 (Submariner VXLAN)
# - UDP 500 (IKE)

# Check GCP firewall rules for OSD
gcloud compute firewall-rules list --filter="name~submariner"

# Check on-prem firewall (if applicable)
# Ensure ports 4500, 4800, 500 UDP are open between:
# On-prem gateway: <ON-PREM-PUBLIC-IP>
# OSD gateway: <OSD-GATEWAY-IP>
```

### Phoenix Pods CrashLooping on OSD

```bash
# Check pod logs
oc --context=osd -n phoenix logs deploy/phoenix --tail=50

# Most common cause: can't reach on-prem PostgreSQL via Submariner
# Verify the connection string uses clusterset DNS:
# postgresql://phoenix:PASSWORD@phoenix-postgres.phoenix.svc.clusterset.local:5432/phoenix

# Check if secret exists on OSD
oc --context=osd -n phoenix get secret phoenix-secrets
```

### Metrics Proxy Returning Zeros

```bash
# Check if metrics-proxy can reach on-prem Phoenix metrics endpoint
oc --context=osd -n phoenix exec deploy/metrics-proxy -- \
  curl -s http://phoenix.phoenix.svc.clusterset.local:9090/metrics | head -20

# If connection fails, check Submariner connectivity
# If metrics return but proxy shows zeros, check the metric names in the proxy script
```

---

## File Reference

| Path | Purpose |
|------|---------|
| `phoenix/manifests/base/` | Namespace + secrets (deployed to all clusters) |
| `phoenix/manifests/onprem/` | PostgreSQL + Phoenix server + HPA + ServiceExports |
| `phoenix/manifests/burst/` | Phoenix burst deployment + Service + Route (connects to on-prem DB via Submariner) |
| `phoenix/manifests/keda/` | KEDA ScaledObject + metrics-proxy (ConfigMap + Deployment + Service) |
| `phoenix/manifests/loadgen/` | Load generator (OTLP trace flood) |
| `phoenix/argocd/` | ArgoCD ApplicationSets + ACM Placements |
| `phoenix/scripts/` | Demo automation scripts |
| `ansible/roles/phoenix/` | Ansible role for automated deployment |
| `ansible/playbooks/07-phoenix.yml` | Ansible playbook |

## Quick Reference: Key Commands

```bash
# Start load (3 replicas)
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix scale deploy phoenix-loadgenerator --replicas=3

# Watch on-prem HPA
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix get hpa -w

# Watch KEDA on OSD
oc --context=osd -n phoenix get scaledobject,hpa,pods -w

# Check metrics-proxy
oc --context=osd -n phoenix logs deploy/metrics-proxy -f

# Stop load
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix scale deploy phoenix-loadgenerator --replicas=0
```
