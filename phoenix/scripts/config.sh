#!/usr/bin/env bash
# ============================================================
# Phoenix Burst Demo — Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Cluster access
# On-prem uses KUBECONFIG file (system:admin cert auth)
export ONPREM_KUBECONFIG="${ONPREM_KUBECONFIG:-/home/anaeem/onprem/perm/auth/kubeconfig}"
# OSD uses named context in ~/.kube/config
export OSD_CONTEXT="${OSD_CONTEXT:-osd}"

# Helpers
oc_onprem() { KUBECONFIG="${ONPREM_KUBECONFIG}" oc "$@"; }
oc_osd() { oc --context="${OSD_CONTEXT}" "$@"; }

# Application
export PHOENIX_NAMESPACE="phoenix"

# Paths
export PHOENIX_DIR="${REPO_ROOT}/phoenix"
