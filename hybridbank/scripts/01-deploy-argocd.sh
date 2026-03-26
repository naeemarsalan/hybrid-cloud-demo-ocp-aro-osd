#!/usr/bin/env bash
# ============================================================
# Deploy HybridBank via ArgoCD ApplicationSets (push model)
# Migrates from ACM Subscriptions to ArgoCD ApplicationSets
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Deploying HybridBank via ArgoCD ApplicationSets ==="

# --- Pre-flight checks ---
echo "Running pre-flight checks..."

if ! oc get crd gitopsclusters.apps.open-cluster-management.io &>/dev/null; then
  echo "ERROR: GitOpsCluster CRD not found. Install the ACM GitOps integration."
  exit 1
fi

if ! oc get argocd openshift-gitops -n openshift-gitops &>/dev/null 2>&1; then
  # Try the newer ArgoCD CRD name
  if ! oc get argocds.argoproj.io openshift-gitops -n openshift-gitops &>/dev/null 2>&1; then
    echo "WARNING: Could not verify ArgoCD instance in openshift-gitops namespace."
  fi
fi

echo "Pre-flight checks passed."

# --- Label on-prem cluster as restricted data zone ---
echo "Labeling ${OCP_CLUSTER_NAME} with data-zone=restricted..."
oc --context="${HUB_CONTEXT}" label managedcluster "${OCP_CLUSTER_NAME}" data-zone=restricted --overwrite

# --- Clean cutover: delete old Subscriptions + Channel ---
echo "Removing old ACM Subscriptions and Channel (clean cutover)..."
oc delete subscription hybridbank-base hybridbank-onprem hybridbank-cloud -n "${APP_NAMESPACE}" 2>/dev/null || true
oc delete channel hybridbank-git -n "${APP_NAMESPACE}" 2>/dev/null || true

# --- Apply ClusterSetBinding in openshift-gitops namespace ---
echo "Creating ManagedClusterSetBinding in openshift-gitops..."
oc apply -f "${HYBRIDBANK_DIR}/argocd/clusterset-binding-gitops.yaml"

# --- Apply GitOpsCluster ---
echo "Creating GitOpsCluster..."
oc apply -f "${HYBRIDBANK_DIR}/argocd/gitopscluster.yaml"

echo "Waiting for ArgoCD cluster secrets..."
sleep 5

# --- Apply ApplicationSets (each includes its Placement) ---
echo "Creating ApplicationSets..."
oc apply -f "${HYBRIDBANK_DIR}/argocd/hybridbank-base-appset.yaml"
oc apply -f "${HYBRIDBANK_DIR}/argocd/hybridbank-onprem-appset.yaml"
oc apply -f "${HYBRIDBANK_DIR}/argocd/hybridbank-cloud-appset.yaml"

# --- Apply lifeboat placement ---
echo "Creating lifeboat placement..."
oc apply -f "${HYBRIDBANK_DIR}/argocd/lifeboat-placement.yaml"

# --- Apply PII data locality policy ---
echo "Creating PII data locality policy..."
oc apply -f "${HYBRIDBANK_DIR}/acm/policies/pii-data-locality-policy.yaml"

# --- Grant anyuid SCC to postgres-sa on all clusters ---
echo "Granting anyuid SCC to postgres-sa..."
for ctx in "${OCP_CLUSTER_NAME}" "${ARO_CLUSTER_NAME}" "${OSD_CLUSTER_NAME}"; do
  oc --context="${ctx}" adm policy add-scc-to-user anyuid -z postgres-sa -n "${APP_NAMESPACE}" 2>/dev/null || true
done

# --- Scale down standby postgres on cloud clusters ---
echo "Scaling standby postgres to 0 on cloud clusters..."
sleep 15  # wait for ApplicationSets to propagate
for ctx in "${ARO_CLUSTER_NAME}" "${OSD_CLUSTER_NAME}"; do
  oc --context="${ctx}" -n "${APP_NAMESPACE}" scale deploy postgres-core --replicas=0 2>/dev/null || true
done

echo ""
echo "✓ HybridBank ArgoCD deployment complete"
echo ""
echo "ApplicationSets:"
echo "  hybridbank-base    → all demo clusters (namespace + configmap)"
echo "  hybridbank-onprem  → on-prem (postgres, account-service, transaction-service)"
echo "  hybridbank-cloud   → ARO (api-gateway, frontend, standby postgres)"
echo ""
echo "Verification:"
echo "  oc get secrets -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster"
echo "  oc get placementdecisions -n openshift-gitops -o wide"
echo "  oc get applicationsets -n openshift-gitops"
echo "  oc get applications -n openshift-gitops -l app.kubernetes.io/part-of=hybridbank"
echo "  oc get policy pii-data-locality -n hybridbank"
