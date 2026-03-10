#!/usr/bin/env bash
# ============================================================
# Scenario: Lifeboat failover
# Simulates ARO failure, watches ACM move workload to OSD
# Usage: ./06-lifeboat.sh [fail|restore]
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

ACTION="${1:-fail}"

# First, ensure we're using the lifeboat placement
setup_lifeboat() {
  echo "=== Setting up lifeboat placement ==="
  oc patch subscription online-boutique \
    -n "${APP_NAMESPACE}" \
    --type merge \
    -p '{"spec":{"placement":{"placementRef":{"name":"lifeboat-placement","kind":"Placement","apiGroup":"cluster.open-cluster-management.io"}}}}'
  echo "✓ Subscription now uses lifeboat-placement (cloud in [azure, gcp])"
  echo ""
}

case "${ACTION}" in
  fail)
    setup_lifeboat
    echo "=== Simulating ARO failure ==="
    echo "Patching ${ARO_CLUSTER_NAME}: hubAcceptsClient=false"
    echo ""
    oc patch managedcluster "${ARO_CLUSTER_NAME}" \
      --type merge \
      -p '{"spec":{"hubAcceptsClient":false}}'
    echo ""
    echo "✓ ARO marked as not accepted by hub"
    echo "  ACM will re-evaluate placement and move workload to OSD"
    echo ""
    echo "Watch the failover:"
    echo "  oc get managedclusters -w"
    echo "  oc get placementdecisions -n ${APP_NAMESPACE} -w"
    ;;

  restore)
    echo "=== Restoring ARO ==="
    echo "Patching ${ARO_CLUSTER_NAME}: hubAcceptsClient=true"
    echo ""
    oc patch managedcluster "${ARO_CLUSTER_NAME}" \
      --type merge \
      -p '{"spec":{"hubAcceptsClient":true}}'
    echo ""
    echo "✓ ARO restored — hub will accept the cluster again"
    echo ""
    echo "Watch cluster rejoin:"
    echo "  oc get managedclusters -w"
    ;;

  *)
    echo "Usage: $0 [fail|restore]"
    echo "  fail    — simulate ARO failure (hubAcceptsClient=false)"
    echo "  restore — restore ARO (hubAcceptsClient=true)"
    exit 1
    ;;
esac
