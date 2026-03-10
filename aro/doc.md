# ARO (Azure Red Hat OpenShift) — Setup Notes

## Cluster Details
- **Name:** aro-east
- **Region:** East US
- **Console:** https://console-openshift-console.apps.q27xwipo.eastus.aroapp.io

## Importing into ACM

### Prerequisites
- ARO cluster is running and accessible
- `oc` CLI authenticated to the ACM hub cluster
- ARO API URL and admin token available

### Steps

1. **Get ARO API URL and token:**
   ```bash
   # Login to ARO
   oc login <ARO_API_URL> --username kubeadmin --password <PASSWORD>
   oc whoami --show-server   # API URL
   oc whoami -t              # Token
   ```

2. **Import via ACM Console (recommended):**
   - ACM Console → Infrastructure → Clusters → "Import cluster"
   - Name: `aro-east`
   - Import mode: "Enter your server URL and API token"
   - Fill in server URL and token from step 1
   - Wait for status: "Ready"

3. **Import via CLI (alternative):**
   ```bash
   # On the hub cluster, create the ManagedCluster
   cat <<EOF | oc apply -f -
   apiVersion: cluster.open-cluster-management.io/v1
   kind: ManagedCluster
   metadata:
     name: aro-east
     labels:
       cloud: azure
       vendor: OpenShift
   spec:
     hubAcceptsClient: true
   EOF

   # Wait for the import secret to be generated
   oc get secret aro-east-import -n aro-east -o jsonpath='{.data.import\.yaml}' | base64 -d > /tmp/aro-import.yaml

   # Apply on the ARO cluster
   oc login <ARO_API_URL> --token=<TOKEN>
   oc apply -f /tmp/aro-import.yaml
   ```

4. **Verify:**
   ```bash
   # Back on the hub
   oc get managedclusters
   # Should show aro-east with status True/True
   ```

## Notes
- ARO clusters have their own OAuth provider; use the kubeadmin credentials or a configured identity provider
- The ARO resource group in Azure contains the cluster infrastructure
- ARO provides integrated Azure AD support if needed for RBAC
