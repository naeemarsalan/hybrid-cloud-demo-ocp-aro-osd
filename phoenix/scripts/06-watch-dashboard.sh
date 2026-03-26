#!/usr/bin/env bash
# ============================================================
# Phoenix Burst Demo — Live Dashboard (tmux)
# ============================================================
# Launches a 6-pane tmux session showing:
#   1. On-prem pods          2. OSD pods
#   3. On-prem HPA           4. KEDA ScaledObject + HPA
#   5. OSD nodes             6. Load generator logs
# ============================================================
set -euo pipefail

SESSION="phoenix-demo"
ONPREM_KC="/home/anaeem/onprem/perm/auth/kubeconfig"
OSD_CTX="osd"
NS="phoenix"

# Kill existing session if any
tmux kill-session -t "${SESSION}" 2>/dev/null || true

# Create session with first pane: on-prem pods
tmux new-session -d -s "${SESSION}" -n "burst-demo" \
  "watch -n3 'echo \"=== ON-PREM PODS ===\"; KUBECONFIG=${ONPREM_KC} oc -n ${NS} get pods -o wide 2>/dev/null; echo; echo \"=== RESOURCE USAGE ===\"; KUBECONFIG=${ONPREM_KC} oc -n ${NS} adm top pods 2>/dev/null'"

# Pane 2 (right): OSD pods
tmux split-window -h -t "${SESSION}" \
  "watch -n3 'echo \"=== OSD PODS ===\"; oc --context=${OSD_CTX} -n ${NS} get pods -o wide 2>/dev/null; echo; echo \"=== KEDA ScaledObject ===\"; oc --context=${OSD_CTX} -n ${NS} get scaledobject 2>/dev/null'"

# Pane 3 (bottom-left): on-prem HPA
tmux split-window -v -t "${SESSION}.0" \
  "watch -n5 'echo \"=== ON-PREM HPA ===\"; KUBECONFIG=${ONPREM_KC} oc -n ${NS} get hpa 2>/dev/null; echo; echo \"=== LOAD GENERATOR ===\"; KUBECONFIG=${ONPREM_KC} oc -n ${NS} logs deploy/phoenix-loadgenerator --tail=5 2>/dev/null'"

# Pane 4 (bottom-right): KEDA HPA + OSD nodes
tmux split-window -v -t "${SESSION}.1" \
  "watch -n5 'echo \"=== KEDA HPA ===\"; oc --context=${OSD_CTX} -n ${NS} get hpa 2>/dev/null; echo; echo \"=== OSD WORKER NODES ===\"; oc --context=${OSD_CTX} get nodes -l node-role.kubernetes.io/worker --no-headers 2>/dev/null; echo; echo \"=== OSD NODE USAGE ===\"; oc --context=${OSD_CTX} adm top nodes 2>/dev/null'"

# Pane 5 (bottom of bottom-left): Submariner status
tmux split-window -v -t "${SESSION}.2" \
  "watch -n10 'echo \"=== SUBMARINER ===\"; oc --context=${OSD_CTX} -n submariner-operator get gateway -o custom-columns=NODE:.status.localEndpoint.hostname,STATUS:.status.haStatus,CONNECTIONS:.status.connections[*].endpoint.cluster_id,CONN_STATUS:.status.connections[*].status,RTT:.status.connections[*].latencyRTT.average 2>/dev/null; echo; echo \"=== METRICS PROXY ===\"; oc --context=${OSD_CTX} -n ${NS} exec deploy/metrics-proxy -- python3 -c \"import urllib.request,json; r=urllib.request.urlopen(\\\"http://localhost:8080/\\\",timeout=5); print(json.dumps(json.loads(r.read()),indent=2))\" 2>/dev/null'"

# Pane 6 (bottom of bottom-right): Phoenix routes + quick status
tmux split-window -v -t "${SESSION}.3" \
  "watch -n10 'echo \"=== PHOENIX ROUTES ===\"; echo \"On-prem: https://\$(KUBECONFIG=${ONPREM_KC} oc -n ${NS} get route phoenix -o jsonpath={.spec.host} 2>/dev/null)\"; echo \"OSD:     https://\$(oc --context=${OSD_CTX} -n ${NS} get route phoenix -o jsonpath={.spec.host} 2>/dev/null)\"; echo; echo \"=== SUMMARY ===\"; ONPREM_PODS=\$(KUBECONFIG=${ONPREM_KC} oc -n ${NS} get pods -l app=phoenix --no-headers 2>/dev/null | grep Running | wc -l); OSD_PODS=\$(oc --context=${OSD_CTX} -n ${NS} get pods -l app=phoenix --no-headers 2>/dev/null | grep Running | wc -l); OSD_NODES=\$(oc --context=${OSD_CTX} get nodes -l node-role.kubernetes.io/worker --no-headers 2>/dev/null | wc -l); echo \"On-prem Phoenix: \${ONPREM_PODS} pods\"; echo \"OSD Phoenix:     \${OSD_PODS} pods (KEDA)\"; echo \"OSD Workers:     \${OSD_NODES} nodes\"; echo \"Total Phoenix:   \$((\${ONPREM_PODS} + \${OSD_PODS})) pods\"'"

# Set layout to tiled for even panes
tmux select-layout -t "${SESSION}" tiled

# Set pane borders to show titles
tmux set -t "${SESSION}" pane-border-status top
tmux select-pane -t "${SESSION}.0" -T "ON-PREM PODS"
tmux select-pane -t "${SESSION}.1" -T "OSD PODS + KEDA"
tmux select-pane -t "${SESSION}.2" -T "ON-PREM HPA + LOADGEN"
tmux select-pane -t "${SESSION}.3" -T "KEDA HPA + OSD NODES"
tmux select-pane -t "${SESSION}.4" -T "SUBMARINER + METRICS"
tmux select-pane -t "${SESSION}.5" -T "ROUTES + SUMMARY"

echo "============================================"
echo " Phoenix Burst Demo Dashboard"
echo "============================================"
echo ""
echo " Attaching to tmux session '${SESSION}'..."
echo " To detach: Ctrl+B, then D"
echo " To kill:   tmux kill-session -t ${SESSION}"
echo ""

# Attach
tmux attach -t "${SESSION}"
