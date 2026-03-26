#!/usr/bin/env bash
# ============================================================
# Watch Phoenix pods across all clusters
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "============================================"
echo " Phoenix Multi-Cluster Status"
echo "============================================"
echo ""
echo "--- ON-PREM ---"
oc_onprem -n "${PHOENIX_NAMESPACE}" get pods -o wide 2>/dev/null || echo "  No pods"
echo ""
echo "HPA:"
oc_onprem -n "${PHOENIX_NAMESPACE}" get hpa 2>/dev/null || echo "  No HPA"
echo ""
echo "Resource usage:"
oc_onprem -n "${PHOENIX_NAMESPACE}" adm top pods 2>/dev/null || echo "  Metrics unavailable"
echo ""
echo "--- OSD (GCP) ---"
oc_osd -n "${PHOENIX_NAMESPACE}" get pods -o wide 2>/dev/null || echo "  No pods"
echo ""
echo "--- Routes ---"
echo "  On-prem: https://$(oc_onprem -n ${PHOENIX_NAMESPACE} get route phoenix -o jsonpath='{.spec.host}' 2>/dev/null || echo 'none')"
echo "  OSD:     https://$(oc_osd -n ${PHOENIX_NAMESPACE} get route phoenix -o jsonpath='{.spec.host}' 2>/dev/null || echo 'none')"
