#!/usr/bin/env bash
# ============================================================
# Burst to Cloud: Deploy Phoenix pods to OSD
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Burst to Cloud: Scaling Phoenix to OSD ==="
echo ""

# Show current on-prem contention
echo "Current on-prem state:"
oc_onprem -n "${PHOENIX_NAMESPACE}" get hpa 2>/dev/null || true
echo ""

# Deploy burst manifests to OSD
echo "Deploying Phoenix burst replicas to OSD..."
oc_osd apply -k "${PHOENIX_DIR}/manifests/burst"

echo "Waiting for OSD burst pods..."
oc_osd -n "${PHOENIX_NAMESPACE}" rollout status statefulset/phoenix-postgres --timeout=180s 2>/dev/null || true
oc_osd -n "${PHOENIX_NAMESPACE}" rollout status deploy/phoenix --timeout=180s

OSD_ROUTE=$(oc_osd -n "${PHOENIX_NAMESPACE}" get route phoenix -o jsonpath='{.spec.host}' 2>/dev/null || echo "pending")

echo ""
echo "============================================"
echo " Burst to Cloud ACTIVE"
echo "============================================"
echo ""
echo " On-prem:  2-6 pods (HPA controlled)"
echo " OSD:      3 burst pods"
echo ""
echo " On-prem UI: https://$(oc_onprem -n ${PHOENIX_NAMESPACE} get route phoenix -o jsonpath='{.spec.host}' 2>/dev/null)"
echo " OSD UI:     https://${OSD_ROUTE}"
echo ""
echo " To stop burst: ./04-burst-stop.sh"
