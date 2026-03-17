# HybridBank Demo Story — Runbook

## Context
HybridBank is fully deployed across 3 clusters via ACM. This document is the demo narrative — the story to tell an audience, what to show, what to click, and what scripts to run.

## Current Deployed State

| Cluster | ACM Name | What's Running | Status |
|---------|----------|---------------|--------|
| OCP on-prem | `hybrid` | postgres-core, postgres-archive, account-service, transaction-service | Normal |
| ARO Azure | `aro` | api-gateway, frontend, standby postgres-core (replicas=0) | Normal |
| OSD GCP | `osd` | base resources only (failover target) | Standby |

- **Route**: `https://hybridbank-hybridbank.apps.iyymkyqq.eastus.aroapp.io`
- **ACM**: 3 subscriptions propagated (base, onprem, cloud)
- **Portworx**: pgdata-core replicating hybrid→ARO every 1min
- **Submariner**: account-service + transaction-service exported from hybrid

---

## Demo Flow (4 Acts)

### Act 1: "Everything is Fine" — Normal Mode (~3 min)

**What to show:**
1. Open the frontend route in browser
2. Point out the **green "All Systems Operational"** badge (top-right)
3. Dashboard shows:
   - Checking Account: $12,458.32 — "Data from primary database (On-Prem OCP)"
   - Savings Account: $45,200.00
   - PII visible: SSN last 4, KYC status (verified), email, phone — **green shield icon**
4. Click **Transactions** — full history available, all date ranges
5. Click **Transfer** button — modal opens, works normally
6. Open **Demo Controls** panel (bottom-right) — all green checkmarks

**What to say:**
> "This is HybridBank running in normal mode. The frontend and API gateway are on ARO in Azure. They connect to backend services on our on-prem OpenShift cluster via Submariner. All data — including PII like SSN and KYC status — is available because the on-prem archive database is reachable."

**Behind the scenes to show (optional):**
- ACM console: show 3 subscriptions, placement decisions
- `curl /api/health` → `{"mode":"normal","services":{"account":"up","transaction":"up"}}`

---

### Act 2: "Datacenter Goes Dark" — On-Prem Outage (~5 min)

**Run the script:**
```bash
./hybridbank/scripts/02-failover-onprem.sh
```

This scales up standby postgres on ARO, then scales down all on-prem services.

**What to watch in the browser (auto-updates every 5s):**
1. **Status badge** changes from green → **orange pulsing "Limited Mode"**
2. **Amber banner** appears: "Limited Banking Mode — Primary systems are recovering..."
3. Account cards change:
   - Data source label → "Data from Portworx replica (OSD) — read-only" with **amber icon**
   - Balances still visible ($12,458.32 / $45,200.00)
4. **PII disappears** — red shield: "PII Unavailable — Sensitive data stored on-prem only"
5. **Transfer button** grays out — hover tooltip: "Unavailable in limited mode"
6. **Transaction History** — date range locked to "Last 90 Days"
7. **Demo Controls** panel shows:
   - Account Service: **down** (red)
   - Transaction Service: **down** (red)
   - hybridbank_archive: **offline** (red)
   - Transfers: **disabled** (red)
   - PII/KYC: **unavailable** (red)
   - Balances: **available** (green) ← key point
   - Transactions (90d): **available** (green) ← key point

**What to say:**
> "The on-prem datacenter just went down. Watch the UI — within 5 seconds the gateway detects the backend services are unreachable and switches to limited mode. Notice what happened:
> - **Balances and recent transactions are still visible** — Portworx replicated the core database to ARO every minute
> - **PII data disappeared** — SSN, KYC, addresses are in the archive database which intentionally stays on-prem. It's never replicated to the cloud. This is a compliance decision.
> - **Transfers are disabled** — we can't write to a read-only replica
> - The customer can still check their balance and recent activity. The bank is degraded, not dead."

---

### Act 3: "Cloud Goes Down Too" — ARO → OSD Lifeboat (~3 min)

**Run the script:**
```bash
./hybridbank/scripts/04-failover-cloud.sh
```

This patches the ACM subscription to move gateway+frontend from ARO to OSD.

**What to show:**
1. The ARO route will stop responding (ACM is moving workloads)
2. After ~30s, access the **OSD route**: `https://hybridbank-hybridbank.apps.osd-demo.gixy.p2.openshiftapps.com`
3. Same limited mode UI — app survived a second failure
4. Show ACM console — subscription now points to lifeboat-placement → OSD

**What to say:**
> "Now Azure goes down too. ACM's lifeboat placement automatically moves the frontend and gateway to our GCP cluster. OSD has its own Portworx replica of the core database. The app is still running — same limited mode, same data available. We survived losing two of three clusters."

---

### Act 4: "All Clear" — Full Recovery (~3 min)

**Run the scripts in order:**
```bash
./hybridbank/scripts/05-failback-cloud.sh   # Restore ARO
./hybridbank/scripts/03-failback-onprem.sh   # Restore on-prem
```

**What to watch:**
1. Frontend moves back to ARO route
2. Within 5 seconds: **green badge returns**, banner disappears
3. **PII reappears** — green shield, SSN/KYC/email visible again
4. **Transfer button** re-enables
5. **Full transaction history** available again
6. Demo Controls: all green

**What to say:**
> "On-prem is back. The gateway detects the backend services are reachable again and switches back to normal mode. PII data reappears because the archive database is accessible. Transfers are re-enabled. Full recovery, no manual intervention."

---

## Key Talking Points

### 1. Data Sovereignty & Compliance
> "PII never leaves the datacenter. The archive database uses a Portworx storage class with local-only replication. During an outage, the UI clearly tells the customer their sensitive data is safe — it's not that we lost it, it's that we deliberately don't replicate it."

### 2. Graceful Degradation vs. Hard Failure
> "The bank doesn't go offline. It degrades gracefully. Customers can still check balances and recent transactions from the Portworx replica. The UI communicates exactly what's available and what isn't."

### 3. ACM Policy-Driven Placement
> "We didn't manually deploy to each cluster. ACM subscriptions + placements decide what runs where based on cluster labels. The lifeboat placement tolerates unreachable clusters and has a 30-second failover window."

### 4. Portworx Cross-Cloud Replication
> "The core database volume is replicated every minute from on-prem to both ARO and OSD via Stork MigrationSchedules. When we scale up the standby postgres, it mounts the replicated volume — same data, different cloud."

### 5. Submariner Service Mesh
> "The API gateway on ARO reaches on-prem services via Submariner's clusterset DNS: `account-service.hybridbank.svc.clusterset.local`. No VPN tunnels to manage, no custom networking — it's just a Kubernetes service name."

---

## Pre-Demo Checklist

- [ ] Verify `curl https://hybridbank-hybridbank.apps.iyymkyqq.eastus.aroapp.io/api/health` returns `{"mode":"normal"}`
- [ ] Open frontend in browser, confirm green badge + PII visible
- [ ] Confirm Demo Controls panel shows all green
- [ ] Have terminal ready with scripts directory: `cd hybridbank/scripts`
- [ ] Have ACM console open in separate tab
- [ ] Optionally: have `watch -n2 'curl -sk .../api/health'` running in a terminal

---

## Verification Commands

```bash
# Health check
curl -sk https://hybridbank-hybridbank.apps.iyymkyqq.eastus.aroapp.io/api/health

# Pods on each cluster
oc --context=hybrid get pods -n hybridbank    # On-prem
oc --context=aro get pods -n hybridbank       # ARO Azure
oc --context=osd get pods -n hybridbank       # OSD GCP

# ACM status (run from hub context)
oc --context=hub get subscriptions.apps -n hybridbank
oc --context=hub get placementdecisions -n hybridbank -o wide
oc --context=hub get managedclusters

# Portworx migration status
oc --context=hybrid get migrationschedules -n hybridbank
```
