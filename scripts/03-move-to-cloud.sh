#!/usr/bin/env bash
# ============================================================
# Scenario: Move workload to a cloud cluster
# Usage: ./03-move-to-cloud.sh [azure|gcp]
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

CLOUD="${1:-gcp}"

case "${CLOUD}" in
  azure) BANNER="ARO / Azure / eastus" ;;
  gcp)   BANNER="OSD / GCP / us-east1" ;;
  *)     echo "Usage: $0 [azure|gcp]"; exit 1 ;;
esac

echo "=== Moving workload to cloud=${CLOUD} ==="
echo ""

# Patch the active placement to select the target cloud
oc patch placement cloud-placement \
  -n "${APP_NAMESPACE}" \
  --type merge \
  -p "{\"spec\":{\"predicates\":[{\"requiredClusterSelector\":{\"labelSelector\":{\"matchLabels\":{\"cloud\":\"${CLOUD}\",\"environment\":\"demo\"}}}}]}}"

echo ""
echo "✓ Placement patched: cloud=${CLOUD}"
echo "  Expected banner: ${BANNER}"
echo ""
echo "Watch placement decisions:"
echo "  oc get placementdecisions -n ${APP_NAMESPACE} -w"
echo ""
echo "Once deployed, get the Route:"
echo "  oc get route frontend -n ${APP_NAMESPACE} --context <managed-cluster-context>"
