# OSD Cluster Autoscaler

Configures OSD worker node autoscaling so new nodes are added when KEDA burst pods can't be scheduled.

## Setup via OCM CLI

```bash
# Get your OSD cluster ID
CLUSTER_ID=$(ocm list clusters --parameter search="name='osd-gcp'" --no-headers | awk '{print $1}')

# 1. Create cluster autoscaler
ocm post "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/autoscaler" <<'EOF'
{
  "balance_similar_node_groups": true,
  "skip_nodes_with_local_storage": false,
  "log_verbosity": 1,
  "max_pod_grace_period": 600,
  "pod_priority_threshold": -10,
  "resource_limits": {
    "max_nodes_total": 12
  },
  "scale_down": {
    "enabled": true,
    "delay_after_add": "5m",
    "delay_after_delete": "3m",
    "delay_after_failure": "3m",
    "unneeded_time": "3m",
    "utilization_threshold": "0.5"
  }
}
EOF

# 2. Enable autoscaling on worker machine pool (3 min, 6 max)
ocm patch "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/machine_pools/worker" <<'EOF'
{
  "autoscaling": {
    "min_replicas": 3,
    "max_replicas": 6
  }
}
EOF

# 3. Verify
ocm get "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/autoscaler"
ocm get "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/machine_pools/worker"
```

## How It Works

When KEDA scales Phoenix burst pods beyond what 3 worker nodes can fit, pods go `Pending`. The cluster autoscaler detects unschedulable pods and adds worker nodes (up to 6). When load drops and nodes are underutilized (<50% for 3 minutes), the autoscaler removes them.

## Scaling Chain

```
KEDA scales pods → pods Pending → cluster autoscaler adds nodes → pods scheduled
Load drops → KEDA scales pods to 0 → nodes idle → cluster autoscaler removes nodes
```
