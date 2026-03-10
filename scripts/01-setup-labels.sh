#!/usr/bin/env bash
# ============================================================
# Label ManagedClusters for placement decisions
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Labeling ManagedClusters ==="

# OCP on-prem (hub / local-cluster)
echo "Labeling ${OCP_CLUSTER_NAME}..."
oc label managedcluster "${OCP_CLUSTER_NAME}" \
  cloud=on-prem \
  environment=demo \
  region=datacenter-1 \
  tier=tier-0 \
  managed-service=false \
  cluster.open-cluster-management.io/clusterset=hybrid-cloud-demo \
  --overwrite

# ARO on Azure
echo "Labeling ${ARO_CLUSTER_NAME}..."
oc label managedcluster "${ARO_CLUSTER_NAME}" \
  cloud=azure \
  environment=demo \
  region=eastus \
  tier=tier-0 \
  managed-service=true \
  cluster.open-cluster-management.io/clusterset=hybrid-cloud-demo \
  --overwrite

# OSD on GCP
echo "Labeling ${OSD_CLUSTER_NAME}..."
oc label managedcluster "${OSD_CLUSTER_NAME}" \
  cloud=gcp \
  environment=demo \
  region=us-east1 \
  tier=tier-0 \
  managed-service=true \
  cluster.open-cluster-management.io/clusterset=hybrid-cloud-demo \
  --overwrite

echo ""
echo "✓ All clusters labeled. Verify with:"
echo "  oc get managedclusters --show-labels"
