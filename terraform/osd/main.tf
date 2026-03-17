# =============================================================================
# OSD Cluster — OpenShift Dedicated on GCP via OCM CLI
# =============================================================================

# GCP Service Account (must be named osd-ccs-admin)
resource "google_service_account" "osd_ccs_admin" {
  account_id   = "osd-ccs-admin"
  display_name = "OSD CCS Admin"
  project      = var.gcp_project_id
}

# IAM roles required by OSD CCS
resource "google_project_iam_member" "osd_owner" {
  project = var.gcp_project_id
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.osd_ccs_admin.email}"
}

resource "google_project_iam_member" "osd_service_account_user" {
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.osd_ccs_admin.email}"
}

resource "google_project_iam_member" "osd_service_account_admin" {
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${google_service_account.osd_ccs_admin.email}"
}

resource "google_project_iam_member" "osd_service_account_key_admin" {
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountKeyAdmin"
  member  = "serviceAccount:${google_service_account.osd_ccs_admin.email}"
}

# SA key for OCM
resource "google_service_account_key" "osd_ccs_admin" {
  service_account_id = google_service_account.osd_ccs_admin.name
}

resource "local_file" "osd_sa_key" {
  content         = base64decode(google_service_account_key.osd_ccs_admin.private_key)
  filename        = "${path.module}/osd-ccs-admin-key.json"
  file_permission = "0600"
}

# Enable required GCP APIs
resource "google_project_service" "osd_apis" {
  for_each = toset(var.gcp_apis)

  project = var.gcp_project_id
  service = each.value

  disable_on_destroy = false
}

# Create OSD cluster via OCM CLI
resource "null_resource" "osd_cluster" {
  depends_on = [
    google_project_iam_member.osd_owner,
    google_project_iam_member.osd_service_account_user,
    google_project_iam_member.osd_service_account_admin,
    google_project_iam_member.osd_service_account_key_admin,
    google_project_service.osd_apis,
    local_file.osd_sa_key,
  ]

  triggers = {
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Login to OCM
      ocm login --token="${var.ocm_token}"

      # Check if cluster already exists
      EXISTING=$(ocm list clusters --parameter search="name='${var.cluster_name}'" --no-headers 2>/dev/null | wc -l)
      if [ "$EXISTING" -gt 0 ]; then
        echo "Cluster ${var.cluster_name} already exists, skipping creation"
        exit 0
      fi

      # Create OSD cluster (no secure boot — required for Portworx)
      VERSION_FLAG=""
      if [ -n "${var.osd_version}" ]; then
        VERSION_FLAG="--version ${var.osd_version}"
      fi

      ocm create cluster \
        --ccs=true \
        --provider=gcp \
        --service-account-file="${local_file.osd_sa_key.filename}" \
        --region="${var.gcp_region}" \
        --compute-machine-type="${var.machine_type}" \
        --compute-nodes=${var.compute_nodes} \
        $VERSION_FLAG \
        "${var.cluster_name}"

      echo "OSD cluster creation initiated. Waiting for ready state..."

      # Poll until ready (up to 60 minutes)
      for i in $(seq 1 120); do
        STATE=$(ocm describe cluster "${var.cluster_name}" --json | jq -r '.state // "unknown"')
        echo "  [$i/120] Cluster state: $STATE"
        if [ "$STATE" = "ready" ]; then
          echo "Cluster is ready!"
          exit 0
        fi
        if [ "$STATE" = "error" ]; then
          echo "Cluster entered error state!"
          exit 1
        fi
        sleep 30
      done

      echo "Timeout waiting for cluster to become ready"
      exit 1
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      ocm delete cluster "${self.triggers.cluster_name}" || true
    EOT
  }
}

# Extract credentials and write kubeconfig
resource "null_resource" "kubeconfig" {
  depends_on = [null_resource.osd_cluster]

  triggers = {
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Get cluster ID
      CLUSTER_ID=$(ocm describe cluster "${var.cluster_name}" --json | jq -r '.id')

      # Create admin user if not exists
      ocm create idp --type htpasswd --name htpasswd \
        --username cluster-admin --password "$(openssl rand -base64 16)" \
        --cluster "$CLUSTER_ID" 2>/dev/null || true

      # Get API URL
      API_URL=$(ocm describe cluster "${var.cluster_name}" --json | jq -r '.api.url')

      # Get credentials
      CREDS=$(ocm get "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/credentials" 2>/dev/null || true)
      KUBECONFIG_CONTENT=$(echo "$CREDS" | jq -r '.kubeconfig // empty')

      if [ -n "$KUBECONFIG_CONTENT" ]; then
        echo "$KUBECONFIG_CONTENT" > /tmp/kubeconfig-osd.yaml
      else
        # Fallback: use ocm token-based login
        oc login "$API_URL" --token="$(ocm token)" --insecure-skip-tls-verify=true
        oc config view --minify --flatten > /tmp/kubeconfig-osd.yaml
      fi

      chmod 600 /tmp/kubeconfig-osd.yaml
    EOT
  }
}

# Read kubeconfig content for output
data "local_file" "kubeconfig" {
  filename   = "/tmp/kubeconfig-osd.yaml"
  depends_on = [null_resource.kubeconfig]
}

# Get cluster info for outputs
data "external" "cluster_info" {
  depends_on = [null_resource.osd_cluster]

  program = ["bash", "-c", <<-EOT
    INFO=$(ocm describe cluster "${var.cluster_name}" --json 2>/dev/null || echo '{}')
    API_URL=$(echo "$INFO" | jq -r '.api.url // ""')
    CONSOLE_URL=$(echo "$INFO" | jq -r '.console.url // ""')
    VPC=$(echo "$INFO" | jq -r '.network.machine_cidr // ""')
    # Get VPC network name from GCP
    NETWORK_NAME=$(echo "$INFO" | jq -r '.infra_id // ""')
    if [ -n "$NETWORK_NAME" ]; then
      NETWORK_NAME="$NETWORK_NAME-network"
    fi
    jq -n --arg api "$API_URL" --arg console "$CONSOLE_URL" --arg network "$NETWORK_NAME" \
      '{"api_url": $api, "console_url": $console, "vpc_network_name": $network}'
  EOT
  ]
}
