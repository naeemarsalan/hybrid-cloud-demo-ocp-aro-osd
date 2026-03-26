#!/usr/bin/env bash
# ============================================================
# Configure OSD Cluster Autoscaler via OCM CLI
# Scales worker nodes 3→6 when burst pods can't be scheduled
# ============================================================
set -euo pipefail

OSD_CLUSTER_NAME="${1:-osd-gcp}"

echo "=== Configuring OSD Cluster Autoscaler ==="

# Get cluster ID
CLUSTER_ID=$(ocm list clusters --parameter search="name='${OSD_CLUSTER_NAME}'" --no-headers 2>/dev/null | awk '{print $1}')
if [ -z "$CLUSTER_ID" ]; then
  echo "ERROR: Cluster '${OSD_CLUSTER_NAME}' not found in OCM"
  exit 1
fi
echo "Cluster ID: $CLUSTER_ID"

# Create or update cluster autoscaler
echo "Creating cluster autoscaler..."
ocm post "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/autoscaler" <<'EOF' 2>/dev/null || \
ocm patch "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/autoscaler" <<'EOF'
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
echo "Cluster autoscaler configured"

# Enable autoscaling on worker machine pool
echo "Enabling worker pool autoscaling (3→6)..."
ocm patch "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/machine_pools/worker" <<'EOF'
{
  "autoscaling": {
    "min_replicas": 3,
    "max_replicas": 6
  }
}
EOF
echo "Worker pool autoscaling enabled"

echo ""
echo "============================================"
echo " OSD Cluster Autoscaler Configured"
echo "============================================"
echo " Worker nodes: 3 (min) → 6 (max)"
echo " Scale down: after 3m idle, <50% utilization"
echo " Max total nodes: 12"
echo "============================================"
