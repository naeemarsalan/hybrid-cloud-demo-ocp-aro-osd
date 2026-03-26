#!/usr/bin/env bash
# ============================================================
# Stop Burst: Remove Phoenix from OSD, stop load
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Stopping Burst ==="
echo ""

# Stop load generator
echo "Stopping load generator..."
oc_onprem -n "${PHOENIX_NAMESPACE}" scale deploy phoenix-loadgenerator --replicas=0 2>/dev/null || true

# Delete burst workloads from OSD
echo "Removing burst workloads from OSD..."
oc_osd delete -k "${PHOENIX_DIR}/manifests/burst" 2>/dev/null || true

echo "Waiting for cleanup..."
sleep 10

echo ""
echo "On-prem HPA (will scale down):"
oc_onprem -n "${PHOENIX_NAMESPACE}" get hpa 2>/dev/null || true

echo ""
echo "============================================"
echo " Burst Stopped"
echo "============================================"
