#!/usr/bin/env bash
# ============================================================
# Simulate on-prem outage: remove cluster label so ACM/ArgoCD
# withdraws on-prem workloads, then scale up standby postgres on ARO
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Simulating on-prem outage ==="

# Step 1: Remove the on-prem label from the hybrid ManagedCluster
# This causes the onprem placement to no longer match → ArgoCD removes resources
echo "Removing 'cloud=on-prem' label from hybrid ManagedCluster..."
oc --context="${HUB_CONTEXT}" label managedcluster "${OCP_CLUSTER_NAME}" cloud- 2>/dev/null || true

echo "Waiting for ArgoCD to withdraw on-prem resources..."
sleep 5

# Step 2: Scale up standby postgres on ARO
echo "Scaling up standby postgres-core on ARO (${ARO_CLUSTER_NAME})..."
oc --context="${ARO_CLUSTER_NAME}" -n "${APP_NAMESPACE}" scale deploy postgres-core --replicas=1

echo "Waiting for standby postgres to be ready..."
oc --context="${ARO_CLUSTER_NAME}" -n "${APP_NAMESPACE}" rollout status deploy/postgres-core --timeout=120s

echo ""
echo "✓ On-prem outage simulated"
echo ""
echo "What happened:"
echo "  - Removed 'cloud=on-prem' label from hybrid → onprem placement no longer matches"
echo "  - ArgoCD removes postgres-core, postgres-archive, account-service, transaction-service from on-prem"
echo "  - ARO standby postgres-core → replicas=1 (serving from Portworx replica)"
echo ""
echo "Expected behavior:"
echo "  - api-gateway detects account-service + transaction-service are down"
echo "  - Mode switches to 'limited'"
echo "  - Gateway reads from local standby postgres-core (Portworx replica data)"
echo "  - PII data unavailable (archive DB is on-prem only)"
echo "  - Transfers disabled"
echo ""
echo "Verify: curl https://\$(oc --context=${ARO_CLUSTER_NAME} get route hybridbank -n ${APP_NAMESPACE} -o jsonpath='{.spec.host}')/api/health"
