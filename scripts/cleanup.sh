#!/usr/bin/env bash
# ============================================================
# Cleanup: Remove all demo resources from the hub
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Cleaning up Hybrid Cloud Demo ==="
echo ""
read -rp "This will delete ALL demo resources from the hub. Continue? [y/N] " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""

# Delete in reverse order of creation
echo "Deleting Subscription..."
oc delete subscription online-boutique -n "${APP_NAMESPACE}" --ignore-not-found

echo "Deleting Policies..."
oc delete -f "${REPO_ROOT}/acm/policies/" --ignore-not-found 2>/dev/null || true

echo "Deleting Placements..."
oc delete -f "${REPO_ROOT}/acm/placement/" --ignore-not-found 2>/dev/null || true

echo "Deleting Channel..."
oc delete -f "${REPO_ROOT}/acm/channel/channel.yaml" --ignore-not-found 2>/dev/null || true

echo "Deleting ManagedClusterSet Binding..."
oc delete -f "${REPO_ROOT}/acm/managedclusterset/hybrid-cloud-set-binding.yaml" --ignore-not-found 2>/dev/null || true

echo "Deleting ManagedClusterSet..."
oc delete -f "${REPO_ROOT}/acm/managedclusterset/hybrid-cloud-set.yaml" --ignore-not-found 2>/dev/null || true

echo "Deleting Git credentials Secret..."
oc delete secret git-credentials -n "${APP_NAMESPACE}" --ignore-not-found

echo "Deleting namespace..."
oc delete namespace "${APP_NAMESPACE}" --ignore-not-found

# Restore ARO if it was failed
echo "Ensuring ARO is restored..."
oc patch managedcluster "${ARO_CLUSTER_NAME}" \
  --type merge \
  -p '{"spec":{"hubAcceptsClient":true}}' 2>/dev/null || true

# Remove cluster labels (optional)
echo ""
read -rp "Remove demo labels from ManagedClusters? [y/N] " REMOVE_LABELS
if [[ "${REMOVE_LABELS}" == "y" || "${REMOVE_LABELS}" == "Y" ]]; then
  for CLUSTER in "${OCP_CLUSTER_NAME}" "${ARO_CLUSTER_NAME}" "${OSD_CLUSTER_NAME}"; do
    echo "Removing labels from ${CLUSTER}..."
    oc label managedcluster "${CLUSTER}" \
      cloud- environment- region- tier- managed-service- \
      cluster.open-cluster-management.io/clusterset- \
      --overwrite 2>/dev/null || true
  done
fi

echo ""
echo "✓ Cleanup complete"
