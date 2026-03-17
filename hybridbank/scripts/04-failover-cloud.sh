#!/usr/bin/env bash
# ============================================================
# Cloud-to-cloud failover: ARO → OSD (lifeboat)
# Patches cloud ApplicationSet to use lifeboat placement
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Cloud-to-cloud failover: ARO → OSD ==="

# Step 1: Scale up standby postgres on OSD
echo "Scaling up standby postgres-core on OSD (${OSD_CLUSTER_NAME})..."
oc --context="${OSD_CLUSTER_NAME}" -n "${APP_NAMESPACE}" scale deploy postgres-core --replicas=1 2>/dev/null || true

echo "Waiting for standby postgres on OSD..."
oc --context="${OSD_CLUSTER_NAME}" -n "${APP_NAMESPACE}" rollout status deploy/postgres-core --timeout=120s 2>/dev/null || true

# Step 2: Patch ApplicationSet generator to use lifeboat placement (targets OSD)
echo "Patching cloud ApplicationSet to hybridbank-lifeboat placement..."
oc -n openshift-gitops patch applicationset hybridbank-cloud --type=json -p='[
  {"op":"replace","path":"/spec/generators/0/clusterDecisionResource/labelSelector/matchLabels/cluster.open-cluster-management.io~1placement","value":"hybridbank-lifeboat"}
]'

echo ""
echo "✓ Cloud failover initiated (ARO → OSD)"
echo ""
echo "What happened:"
echo "  - hybridbank-cloud ApplicationSet now targets hybridbank-lifeboat placement"
echo "  - ArgoCD will deploy api-gateway + frontend to OSD"
echo "  - OSD standby postgres-core scaled to 1 (Portworx replica data)"
echo "  - Gateway on OSD will operate in limited mode"
echo ""
echo "Waiting for ArgoCD to reconcile..."
sleep 10
echo "Placement decisions:"
oc get placementdecisions -n openshift-gitops -o wide 2>/dev/null || echo "(waiting...)"
echo ""
echo "Verify: oc get pods -n ${APP_NAMESPACE} --context=${OSD_CLUSTER_NAME}"
