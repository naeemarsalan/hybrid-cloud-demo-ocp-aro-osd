#!/usr/bin/env bash
# ============================================================
# Build and push HybridBank container images
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Building and pushing HybridBank images ==="

# Build and push api-gateway
echo "Building api-gateway..."
docker build -t "${GATEWAY_IMAGE}" "${WEBAPP_DIR}/services/api-gateway"
docker push "${GATEWAY_IMAGE}"
echo "  ✓ ${GATEWAY_IMAGE}"

# Build and push account-service
echo "Building account-service..."
docker build -t "${ACCOUNT_IMAGE}" "${WEBAPP_DIR}/services/account-service"
docker push "${ACCOUNT_IMAGE}"
echo "  ✓ ${ACCOUNT_IMAGE}"

# Build and push transaction-service
echo "Building transaction-service..."
docker build -t "${TRANSACTION_IMAGE}" "${WEBAPP_DIR}/services/transaction-service"
docker push "${TRANSACTION_IMAGE}"
echo "  ✓ ${TRANSACTION_IMAGE}"

# Build and push frontend (needs nginx on port 8080 for OpenShift)
echo "Building frontend..."
docker build -t "${FRONTEND_IMAGE}" "${WEBAPP_DIR}/project"
docker push "${FRONTEND_IMAGE}"
echo "  ✓ ${FRONTEND_IMAGE}"

echo ""
echo "=== All images pushed ==="
echo "  ${GATEWAY_IMAGE}"
echo "  ${ACCOUNT_IMAGE}"
echo "  ${TRANSACTION_IMAGE}"
echo "  ${FRONTEND_IMAGE}"
