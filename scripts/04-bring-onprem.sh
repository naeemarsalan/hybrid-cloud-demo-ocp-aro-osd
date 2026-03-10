#!/usr/bin/env bash
# ============================================================
# Scenario: Bring workload back on-prem
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Moving workload on-prem (cloud=on-prem) ==="
echo ""

oc patch placement cloud-placement \
  -n "${APP_NAMESPACE}" \
  --type merge \
  -p '{"spec":{"predicates":[{"requiredClusterSelector":{"labelSelector":{"matchLabels":{"cloud":"on-prem","environment":"demo"}}}}]}}'

echo ""
echo "✓ Placement patched: cloud=on-prem"
echo "  Expected banner: OCP / On-Prem / datacenter-1"
echo ""
echo "Watch placement decisions:"
echo "  oc get placementdecisions -n ${APP_NAMESPACE} -w"
