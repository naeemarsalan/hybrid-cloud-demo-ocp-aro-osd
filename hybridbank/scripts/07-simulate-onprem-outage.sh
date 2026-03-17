#!/usr/bin/env bash
# ============================================================
# Part 2: Simulate on-prem outage (automatic failover)
# Just removes the label — ArgoCD + Placement handle the rest
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Part 2: Simulating on-prem outage (automatic failover) ==="

# Remove the on-prem label — that's it!
echo "Removing 'cloud=on-prem' label from ${OCP_CLUSTER_NAME}..."
oc --context="${HUB_CONTEXT}" label managedcluster "${OCP_CLUSTER_NAME}" cloud- 2>/dev/null || true

echo ""
echo "✓ On-prem outage simulated"
echo ""
echo "What happens automatically:"
echo "  - onprem Placement no longer matches → ArgoCD withdraws on-prem workloads"
echo "  - Cloud cluster already has postgres at replicas=1 (ArgoCD manages this from git)"
echo "  - No manual scaling needed (Part 1 required 'oc scale' commands)"
echo "  - api-gateway detects account/transaction services down → switches to limited mode"
echo "  - Gateway reads from cloud postgres (Portworx replica data)"
echo ""
echo "Compare to Part 1: 02-failover-onprem.sh required manual 'oc scale' of postgres"
echo ""
echo "Watching placement decisions (auto-failover)..."
echo "Press Ctrl+C to stop watching"
watch -n5 'oc --context=hub get placementdecisions -n openshift-gitops -o wide'
