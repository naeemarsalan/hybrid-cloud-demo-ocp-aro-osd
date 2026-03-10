#!/usr/bin/env bash
# ============================================================
# Create the Git credentials Secret for ACM Channel access
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo "=== Setting up Git credentials Secret for ACM ==="
echo ""

# Ensure namespace exists
oc get namespace "${APP_NAMESPACE}" &>/dev/null || \
  oc create namespace "${APP_NAMESPACE}"

# Prompt for GitHub PAT if not set
if [[ -z "${GITHUB_PAT:-}" ]]; then
  read -rsp "Enter your GitHub Personal Access Token: " GITHUB_PAT
  echo ""
fi

# Create the secret
oc create secret generic git-credentials \
  --namespace="${APP_NAMESPACE}" \
  --from-literal=user=git \
  --from-literal=accessToken="${GITHUB_PAT}" \
  --dry-run=client -o yaml | oc apply -f -

echo ""
echo "✓ Secret 'git-credentials' created in namespace '${APP_NAMESPACE}'"
