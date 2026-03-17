#!/usr/bin/env bash
# ============================================================
# HybridBank — Configuration
# ============================================================
# Sources the main project config and adds HybridBank-specific settings.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source the main project config
source "${REPO_ROOT}/scripts/config.sh"

# Override namespace for HybridBank
export APP_NAMESPACE="hybridbank"

# Container image registry
export IMAGE_REGISTRY="docker.io/naeemarsalan"
export IMAGE_TAG="latest"

# Image names
export FRONTEND_IMAGE="${IMAGE_REGISTRY}/hybridbank-frontend:${IMAGE_TAG}"
export GATEWAY_IMAGE="${IMAGE_REGISTRY}/hybridbank-api-gateway:${IMAGE_TAG}"
export ACCOUNT_IMAGE="${IMAGE_REGISTRY}/hybridbank-account-service:${IMAGE_TAG}"
export TRANSACTION_IMAGE="${IMAGE_REGISTRY}/hybridbank-transaction-service:${IMAGE_TAG}"

# Paths
export HYBRIDBANK_DIR="${REPO_ROOT}/hybridbank"
export WEBAPP_DIR="${REPO_ROOT}/webapp"
