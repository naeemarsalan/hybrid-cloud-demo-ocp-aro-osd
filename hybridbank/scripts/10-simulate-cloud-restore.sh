#!/usr/bin/env bash
# ============================================================
# Part 2: Restore cloud ARO (automatic failback)
# Re-adds ARO label. Steady prioritizer keeps workloads on OSD
# unless forced back.
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Part 2: Restoring cloud ARO (automatic) ==="

# Re-add ARO cloud label
echo "Re-adding 'cloud=azure' label to ${ARO_CLUSTER_NAME}..."
oc --context="${HUB_CONTEXT}" label managedcluster "${ARO_CLUSTER_NAME}" cloud=azure --overwrite

echo ""
echo "✓ Cloud restore initiated"
echo ""
echo "Note: Steady prioritizer (weight 3) keeps workloads on OSD to avoid flapping."
echo "Both ARO and OSD now match the cloud Placement — Steady prefers the current cluster."
echo ""
echo "To force workloads back to ARO, temporarily remove OSD from the Placement:"
echo "  oc --context=${HUB_CONTEXT} label managedcluster ${OSD_CLUSTER_NAME} cloud-"
echo "  sleep 40"
echo "  oc --context=${HUB_CONTEXT} label managedcluster ${OSD_CLUSTER_NAME} cloud=gcp"
echo ""
echo "Compare to Part 1: 05-failback-cloud.sh required AppSet patch + manual postgres scale-down"
echo ""
echo "Verify:"
echo "  oc get placementdecisions -n openshift-gitops -o wide"
echo "  oc --context=${ARO_CLUSTER_NAME} get pods -n ${APP_NAMESPACE}"
echo "  oc --context=${OSD_CLUSTER_NAME} get pods -n ${APP_NAMESPACE}"
