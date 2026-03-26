#!/usr/bin/env bash
# ============================================================
# Part 2: Restore on-prem (automatic failback)
# Just re-adds the label — no manual postgres scaling
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Part 2: Restoring on-prem services (automatic) ==="

# Re-add the on-prem label — that's it!
echo "Re-adding 'cloud=on-prem' label to ${OCP_CLUSTER_NAME}..."
oc --context="${HUB_CONTEXT}" label managedcluster "${OCP_CLUSTER_NAME}" cloud=on-prem --overwrite

echo ""
echo "✓ On-prem restore initiated"
echo ""
echo "What happens automatically:"
echo "  - onprem Placement matches ${OCP_CLUSTER_NAME} again"
echo "  - ArgoCD deploys postgres-core, postgres-archive, account-service, transaction-service"
echo "  - Cloud cluster unaffected (postgres stays at replicas=1, managed by ArgoCD)"
echo "  - No manual scaling needed (Part 1 required 'oc scale' to 0 on cloud)"
echo "  - api-gateway detects services back → mode switches to 'normal'"
echo ""
echo "Compare to Part 1: 03-failback-onprem.sh required manual scale-down of standby postgres"
echo ""
echo "Verify:"
echo "  oc get placementdecisions -n openshift-gitops -o wide"
echo "  oc --context=${OCP_CLUSTER_NAME} get pods -n ${APP_NAMESPACE}"
