#!/usr/bin/env bash
# ============================================================
# Scenario: Deploy to ALL clusters simultaneously
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Deploying to ALL clusters ==="
echo ""

# Switch subscription to use the all-clusters placement
oc patch subscription online-boutique \
  -n "${APP_NAMESPACE}" \
  --type merge \
  -p '{"spec":{"placement":{"placementRef":{"name":"all-clusters-placement","kind":"Placement","apiGroup":"cluster.open-cluster-management.io"}}}}'

echo ""
echo "✓ Subscription now references all-clusters-placement"
echo "  App will deploy to all clusters with environment=demo"
echo ""
echo "Watch placement decisions:"
echo "  oc get placementdecisions -n ${APP_NAMESPACE} -w"
echo ""
echo "Check ManifestWork on all clusters:"
echo "  oc get manifestwork -A | grep ${APP_NAMESPACE}"
