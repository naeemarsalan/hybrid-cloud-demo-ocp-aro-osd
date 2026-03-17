#!/usr/bin/env bash
# ============================================================
# Watch pods across all 3 clusters side-by-side
# Uses tmux split panes with colored headers
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

if ! command -v tmux &>/dev/null; then
  echo "ERROR: tmux is required. Install with: sudo dnf install tmux"
  exit 1
fi

SESSION="hybridbank-watch"
tmux kill-session -t "$SESSION" 2>/dev/null

tmux new-session -d -s "$SESSION" -x "$(tput cols)" -y "$(tput lines)"

tmux send-keys -t "$SESSION" "printf '\\033[1;32m=== ON-PREM (hybrid) ===\\033[0m\\n'; watch -n2 'oc --context=${OCP_CLUSTER_NAME} get pods -n ${APP_NAMESPACE} -o wide 2>&1'" C-m
tmux split-window -h -t "$SESSION"
tmux send-keys -t "$SESSION" "printf '\\033[1;34m=== ARO (Azure) ===\\033[0m\\n'; watch -n2 'oc --context=${ARO_CLUSTER_NAME} get pods -n ${APP_NAMESPACE} -o wide 2>&1'" C-m
tmux split-window -v -t "$SESSION"
tmux send-keys -t "$SESSION" "printf '\\033[1;35m=== OSD (GCP) ===\\033[0m\\n'; watch -n2 'oc --context=${OSD_CLUSTER_NAME} get pods -n ${APP_NAMESPACE} -o wide 2>&1'" C-m

tmux select-layout -t "$SESSION" main-vertical
tmux attach -t "$SESSION"
