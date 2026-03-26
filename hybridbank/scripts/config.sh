#!/usr/bin/env bash
# ============================================================
# HybridBank — Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Cluster contexts (oc --context=)
export HUB_CONTEXT="hub"
export OCP_CLUSTER_NAME="prem"
export ARO_CLUSTER_NAME="aro"
export OSD_CLUSTER_NAME="osd"

# Application
export APP_NAMESPACE="hybridbank"

# Container images
export IMAGE_REGISTRY="docker.io/naeemarsalan"
export IMAGE_TAG="latest"
export FRONTEND_IMAGE="${IMAGE_REGISTRY}/hybridbank-frontend:${IMAGE_TAG}"
export GATEWAY_IMAGE="${IMAGE_REGISTRY}/hybridbank-api-gateway:${IMAGE_TAG}"
export ACCOUNT_IMAGE="${IMAGE_REGISTRY}/hybridbank-account-service:${IMAGE_TAG}"
export TRANSACTION_IMAGE="${IMAGE_REGISTRY}/hybridbank-transaction-service:${IMAGE_TAG}"

# Paths
export HYBRIDBANK_DIR="${REPO_ROOT}/hybridbank"
