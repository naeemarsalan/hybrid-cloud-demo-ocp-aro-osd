#!/usr/bin/env bash
# ============================================================
# Restore on-prem: re-add cluster label so ACM/ArgoCD deploys
# on-prem workloads, then scale down standby
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Restoring on-prem services ==="

# Step 1: Scale down standby postgres on ARO
echo "Scaling down standby postgres-core on ARO..."
oc --context="${ARO_CLUSTER_NAME}" -n "${APP_NAMESPACE}" scale deploy postgres-core --replicas=0

# Step 2: Re-add the on-prem label to hybrid ManagedCluster
# This causes onprem placement to match again → ArgoCD deploys resources
echo "Re-adding 'cloud=on-prem' label to hybrid ManagedCluster..."
oc --context="${HUB_CONTEXT}" label managedcluster "${OCP_CLUSTER_NAME}" cloud=on-prem --overwrite

echo "Waiting for ArgoCD to deploy on-prem resources..."
sleep 10

# Step 3: Wait for on-prem services to be ready
echo "Waiting for on-prem services..."
oc --context="${OCP_CLUSTER_NAME}" -n "${APP_NAMESPACE}" rollout status deploy/postgres-core --timeout=120s 2>/dev/null || true
oc --context="${OCP_CLUSTER_NAME}" -n "${APP_NAMESPACE}" rollout status deploy/postgres-archive --timeout=120s 2>/dev/null || true
oc --context="${OCP_CLUSTER_NAME}" -n "${APP_NAMESPACE}" rollout status deploy/account-service --timeout=120s 2>/dev/null || true
oc --context="${OCP_CLUSTER_NAME}" -n "${APP_NAMESPACE}" rollout status deploy/transaction-service --timeout=120s 2>/dev/null || true

echo ""
echo "✓ On-prem restored"
echo ""
echo "What happened:"
echo "  - ARO standby postgres-core → replicas=0"
echo "  - Re-added 'cloud=on-prem' label → onprem placement matches hybrid again"
echo "  - ArgoCD deploys postgres-core, postgres-archive, account-service, transaction-service"
echo "  - api-gateway detects services are back → mode='normal'"
echo ""
echo "Verify: curl https://\$(oc --context=${ARO_CLUSTER_NAME} get route hybridbank -n ${APP_NAMESPACE} -o jsonpath='{.spec.host}')/api/health"
