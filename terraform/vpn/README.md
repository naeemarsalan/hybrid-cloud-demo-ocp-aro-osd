# Hybrid Cloud VPN — Azure <-> GCP <-> On-Prem (IPSec)

Three-site IPSec mesh VPN connecting the hybrid cloud demo clusters:

```
On-Prem OCP  <---IPSec--->  Azure ARO  <---IPSec--->  GCP OSD
     \                                                  /
      \__________________IPSec_________________________/
```

## Architecture

| Component | Details |
|-----------|---------|
| **Azure VPN Gateway** | VpnGw1 in a separate VPN VNet (10.4.0.0/24), peered to ARO VNet (10.0.0.0/22) |
| **GCP HA VPN** | HA VPN Gateway + Cloud Router with BGP in us-east1 |
| **Azure <-> GCP** | IPSec with BGP dynamic routing (ASN 65515 / 65534) |
| **On-Prem** | Static-route IPSec tunnels to both cloud gateways (Libreswan/strongSwan) |

### Why a Separate VPN VNet?

The existing ARO VNet (10.0.0.0/22) is fully consumed by two /23 subnets. Azure VPN Gateway requires a `GatewaySubnet`. Rather than modifying the ARO VNet (risky for a running cluster), we create a small VPN VNet and peer it.

## Prerequisites

- **Terraform** >= 1.5
- **Azure CLI** (`az`) — authenticated or service principal credentials
- **gcloud CLI** — authenticated or service account key
- Azure service principal with Contributor access to the resource group
- GCP service account with Compute Network Admin role

## Quick Start

```bash
# 1. Copy and edit the tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your credentials

# 2. Initialize and apply
terraform init
terraform plan
terraform apply
```

## Populating Credentials

**Azure** — Extract from your `az_creds` directory or create a service principal:
```bash
az ad sp create-for-rbac --name "vpn-terraform" --role Contributor \
  --scopes /subscriptions/<SUB_ID>/resourceGroups/openenv-fzm26
```

**GCP** — Use the existing service account key:
```bash
# The default gcp_credentials_file points to ../../osd/sa.json
# Verify it exists and has Compute Network Admin permissions
```

## Enabling On-Prem VPN

On-prem connections are disabled by default. When your on-prem VPN endpoint is ready:

1. Set `enable_onprem_vpn = true` in `terraform.tfvars`
2. Set `onprem_public_ip` to your endpoint's public IP
3. Set `onprem_cidr_ranges` to your on-prem subnets
4. Run `terraform apply`

### On-Prem Endpoint Setup (Libreswan)

After `terraform apply`, the `onprem_ipsec_config` output contains ready-to-use Libreswan configuration. Copy it to your on-prem host:

```bash
# Get the config snippet
terraform output -raw onprem_ipsec_config

# On the on-prem host:
# 1. Install Libreswan
sudo dnf install -y libreswan

# 2. Copy the config from terraform output to:
#    /etc/ipsec.d/hybrid-cloud.conf
#    /etc/ipsec.d/hybrid-cloud.secrets

# 3. Start IPSec
sudo systemctl enable --now ipsec
sudo ipsec auto --add onprem-to-azure
sudo ipsec auto --add onprem-to-gcp
sudo ipsec auto --up onprem-to-azure
sudo ipsec auto --up onprem-to-gcp
```

## Verification

```bash
# Terraform outputs
terraform output azure_vpn_gateway_public_ip
terraform output gcp_ha_vpn_gateway_ips

# Azure tunnel status
az network vpn-connection show \
  --name azure-to-gcp \
  --resource-group openenv-fzm26 \
  --query connectionStatus

# GCP tunnel status
gcloud compute vpn-tunnels describe tunnel-to-azure \
  --region=us-east1 --format="value(status)"

# BGP routes
gcloud compute routers get-status vpn-router --region=us-east1

# Connectivity test (from a pod in one cluster)
oc exec -it <pod> -- ping <remote-pod-ip>
```

## Resource Summary

| Resource | Count | Notes |
|----------|-------|-------|
| Azure VPN VNet + GatewaySubnet | 2 | Separate from ARO VNet |
| Azure VNet Peerings | 2 | Bidirectional with gateway transit |
| Azure VPN Gateway + Public IP | 2 | VpnGw1, ~30 min to provision |
| Azure Local Network Gateway | 1-2 | GCP + on-prem (if enabled) |
| Azure VPN Connections | 1-2 | IPSec to GCP + on-prem |
| GCP HA VPN Gateway | 1 | 2 public IPs |
| GCP Cloud Router | 1 | BGP ASN 65534 |
| GCP External VPN Gateway | 1-2 | Azure + on-prem (if enabled) |
| GCP VPN Tunnels | 1-2 | To Azure + on-prem |
| GCP Firewall Rules | 1-2 | Allow VPN traffic |

**Note:** Azure VPN Gateway takes approximately 25-40 minutes to provision.

## Cleanup

```bash
terraform destroy
```
