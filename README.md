# Hybrid Cloud Burst Demo — Auto-Scale from On-Prem to Cloud

A hybrid cloud demo that automatically bursts workloads from on-prem OpenShift to cloud (OSD on GCP) when under pressure. Uses **Arize Phoenix** (AI observability platform) as the workload, with three layers of auto-scaling driven by **KEDA + Submariner + Cluster Autoscaler**.

## How It Works

```
Load spike
  → On-prem HPA scales Phoenix (1→4 pods)
    → KEDA detects high request rate via Submariner tunnel
      → OSD Phoenix burst pods scale (0→8)
        → OSD Cluster Autoscaler adds worker nodes (3→6)
```

Everything is **fully automatic** — you only start the load generator. The rest is event-driven.

## Architecture

| Component | On-Prem (hybrid) | OSD (GCP) |
|-----------|-----------------|-----------|
| **Phoenix Server** | 1-4 pods (HPA) | 0-8 pods (KEDA) |
| **PostgreSQL** | Primary (Portworx PVC) | — uses on-prem via Submariner |
| **Scaling** | HPA (CPU > 60%) | KEDA ScaledObject (request rate > 5/s) |
| **Nodes** | 3 fixed (master+worker) | 3-6 worker nodes (autoscaler) |
| **Load Generator** | Sends OTLP traces | — |
| **Metrics Proxy** | — | Queries on-prem metrics via Submariner |

### Cross-Cluster Connectivity

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Submariner** | IPsec tunnel + Globalnet | Service discovery via `clusterset.local` DNS |
| **ACM** | ManagedClusterSet + Addons | Manages Submariner lifecycle on both clusters |
| **ArgoCD** | ApplicationSets | GitOps deployment of all manifests |

### The Scaling Chain (7 Steps)

1. Load generator floods Phoenix with OTLP traces
2. On-prem HPA scales Phoenix 1→4 pods (CPU > 60%)
3. Metrics proxy on OSD queries on-prem Phoenix metrics through Submariner tunnel
4. KEDA ScaledObject detects `request_rate > 5/s` → scales OSD Phoenix 0→8
5. OSD burst pods connect to on-prem PostgreSQL via clusterset DNS (Submariner)
6. When pods can't schedule → OSD cluster autoscaler adds worker nodes (3→6)
7. Load stops → KEDA scales OSD to 0, HPA scales on-prem back to 1

## Clusters

| Cluster | Platform | Role |
|---------|----------|------|
| **on-prem** | On-Prem OCP | Phoenix primary + PostgreSQL |
| **osd** | OSD on GCP | Burst target (KEDA-controlled) |
| **hub** | On-Prem OCP | ACM Hub + ArgoCD |

## Quick Start

### 1. Start the load

```bash
KUBECONFIG=$ONPREM_KUBECONFIG \
  oc -n phoenix scale deploy phoenix-loadgenerator --replicas=3
```

### 2. Watch the auto-scaling chain

```bash
# Launch the live dashboard (6 tmux panes)
cd phoenix/scripts && ./06-watch-dashboard.sh

# Or watch individually:
# On-prem HPA
KUBECONFIG=$ONPREM_KUBECONFIG oc -n phoenix get hpa -w

# KEDA + burst pods on OSD
oc --context=osd -n phoenix get scaledobject,hpa,pods -w

# OSD worker nodes scaling
oc --context=osd get nodes -l node-role.kubernetes.io/worker -w
```

### 3. Stop the load

```bash
KUBECONFIG=$ONPREM_KUBECONFIG \
  oc -n phoenix scale deploy phoenix-loadgenerator --replicas=0
```

KEDA scales OSD back to 0 (120s cooldown), HPA scales on-prem back to 1, cluster autoscaler removes idle worker nodes.

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Workload** | Arize Phoenix | AI observability — OTLP trace ingestion |
| **On-prem scaling** | HPA (autoscaling/v2) | Scale Phoenix pods 1→4 based on CPU |
| **Cross-cluster scaling** | KEDA (Red Hat v2.18) | Scale OSD burst pods 0→8 based on on-prem metrics |
| **Metrics bridge** | Metrics Proxy | Converts Prometheus text → JSON for KEDA via Submariner |
| **Cross-cluster network** | Submariner + Globalnet | IPsec tunnel, clusterset DNS (`*.svc.clusterset.local`) |
| **Node scaling** | OSD Cluster Autoscaler | Worker nodes 3→6 via MachinePool autoscaling |
| **Cluster management** | ACM 2.x | ManagedClusterSet, Submariner addon |
| **GitOps** | ArgoCD ApplicationSets | Deploy all manifests from Git via ACM Placements |
| **Automation** | Ansible + Terraform | Cluster provisioning and configuration |

## Project Structure

```
.
├── phoenix/
│   ├── DEMO-RUNBOOK.md              # Full demo narrative + troubleshooting
│   ├── argocd/                      # ApplicationSets + ACM Placements
│   │   ├── phoenix-base-appset.yaml
│   │   ├── phoenix-onprem-appset.yaml
│   │   ├── phoenix-burst-appset.yaml
│   │   └── phoenix-loadgen-appset.yaml
│   ├── manifests/
│   │   ├── base/                    # Namespace + secrets (all clusters)
│   │   ├── onprem/                  # Phoenix server + PostgreSQL + HPA
│   │   ├── burst/                   # Phoenix burst pods (replicas:0, KEDA scales)
│   │   ├── keda/                    # Metrics proxy + ScaledObject
│   │   └── loadgen/                 # OTLP trace load generator
│   ├── scripts/
│   │   ├── 01-deploy-phoenix.sh
│   │   ├── 02-start-load.sh
│   │   ├── 03-burst-to-cloud.sh
│   │   ├── 04-burst-stop.sh
│   │   ├── 05-watch-all.sh
│   │   └── 06-watch-dashboard.sh    # tmux 6-pane live dashboard
│   └── docs/
├── hybridbank/                      # HybridBank failover demo (separate)
├── ansible/
│   ├── site.yml                     # Master playbook (7 stages)
│   ├── roles/phoenix/               # Phoenix deployment role
│   └── inventory/
├── terraform/
│   ├── aro/                         # ARO cluster (Azure)
│   ├── osd/                         # OSD cluster (GCP)
│   └── vpn/                         # IPsec mesh VPN
└── docs/
```

## Firewall Requirements

The Submariner IPsec tunnel requires these ports open on the on-prem firewall:

| Direction | Source | Dest | Ports | Protocol |
|-----------|--------|------|-------|----------|
| Inbound | OSD gateway public IP | On-prem gateway node (NAT) | 4500, 500, 4490 | UDP |

## Documentation

| Document | Description |
|----------|-------------|
| [`phoenix/DEMO-RUNBOOK.md`](phoenix/DEMO-RUNBOOK.md) | Burst demo — full runbook with troubleshooting |
| [`hybridbank/DEMO-RUNBOOK.md`](hybridbank/DEMO-RUNBOOK.md) | HybridBank failover demo (Part 1) |
| [`hybridbank/DEMO-RUNBOOK-PART2.md`](hybridbank/DEMO-RUNBOOK-PART2.md) | HybridBank intelligent placement (Part 2) |
| [`docs/storage-replication-infrastructure.md`](docs/storage-replication-infrastructure.md) | Portworx DR setup |
| [`terraform/vpn/README.md`](terraform/vpn/README.md) | Three-site IPsec mesh VPN |

## Prerequisites

- `oc` CLI with kubeconfigs for all clusters
- Ansible 2.14+ with `kubernetes.core` collection
- Terraform 1.5+
- `ocm` CLI (for OSD management)
- `subctl` (for Submariner diagnostics)
