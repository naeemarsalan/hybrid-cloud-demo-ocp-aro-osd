#!/usr/bin/env bash
# ============================================================
# Start load generation against Phoenix
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

LOAD_REPLICAS="${1:-3}"

echo "=== Starting Phoenix Load Generation ==="
echo ""
echo "Scaling load generator to ${LOAD_REPLICAS} replicas..."
oc_onprem -n "${PHOENIX_NAMESPACE}" scale deploy phoenix-loadgenerator --replicas="${LOAD_REPLICAS}"
oc_onprem -n "${PHOENIX_NAMESPACE}" rollout status deploy/phoenix-loadgenerator --timeout=120s

echo ""
echo "============================================"
echo " Load Generation ACTIVE"
echo "============================================"
echo ""
echo "Watch contention:"
echo "  HPA:   KUBECONFIG=${ONPREM_KUBECONFIG} oc -n phoenix get hpa -w"
echo "  Pods:  KUBECONFIG=${ONPREM_KUBECONFIG} oc -n phoenix get pods -w"
echo "  Top:   KUBECONFIG=${ONPREM_KUBECONFIG} oc -n phoenix adm top pods"
echo ""
echo "When HPA hits max replicas -> burst to cloud:"
echo "  ./03-burst-to-cloud.sh"
