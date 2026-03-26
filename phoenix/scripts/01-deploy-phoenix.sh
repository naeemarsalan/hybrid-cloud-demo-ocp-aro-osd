#!/usr/bin/env bash
# ============================================================
# Deploy Phoenix AI Observability to on-prem + prepare OSD burst
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Deploying Phoenix AI Observability ==="
echo ""

# Grant anyuid SCC for Postgres on both clusters
echo "Granting anyuid SCC..."
oc_onprem adm policy add-scc-to-user anyuid -z default -n "${PHOENIX_NAMESPACE}" 2>/dev/null || true
oc_osd adm policy add-scc-to-user anyuid -z default -n "${PHOENIX_NAMESPACE}" 2>/dev/null || true

# Deploy base (namespace + secrets) to both clusters
echo "Deploying base resources..."
oc_onprem apply -k "${PHOENIX_DIR}/manifests/base"
oc_osd apply -k "${PHOENIX_DIR}/manifests/base"

# Deploy on-prem components (postgres + phoenix server + HPA)
echo "Deploying Phoenix on on-prem..."
oc_onprem apply -k "${PHOENIX_DIR}/manifests/onprem"

# Deploy load generator (starts at 0 replicas)
echo "Deploying load generator..."
oc_onprem apply -k "${PHOENIX_DIR}/manifests/loadgen"

# Wait for on-prem to be ready
echo "Waiting for PostgreSQL..."
oc_onprem -n "${PHOENIX_NAMESPACE}" rollout status statefulset/phoenix-postgres --timeout=180s

echo "Waiting for Phoenix server..."
oc_onprem -n "${PHOENIX_NAMESPACE}" rollout status deploy/phoenix --timeout=180s

PHOENIX_ROUTE=$(oc_onprem -n "${PHOENIX_NAMESPACE}" get route phoenix -o jsonpath='{.spec.host}' 2>/dev/null || echo "pending")

echo ""
echo "============================================"
echo " Phoenix Deployed on On-Prem"
echo "============================================"
echo " Phoenix UI: https://${PHOENIX_ROUTE}"
echo " Pods:       $(oc_onprem -n ${PHOENIX_NAMESPACE} get pods -l app=phoenix --no-headers 2>/dev/null | wc -l) running"
echo " HPA:        2-6 replicas (60% CPU threshold)"
echo "============================================"
echo ""
echo "Next: ./02-start-load.sh"
