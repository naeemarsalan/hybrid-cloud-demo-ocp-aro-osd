#!/usr/bin/env bash
# ============================================================
# Deploy ACM resources: Channel, Subscription, Placement
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Deploying ACM resources ==="

# Ensure namespace exists on the hub
oc get namespace "${APP_NAMESPACE}" &>/dev/null || \
  oc create namespace "${APP_NAMESPACE}"

# 1. ManagedClusterSet + Binding
echo "Creating ManagedClusterSet..."
oc apply -f "${REPO_ROOT}/acm/managedclusterset/hybrid-cloud-set.yaml"
oc apply -f "${REPO_ROOT}/acm/managedclusterset/hybrid-cloud-set-binding.yaml"

# 2. Channel
echo "Creating Channel..."
oc apply -f "${REPO_ROOT}/acm/channel/channel.yaml"

# 3. Placements
echo "Creating Placements..."
oc apply -f "${REPO_ROOT}/acm/placement/"

# 4. Subscription (defaults to cloud-placement → azure)
echo "Creating Subscription..."
oc apply -f "${REPO_ROOT}/acm/subscription/subscription.yaml"

# 5. Policies (optional governance)
echo "Creating Policies..."
oc apply -f "${REPO_ROOT}/acm/policies/"

echo ""
echo "✓ ACM resources deployed. Default placement: cloud=azure (ARO)"
echo ""
echo "Checking placement decisions..."
sleep 5
oc get placementdecisions -n "${APP_NAMESPACE}" -o wide 2>/dev/null || echo "(waiting for placement decisions...)"
echo ""
echo "Monitor with:"
echo "  oc get placementdecisions -n ${APP_NAMESPACE} -w"
echo "  oc get manifestwork -A | grep ${APP_NAMESPACE}"
