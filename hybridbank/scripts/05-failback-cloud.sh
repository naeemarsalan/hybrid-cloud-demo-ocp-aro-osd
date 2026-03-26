#!/usr/bin/env bash
# ============================================================
# Cloud failback: OSD → ARO (restore normal)
# Patches cloud ApplicationSet back to cloud placement (ARO)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Cloud failback: OSD → ARO ==="

# Step 1: Patch ApplicationSet back to cloud placement (ARO)
echo "Patching cloud ApplicationSet back to hybridbank-cloud placement..."
oc -n openshift-gitops patch applicationset hybridbank-cloud --type=json -p='[
  {"op":"replace","path":"/spec/generators/0/clusterDecisionResource/labelSelector/matchLabels/cluster.open-cluster-management.io~1placement","value":"hybridbank-cloud"}
]'

# Step 2: Scale down standby postgres on OSD
echo "Scaling down standby postgres-core on OSD..."
oc --context="${OSD_CLUSTER_NAME}" -n "${APP_NAMESPACE}" scale deploy postgres-core --replicas=0 2>/dev/null || true

echo ""
echo "✓ Cloud failback initiated (OSD → ARO)"
echo ""
echo "What happened:"
echo "  - hybridbank-cloud ApplicationSet restored to hybridbank-cloud placement (ARO)"
echo "  - ArgoCD will deploy api-gateway + frontend back to ARO"
echo "  - OSD standby postgres-core scaled back to 0"
echo ""
echo "Waiting for ArgoCD to reconcile..."
sleep 10
echo "Placement decisions:"
oc get placementdecisions -n openshift-gitops -o wide 2>/dev/null || echo "(waiting...)"
echo ""
echo "Verify: oc get pods -n ${APP_NAMESPACE} --context=${ARO_CLUSTER_NAME}"
