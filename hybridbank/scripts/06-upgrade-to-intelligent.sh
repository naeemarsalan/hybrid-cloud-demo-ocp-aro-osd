#!/usr/bin/env bash
# ============================================================
# Upgrade to intelligent placement (Part 2)
# Patches Placements with tolerations + Steady prioritizer,
# deploys Gatekeeper + PX readiness policies,
# and refreshes ClusterPair tokens with long-lived SA tokens
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Upgrading to Intelligent Automated Placement (Part 2) ==="

# Step 1: Patch cloud placement — multi-cloud selector + Steady prioritizer + tolerations
# Note: changing the selector from cloud=azure to cloud In [azure,gcp] causes ACM to
# re-evaluate cluster selection. The Steady prioritizer anchors to the NEW decision,
# so workloads may move (e.g. from ARO to OSD) based on ResourceAllocatable scores.
echo "Patching hybridbank-cloud placement (multi-cloud + Steady + tolerations)..."
oc --context="${HUB_CONTEXT}" patch placement hybridbank-cloud -n openshift-gitops --type=merge -p '{
  "spec": {
    "predicates": [{"requiredClusterSelector": {"labelSelector": {
      "matchExpressions": [{"key": "cloud", "operator": "In", "values": ["azure", "gcp"]}],
      "matchLabels": {"environment": "demo"}
    }}}],
    "prioritizerPolicy": {
      "mode": "Exact",
      "configurations": [
        {"scoreCoordinate": {"type": "BuiltIn", "builtIn": "Steady"}, "weight": 3},
        {"scoreCoordinate": {"type": "BuiltIn", "builtIn": "ResourceAllocatableCPU"}, "weight": 1},
        {"scoreCoordinate": {"type": "BuiltIn", "builtIn": "ResourceAllocatableMemory"}, "weight": 1}
      ]
    },
    "tolerations": [{"key": "cluster.open-cluster-management.io/unreachable", "operator": "Exists", "tolerationSeconds": 30}]
  }
}'

# Step 2: Patch onprem placement — tolerations
echo "Patching hybridbank-onprem placement (tolerations)..."
oc --context="${HUB_CONTEXT}" patch placement hybridbank-onprem -n openshift-gitops --type=merge -p '{
  "spec": {
    "tolerations": [{"key": "cluster.open-cluster-management.io/unreachable", "operator": "Exists", "tolerationSeconds": 30}]
  }
}'

# Step 3: Delete lifeboat placement (merged into cloud via multi-cloud selector)
echo "Deleting hybridbank-lifeboat placement (merged into cloud)..."
oc --context="${HUB_CONTEXT}" delete placement hybridbank-lifeboat -n openshift-gitops 2>/dev/null || true

# Step 4: Ensure ManagedClusterSetBinding exists in hybridbank namespace
# (Required for policy Placements to select clusters)
echo "Ensuring ManagedClusterSetBinding in ${APP_NAMESPACE} namespace..."
oc --context="${HUB_CONTEXT}" apply -f "${HYBRIDBANK_DIR}/acm/clusterset-binding.yaml"

# Step 5: Ensure governance addons are enabled on managed clusters
echo "Ensuring governance policy addons on managed clusters..."
for cluster in "${OCP_CLUSTER_NAME}" "${ARO_CLUSTER_NAME}" "${OSD_CLUSTER_NAME}"; do
  for addon in governance-policy-framework config-policy-controller; do
    oc --context="${HUB_CONTEXT}" get managedclusteraddon "${addon}" -n "${cluster}" &>/dev/null || \
    cat <<EOF | oc --context="${HUB_CONTEXT}" apply -f -
apiVersion: addon.open-cluster-management.io/v1alpha1
kind: ManagedClusterAddOn
metadata:
  name: ${addon}
  namespace: ${cluster}
spec:
  installNamespace: open-cluster-management-agent-addon
EOF
  done
done

# Step 6: Deploy Gatekeeper PII constraint via ACM Policy
echo "Applying Gatekeeper PII constraint policy..."
oc --context="${HUB_CONTEXT}" apply -f "${HYBRIDBANK_DIR}/acm/gatekeeper/pii-restricted-zone.yaml"

# Step 7: Deploy PX data readiness policy
echo "Applying PX data readiness policy..."
oc --context="${HUB_CONTEXT}" apply -f "${HYBRIDBANK_DIR}/acm/policies/px-data-readiness-policy.yaml"

# Step 8: Refresh ClusterPair tokens using long-lived SA tokens
echo "Refreshing ClusterPair tokens..."
"${SCRIPT_DIR}/refresh-clusterpair-tokens.sh"

# Step 9: Wait for ApplicationSet to pick up the new PlacementDecision
echo ""
echo "Waiting for ApplicationSet to reconcile (up to 3 minutes)..."
SELECTED=""
for i in $(seq 1 18); do
  SELECTED=$(oc --context="${HUB_CONTEXT}" get placementdecisions -n openshift-gitops \
    -l cluster.open-cluster-management.io/placement=hybridbank-cloud \
    -o jsonpath='{.items[0].status.decisions[0].clusterName}' 2>/dev/null)
  APP_TARGET=$(oc --context="${HUB_CONTEXT}" get applicationset hybridbank-cloud -n openshift-gitops \
    -o jsonpath='{.status.resources[0].name}' 2>/dev/null)
  if [[ "${APP_TARGET}" == *"${SELECTED}"* ]] && [ -n "${SELECTED}" ]; then
    echo "  ApplicationSet targeting ${SELECTED} ✓"
    break
  fi
  echo "  Placement selected: ${SELECTED}, AppSet targeting: ${APP_TARGET:-pending}... (${i}/18)"
  sleep 10
done

echo ""
echo "✓ Upgrade to Part 2 complete"
echo ""
echo "What changed:"
echo "  - hybridbank-cloud Placement: multi-cloud selector (azure + gcp) + Steady prioritizer + 30s toleration"
echo "  - hybridbank-onprem Placement: 30s unreachable toleration"
echo "  - hybridbank-lifeboat Placement: deleted (merged into cloud)"
echo "  - Cloud workloads now on: ${SELECTED} (Steady anchors here going forward)"
echo "  - Postgres on cloud: already at replicas=1 (git manifest default, ArgoCD selfHeal enforces)"
echo "  - Gatekeeper: PII deployments blocked on unrestricted clusters"
echo "  - PX data readiness: clusters checked for pgdata-core PVC Bound"
echo "  - ClusterPair tokens: SA-based (long-lived, no expiry)"
echo ""
echo "Verification:"
echo "  oc --context=${HUB_CONTEXT} get placement -n openshift-gitops"
echo "  oc --context=${HUB_CONTEXT} get placementdecisions -n openshift-gitops -o wide"
echo "  oc --context=${HUB_CONTEXT} get policy -n hybridbank"
echo "  oc --context=${SELECTED:-aro} get pods -n ${APP_NAMESPACE}"
echo "  oc --context=${OCP_CLUSTER_NAME} get clusterpair -n ${APP_NAMESPACE}"
