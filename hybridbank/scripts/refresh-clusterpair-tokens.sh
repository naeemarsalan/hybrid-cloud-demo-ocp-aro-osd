#!/usr/bin/env bash
# ============================================================
# Refresh ClusterPair tokens using long-lived ServiceAccount tokens
# Replaces short-lived kubeconfig tokens that expire
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

SA_NAME="stork-replication-sa"
SA_SECRET_NAME="stork-replication-sa-token"

echo "=== Refreshing ClusterPair tokens (SA-based, long-lived) ==="

# Function: create SA + token on destination, patch ClusterPair on source
refresh_pair() {
  local dest_ctx="$1"
  local source_ctx="$2"
  local pair_name="$3"

  echo ""
  echo "--- Refreshing ClusterPair '${pair_name}' (dest=${dest_ctx}, source=${source_ctx}) ---"

  # 1. Create ServiceAccount on destination
  echo "  Creating ServiceAccount ${SA_NAME} on ${dest_ctx}..."
  oc --context="${dest_ctx}" create sa "${SA_NAME}" -n "${APP_NAMESPACE}" 2>/dev/null || true

  # 2. Create ClusterRoleBinding on destination (Stork needs full access)
  echo "  Creating ClusterRoleBinding on ${dest_ctx}..."
  oc --context="${dest_ctx}" create clusterrolebinding "${SA_NAME}-admin" \
    --clusterrole=cluster-admin \
    --serviceaccount="${APP_NAMESPACE}:${SA_NAME}" 2>/dev/null || true

  # 3. Create long-lived token Secret on destination
  echo "  Creating long-lived token Secret on ${dest_ctx}..."
  cat <<EOF | oc --context="${dest_ctx}" apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SA_SECRET_NAME}
  namespace: ${APP_NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF

  # 4. Wait for token to be populated by the token controller
  echo "  Waiting for token population..."
  local retries=0
  local sa_token=""
  while [ -z "${sa_token}" ] && [ ${retries} -lt 30 ]; do
    sa_token=$(oc --context="${dest_ctx}" -n "${APP_NAMESPACE}" get secret "${SA_SECRET_NAME}" \
      -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null) || true
    if [ -z "${sa_token}" ]; then
      sleep 2
      retries=$((retries + 1))
    fi
  done

  if [ -z "${sa_token}" ]; then
    echo "  ERROR: Failed to get SA token from ${dest_ctx} after 60s"
    return 1
  fi

  echo "  Token obtained (${#sa_token} chars)"

  # 5. Patch the Stork ClusterPair on source with the SA token
  echo "  Patching ClusterPair '${pair_name}' on ${source_ctx}..."
  oc --context="${source_ctx}" patch clusterpair "${pair_name}" -n "${APP_NAMESPACE}" --type=merge \
    -p "{\"spec\":{\"options\":{\"token\":\"${sa_token}\"}}}"

  echo "  ✓ ClusterPair '${pair_name}' refreshed"
}

# Refresh both ClusterPairs (on-prem → ARO, on-prem → OSD)
refresh_pair "${ARO_CLUSTER_NAME}" "${OCP_CLUSTER_NAME}" "aro-east"
refresh_pair "${OSD_CLUSTER_NAME}" "${OCP_CLUSTER_NAME}" "osd-gcp"

echo ""
echo "✓ All ClusterPair tokens refreshed"
echo ""
echo "Verify:"
echo "  oc --context=${OCP_CLUSTER_NAME} get clusterpair -n ${APP_NAMESPACE}"
echo "  oc --context=${OCP_CLUSTER_NAME} get clusterpair aro-east -n ${APP_NAMESPACE} -o jsonpath='{.status}'"
echo "  oc --context=${OCP_CLUSTER_NAME} get clusterpair osd-gcp -n ${APP_NAMESPACE} -o jsonpath='{.status}'"
