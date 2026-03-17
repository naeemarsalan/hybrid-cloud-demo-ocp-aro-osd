# Portworx Cross-Cloud Connectivity: Problems & Solutions

## Overview

This document covers the challenges encountered setting up Portworx Enterprise 3.5.2 cross-cloud replication between **ARO (Azure Red Hat OpenShift)** and **OSD (OpenShift Dedicated on GCP)**, and how each was resolved.

## Environment

| Cluster | Platform | Network Plugin | PX Version | Nodes |
|---------|----------|---------------|------------|-------|
| ARO     | Azure    | OVNKubernetes | 3.5.2.1    | 3 workers |
| OSD     | GCP      | OVNKubernetes | 3.5.2.1    | 3 workers |

---

## Problem 1: PX 3.x SDK Port Serves HTTPS — ClusterPair Gets "Connection Reset by Peer"

### Symptom
```
pxctl cluster pair create --ip <remote-ip> --port 9001
Error: rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial tcp <ip>:9001: read: connection reset by peer"
```
Even local pairing (OSD to itself via LoadBalancer IP) failed with the same error.

### Root Cause
PX 3.x always serves **HTTPS/TLS** on the SDK port (9001). The `pxctl` daemon-to-daemon connection attempts **plain HTTP gRPC**, causing the TLS-speaking server to reset the connection.

The `--ssl` flag on `pxctl` only controls the pxctl-to-local-daemon connection, not daemon-to-remote-daemon pairing requests.

### Attempted Fix: Nginx TLS Proxy
Deployed an nginx stream proxy as a DaemonSet (`hostNetwork: true`) on each worker node:
- Listens on port 19001 (plain HTTP)
- Proxies to localhost:9001 with `proxy_ssl on` (terminates TLS)

This fixed the TLS mismatch but exposed **Problem 2**.

---

## Problem 2: PX 3.x SDK Authentication — "Unauthorized"

### Symptom
After fixing TLS via the nginx proxy:
```
pxctl cluster pair create --ip <ip> --port 19001
Error: Unauthorized
```

### Root Cause
PX 3.x wraps the SDK port (9001) with **kube-rbac-proxy**, which requires Kubernetes ServiceAccount token authentication on all incoming requests. The PX daemon does not send auth tokens for outbound ClusterPair requests.

### What Didn't Work
- `security.enabled: false` in StorageCluster spec — kube-rbac-proxy still enforces auth
- Granting `cluster-admin` to the `portworx` ServiceAccount — PX has its own internal authorization model separate from k8s RBAC
- Using the PX ServiceAccount token directly — got `Forbidden` (PX authorization, not k8s RBAC)
- kubeadmin token — bypassed "Unauthorized" but hit PX-internal `Forbidden`

### Resolution
Bypassed kube-rbac-proxy entirely — see **Solution** below.

---

## Problem 3: No Direct Network Path Between Azure and GCP

### Symptom
PX nodes on ARO (10.0.2.x) cannot reach PX nodes on OSD (10.0.128.x) — different clouds, overlapping RFC1918 subnets, no routable path.

### Options Considered

| Option | Issue |
|--------|-------|
| Site-to-site VPN (Azure VPN GW ↔ GCP Cloud VPN) | Existed but had overlapping subnet conflict (GCP 10.0.0.0/17 overlaps ARO 10.0.0.0/22) — GCP refuses static routes that overlap its own subnets |
| Direct public IP exposure | Security concern; PX ports exposed to internet |
| **Submariner** | ✅ Chosen — provides encrypted tunnel with Globalnet for overlapping CIDRs |

---

## Problem 4: Submariner Tunnel Establishment

### Sub-problems encountered getting the IPsec tunnel up:

#### 4a. NAT Discovery Packets Blocked
- **Symptom**: Gateway pods send UDP:4490 NAT discovery but get no response
- **Fix**: Opened UDP 4490/4500/500 on GCP firewall and Azure NSG

#### 4b. OSD Gateway Node Had No Public IP
- **Symptom**: GCP Cloud NAT handles outbound only; no inbound path for IPsec
- **Fix**: Reserved static IP (34.24.19.160) and assigned to the OSD gateway node NIC

#### 4c. ARO Gateway Node Couldn't Get Instance-Level Public IP
- **Symptom**: Azure LB outbound rules prevent instance-level public IPs
- **Fix**: Created Azure LB inbound NAT rules for UDP 4490/4500/500 forwarding to the gateway worker NIC

#### Result
Submariner tunnel established: ARO ↔ OSD with ~20ms RTT over IPsec (ESP in UDP:4500).

---

## Problem 5: Submariner Globalnet Can't Reach hostNetwork Services

### Symptom
Submariner cross-cluster connectivity works for regular pods (verified with nginx test), but the `portworx-api` service (GlobalIngressIP `242.1.255.253`) times out from ARO.

### Root Cause
The `portworx-api` DaemonSet runs with `hostNetwork: true`. Its endpoints are **node IPs** (10.0.128.x), not pod IPs. Submariner's Globalnet routing through OVN handles pod-network endpoints but cannot properly route to hostNetwork endpoints.

The packet path breaks because:
1. Traffic arrives at OSD gateway via IPsec tunnel
2. iptables DNAT rewrites dest to the Submariner service ClusterIP
3. OVN load balancer routes to the hostNetwork endpoint (node IP)
4. Return traffic from node IP doesn't traverse the Globalnet SNAT/xfrm path correctly

Additional issues found on the OSD gateway node:
- `ip_forward` was **disabled** (`net.ipv4.ip_forward = 0`)
- `rp_filter` was **strict** on br-ex, dropping packets with source IPs reachable via a different interface

### Fix Applied (partial)
```bash
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.br-ex.rp_filter=0
sysctl -w net.ipv4.conf.all.rp_filter=0
```
These alone did not resolve the hostNetwork endpoint routing issue.

---

## The Solution: Non-hostNetwork TCP Proxy

### Architecture
```
ARO Pod ──→ Submariner Tunnel ──→ OSD px-gw-proxy pod ──→ portworx-api svc ──→ PX (port 17001)
              (IPsec/Globalnet)     (regular pod, port 9001)  (ClusterIP)        (HTTP, no auth)
```

### Key Insight
The `portworx-api` service maps port **9001 → targetPort 17001**. Port 17001 is the **raw PX HTTP API**, bypassing kube-rbac-proxy entirely. This solves both the hostNetwork routing problem AND the authentication problem.

### Implementation

1. **Created `px-gw-proxy` on each cluster** — a regular (non-hostNetwork) Deployment running `nginxinc/nginx-unprivileged` with TCP stream proxy:

```yaml
# ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: px-gw-proxy-config
  namespace: portworx
data:
  nginx.conf: |
    worker_processes 1;
    pid /tmp/nginx.pid;
    events { worker_connections 128; }
    stream {
      upstream px_api {
        server portworx-api.portworx.svc.cluster.local:9001;
      }
      server {
        listen 9001;
        proxy_pass px_api;
      }
    }
---
# Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: px-gw-proxy
  namespace: portworx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: px-gw-proxy
  template:
    metadata:
      labels:
        app: px-gw-proxy
    spec:
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged:latest
        ports:
        - containerPort: 9001
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
      volumes:
      - name: nginx-config
        configMap:
          name: px-gw-proxy-config
---
# Service
apiVersion: v1
kind: Service
metadata:
  name: px-gw-proxy
  namespace: portworx
spec:
  selector:
    app: px-gw-proxy
  ports:
  - port: 9001
    targetPort: 9001
    protocol: TCP
```

2. **Exported via Submariner ServiceExport** on each cluster:
```yaml
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: px-gw-proxy
  namespace: portworx
```

3. **Resulting GlobalIngressIPs**:
   - ARO proxy: `242.0.255.253`
   - OSD proxy: `242.1.255.250`

### Verification
```
# From ARO pod → OSD PX API
curl http://242.1.255.250:9001/   →  "404 page not found" (PX HTTP API responding)

# From OSD pod → ARO PX API
curl http://242.0.255.253:9001/   →  "404 page not found" (PX HTTP API responding)
```

---

## PX ClusterPair Setup

With the proxy in place, `pxctl cluster pair create` worked:

```bash
# Generate token on destination cluster (OSD)
pxctl cluster token show
# Token: 08e197...

# Create objectstore credentials on BOTH clusters
# On each cluster, create credential named clusterPair_<REMOTE_CLUSTER_UUID>
# AND clusterPair_<OWN_CLUSTER_UUID> (PX requires both)
pxctl credentials create \
  --provider google \
  --google-project-id openenv-j4tbl \
  --google-json-key-file /path/to/gcloud.json \
  --bucket px-dr-openenv-j4tbl \
  clusterPair_<UUID>

# Create the pair from ARO → OSD via Submariner proxy IP
pxctl cluster pair create \
  --ip 242.1.255.250 \
  --remote-port 9001 \
  --token 08e197...

# Result: Successfully paired with remote cluster px-cluster-osd
```

Then create the Stork ClusterPair resource with the same endpoint:
```yaml
apiVersion: stork.libopenstorage.org/v1alpha1
kind: ClusterPair
metadata:
  name: osd-cluster
  namespace: online-boutique
spec:
  config:
    clusters:
      osd-cluster:
        server: "https://api.osd-demo.gixy.p2.openshiftapps.com:6443"
        insecure-skip-tls-verify: true
    contexts:
      osd-cluster:
        cluster: osd-cluster
        user: osd-cluster
    users:
      osd-cluster:
        token: "<osd-kubeconfig-token>"
    current-context: osd-cluster
  options:
    ip: "242.1.255.250"
    port: "9001"
    token: "<px-cluster-token>"
```

Status:
```
schedulerStatus: Ready
storageStatus: Ready
remoteStorageId: 498b4909-b9e9-4d66-957e-61d7eb67e5fb
```

---

## Volume-Only Migration (Data Sync)

Resources are managed by GitOps/ACM. Only volume data is migrated via PX:

```yaml
apiVersion: stork.libopenstorage.org/v1alpha1
kind: Migration
metadata:
  name: volume-sync
  namespace: online-boutique
spec:
  clusterPair: osd-cluster
  namespaces:
  - online-boutique
  includeResources: false    # GitOps handles resources
  includeVolumes: true       # Only sync PX volume data
  startApplications: false
```

Data flows: **PX cloudsnap (backup) → GCS bucket → PX cloudsnap (restore)** on the destination cluster.

---

## Summary of Problems and Solutions

| # | Problem | Root Cause | Solution |
|---|---------|-----------|----------|
| 1 | Connection reset on port 9001 | PX 3.x serves HTTPS, daemon connects HTTP | Proxy bypasses direct connection |
| 2 | Unauthorized on SDK port | kube-rbac-proxy enforces k8s SA auth | Proxy routes to port 17001 (raw HTTP API, no auth) |
| 3 | No network path between clouds | Different clouds, overlapping subnets | Submariner with Globalnet |
| 4 | IPsec tunnel won't establish | Firewall rules, missing public IPs | Opened UDP ports, assigned static IPs, Azure LB NAT rules |
| 5 | Globalnet can't reach hostNetwork pods | OVN routing doesn't handle hostNetwork endpoints | Non-hostNetwork proxy pod exported via Submariner |
