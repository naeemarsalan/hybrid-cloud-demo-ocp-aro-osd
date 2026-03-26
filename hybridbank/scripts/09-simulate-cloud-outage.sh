#!/usr/bin/env bash
# ============================================================
# Part 2: Simulate cloud outage ARO → OSD (automatic failover)
# Just removes the cloud label — Steady prioritizer handles failover
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Part 2: Simulating cloud outage ARO → OSD (automatic) ==="

# Remove ARO cloud label — Placement auto-selects OSD
echo "Removing 'cloud=azure' label from ${ARO_CLUSTER_NAME}..."
oc --context="${HUB_CONTEXT}" label managedcluster "${ARO_CLUSTER_NAME}" cloud- 2>/dev/null || true

echo ""
echo "✓ Cloud outage simulated"
echo ""
CURRENT_CLOUD=$(oc --context="${HUB_CONTEXT}" get placementdecisions -n openshift-gitops \
  -l cluster.open-cluster-management.io/placement=hybridbank-cloud \
  -o jsonpath='{.items[0].status.decisions[0].clusterName}' 2>/dev/null)
echo "What happens automatically:"
echo "  - cloud Placement (In: [azure, gcp]) no longer matches ${ARO_CLUSTER_NAME}"
if [ "${CURRENT_CLOUD}" = "${ARO_CLUSTER_NAME}" ]; then
  echo "  - Workloads were on ARO → Placement selects OSD as the remaining match"
  echo "  - ArgoCD moves api-gateway, frontend, postgres to OSD (~3 min)"
else
  echo "  - Workloads already on ${CURRENT_CLOUD} → no workload movement (ARO had no pods)"
fi
echo "  - Postgres on the selected cloud cluster is already at replicas=1 (managed by ArgoCD)"
echo "  - No manual ApplicationSet patching needed (Part 1 required AppSet patch)"
echo "  - No manual postgres scaling needed (Part 1 required 'oc scale')"
echo ""
echo "Compare to Part 1: 04-failover-cloud.sh required AppSet patch + manual postgres scale-up"
echo ""
echo "Watching placement decisions (Steady → OSD in ~30s)..."
echo "Press Ctrl+C to stop watching"
watch -n5 'oc --context=hub get placementdecisions -n openshift-gitops -o wide'
