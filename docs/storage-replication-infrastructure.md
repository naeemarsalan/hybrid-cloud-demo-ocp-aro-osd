# Storage Replication Infrastructure Guide

How to configure Portworx volume replication for any application across the three clusters (on-prem OCP, ARO, OSD).

## Prerequisites

These components must be operational before configuring replication:

| Component | Purpose | Verification |
|-----------|---------|-------------|
| Portworx Enterprise | Storage layer on each cluster | `pxctl status` shows Online |
| Submariner + Globalnet | Cross-cluster networking (overlapping CIDRs) | `subctl show connections` shows connected |
| px-gw-proxy | Non-hostNetwork TCP proxy for PX API | `oc get svc px-gw-proxy -n portworx` |
| Submariner ServiceExport | Exposes px-gw-proxy across clusters | `oc get serviceexport px-gw-proxy -n portworx` |
| GCS objectstore bucket | Intermediate storage for cloudsnap backup/restore | `pxctl credentials list` shows GCS cred |

See [portworx-cross-cloud-connectivity.md](portworx-cross-cloud-connectivity.md) for how these were set up and the problems encountered.

## Cluster Identifiers

| Cluster | PX Cluster Name | PX Cluster ID | Submariner Cluster ID | GlobalNet CIDR | Proxy GlobalIngressIP |
|---------|----------------|---------------|----------------------|----------------|----------------------|
| On-prem OCP | px-cluster-ocp-onprem | `bd134578-c142-4b2a-9a51-43c97a6b71f3` | onprem-cluster | 242.2.0.0/16 | 242.2.255.253 |
| ARO | px-cluster-aro | `5e2e7b4c-a9a4-4e69-a8e4-41af0e147b16` | aro-cluster | 242.0.0.0/16 | 242.0.255.253 |
| OSD | px-cluster-osd | `498b4909-b9e9-4d66-957e-61d7eb67e5fb` | osd-cluster | 242.1.0.0/16 | 242.1.255.250 |

## Architecture

```
On-Prem (Primary)
  │
  ├── PX cloudsnap backup ──► GCS bucket (px-dr-openenv-j4tbl)
  │                                │
  │                    ┌───────────┴───────────┐
  │                    ▼                       ▼
  │              ARO (Standby)           OSD (Standby)
  │              cloudsnap restore       cloudsnap restore
  │
  └── Stork MigrationSchedule triggers backup every N minutes
      Stork polls restore status via Submariner proxy
```

Data flow per migration cycle:
1. Stork on primary creates a `Migration` CR
2. PX creates a cloudsnap (incremental after first full) → uploads to GCS
3. PX initiates restore on destination via gRPC through Submariner proxy
4. Destination PX downloads from GCS and applies to the standby volume
5. Stork polls restore status until complete

## Layer 1: PX Cluster Pairs (Storage Layer)

PX cluster pairs enable the PX daemons to communicate across clusters. These must exist **bidirectionally** — both the source and destination need a pair to each other.

### Creating a PX Cluster Pair

Run on the **source** cluster, pointing at the **destination** proxy IP:

```bash
# 1. Get the destination cluster's PX token
KUBECONFIG=/tmp/kubeconfig-<dest>.yaml \
  oc -n portworx exec <px-pod> -- pxctl cluster token show
# Output: Token is <PX_TOKEN>

# 2. Create the pair on the source
KUBECONFIG=/tmp/kubeconfig-<source>.yaml \
  oc -n portworx exec <px-pod> -- pxctl cluster pair create \
    --ip <DEST_PROXY_GLOBALINGRESSIP> \
    --remote-port 9001 \
    --token <PX_TOKEN>
```

### Current PX Pair Mesh

Each cluster has pairs to the other two. Example from on-prem:

```
on-prem → ARO:  endpoint http://242.0.255.253:9001
on-prem → OSD:  endpoint http://242.1.255.250:9001
```

### Critical Constraint: Bidirectional Pairs Required

If you delete a PX pair on cluster A→B, you must also ensure the pair on B→A still exists. Without the reverse pair, PX on B cannot locate the objectstore credential needed to restore cloudsnaps from A. Symptom: restore silently never starts; status check returns "Key not found".

## Layer 2: Stork ClusterPairs (Scheduler Layer)

Stork ClusterPairs give Stork on the source cluster access to both the destination Kubernetes API and the PX storage layer. They live in the **application namespace**.

### Creating a Stork ClusterPair

```yaml
apiVersion: stork.libopenstorage.org/v1alpha1
kind: ClusterPair
metadata:
  name: <pair-name>           # e.g., aro-cluster
  namespace: <app-namespace>  # Must match the namespace being replicated
spec:
  config:
    clusters:
      <pair-name>:
        server: <DEST_API_SERVER_URL>
        insecure-skip-tls-verify: true
    contexts:
      <pair-name>:
        cluster: <pair-name>
        user: <pair-name>
    current-context: <pair-name>
    users:
      <pair-name>:
        token: <DEST_KUBECONFIG_TOKEN>
  options:
    ip: "<DEST_PROXY_GLOBALINGRESSIP>"
    port: "9001"
    token: "<DEST_PX_CLUSTER_TOKEN>"
```

### Verification

```bash
oc get clusterpair -n <namespace>
# Both schedulerStatus and storageStatus must show "Ready"
```

### Token Refresh

The `spec.config.users.*.token` is a kubeconfig bearer token that **expires**. When it expires:
- `schedulerStatus` flips to error
- Migrations that touch resources (PV/PVC) fail at the Applications stage
- Volume-only migrations may still succeed (PX uses its own token)

To refresh:
```bash
# Get a fresh token (ARO example using az CLI)
az aro list-credentials --name <aro-name> --resource-group <rg>
oc login --username=kubeadmin --password=<pass> --server=<api-url>
NEW_TOKEN=$(oc whoami -t)

# Patch the ClusterPair
oc patch clusterpair <name> -n <namespace> --type=merge \
  -p "{\"spec\":{\"config\":{\"users\":{\"<pair-name>\":{\"token\":\"$NEW_TOKEN\"}}}}}"
```

## Layer 3: SchedulePolicy

Cluster-scoped resource that defines replication frequency.

```yaml
apiVersion: stork.libopenstorage.org/v1alpha1
kind: SchedulePolicy
metadata:
  name: px-volume-sync
policy:                    # NOTE: top-level key is "policy", NOT "spec"
  interval:
    intervalMinutes: 1     # Every 1 minute (for demo; use 15+ for production)
    retain: 3              # Keep last 3 migration objects
```

**Gotcha**: Using `spec.interval` instead of `policy.interval` silently creates the resource but Stork never triggers migrations.

## Layer 4: MigrationSchedule

Namespace-scoped resource that ties everything together.

```yaml
apiVersion: stork.libopenstorage.org/v1alpha1
kind: MigrationSchedule
metadata:
  name: volume-sync-<dest>
  namespace: <app-namespace>
spec:
  template:
    spec:
      clusterPair: <stork-clusterpair-name>
      namespaces:
      - <app-namespace>
      includeResources: false    # Resources managed by GitOps/ACM
      includeVolumes: true       # Only replicate PX volume data
      startApplications: false   # Don't start apps on destination
  schedulePolicyName: px-volume-sync
```

### Monitoring

```bash
# Check schedule status
oc get migrationschedule -n <namespace> -o yaml

# Status shows items under .status.items.Interval[]
# Each item has: name, status (InProgress/Successful/PartialSuccess/Failed)
```

## Onboarding a New Application

### Step-by-step checklist

1. **PVC uses Portworx StorageClass**
   ```yaml
   storageClassName: px-csi-replicated   # repl=3, io_profile=auto
   ```
   Other PX classes available: `px-csi-db` (repl=3, io_profile=db), etc.

2. **Stork ClusterPairs exist in the app namespace**
   Create one ClusterPair per destination cluster, in the application namespace:
   ```bash
   oc get clusterpair -n <app-namespace>
   # Should show one per destination, both Ready/Ready
   ```
   If not, create them following the template in Layer 2 above.

3. **Seed the destination volumes** (one-time initial migration)
   ```yaml
   apiVersion: stork.libopenstorage.org/v1alpha1
   kind: Migration
   metadata:
     name: initial-sync-<dest>
     namespace: <app-namespace>
   spec:
     clusterPair: <pair-name>
     namespaces:
     - <app-namespace>
     includeResources: false
     includeVolumes: true
     startApplications: false
   ```
   Wait for `status: Successful` or `PartialSuccess` (PartialSuccess is OK if the volume succeeded but PVC resource failed due to already existing).

4. **Ensure the destination volume is detached**
   The standby volume on the destination cluster must NOT be mounted by a running pod. If the app is deployed on the destination (e.g., via GitOps), scale down the stateful component or ensure its PVC points to a different (local) volume.

   **Why**: PX cloudsnap restore cannot write to an attached volume. If the volume is attached, the restore silently never starts and the migration reports "all endpoints returned error" after timeout.

5. **Create the MigrationSchedule**
   Follow the template in Layer 4 above.

6. **Verify first scheduled migration succeeds**
   ```bash
   oc get migrationschedule <name> -n <namespace> -o yaml
   # .status.items.Interval[0].status should be Successful or PartialSuccess
   ```

## Known Issues and Constraints

### Volume must be detached on destination for restore
PX cloudsnap restore requires the target volume to be detached. If the application is running on the standby cluster using the replicated volume, restores fail silently.

**Workaround**: Keep the stateful component scaled to 0 on standby clusters, or have the standby app use a separate local volume while the replicated volume is maintained as a detached standby.

### PX uses direct node IPs for status checks
After a cloudsnap backup, PX on the source polls restore status on the destination using `current_endpoints` (the destination's actual node IPs, e.g., 10.0.2.x). These are not routable through Submariner Globalnet. PX falls back to the proxy endpoint via gRPC, but the REST status check on port 17001 still fails against direct IPs.

In practice, this causes a delay (timeout on unreachable IPs) but the migration still completes if the restore itself succeeds via the proxy.

### PartialSuccess is normal for volume-only migrations
When `includeResources: false`, PX still reports PV/PVC as resources. If the PVC already exists on the destination (from GitOps), the resource migration fails while the volume migration succeeds → `PartialSuccess`. This is expected.

### SchedulePolicy uses `policy:` not `spec:`
The SchedulePolicy CRD uses `policy.interval` at the top level. Using `spec.interval` creates the object without error but Stork never triggers scheduled migrations.

### Stork restart may be needed after ClusterPair changes
If Stork doesn't pick up new MigrationSchedules, restart the Stork deployment:
```bash
oc rollout restart deployment stork -n portworx
```
Then delete and recreate the MigrationSchedule.

## Failover Procedure (Manual)

When the primary cluster fails:

1. **Stop the MigrationSchedule** on the primary (if accessible):
   ```bash
   oc patch migrationschedule <name> -n <namespace> --type=merge \
     -p '{"spec":{"suspend": true}}'
   ```

2. **Scale up the application** on the standby cluster:
   ```bash
   oc scale deployment <stateful-app> -n <namespace> --replicas=1
   ```
   The app will mount the replicated volume with data from the last successful sync.

3. **Update DNS/routing** to point traffic to the standby cluster's frontend.
