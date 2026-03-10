Once you request the Red Hat OpenShift Dedicated (OSD) on GCP catalog item through RHDP, the system will take a few minutes to process and assign a GCP project. Once it is ready, you will get a confirmation email that the blank environment is ready with other details. Please make note of PROJECT_ID (e.g. “openenv-x6jql”) and SERVICE_ACCOUNT that you are assigned. You can find these details under “Your GCP OPEN Environment details:” Here’s an example with the email confirmation: 



Step 1: Install the gcloud CLI.


Step 2: Authenticate the gcloud CLI with the Application Default Credentials (ADC)

NOTE: Use the PROJECT_ID (e.g. “openenv-x6jql”) that you are assigned while provisioning the “Red Hat OpenShift Dedicated (OSD) on GCP” catalog item, if prompted during authentication. You can find it in the email confirmation. The PROJECT_ID has the following format “openenv-xxxxx”.


# required only one time, at an account level. 
gcloud init
gcloud auth application-default login

You maybe prompted to carry out the following steps after you run the above command. 

Select [1] when prompted to pick configuration.




Select [1] to login to GCloud CLI using your Red Hat email.



Select [1] and enter the PROJECT_ID (e.g. “openenv-x6jql”) that you are assigned while provisioning the “Red Hat OpenShift Dedicated (OSD) on GCP” catalog item. 


Note: You can also set the project by using the following command: 


gcloud config set project PROJECT_ID



Step 3: Enable the following required APIs in the project that hosts your OpenShift Dedicated cluster


gcloud services enable deploymentmanager.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable cloudapis.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable dns.googleapis.com
gcloud services enable networksecurity.googleapis.com
gcloud services enable iamcredentials.googleapis.com
gcloud services enable iam.googleapis.com
gcloud services enable servicemanagement.googleapis.com
gcloud services enable serviceusage.googleapis.com
gcloud services enable storage-api.googleapis.com
gcloud services enable storage-component.googleapis.com
gcloud services enable orgpolicy.googleapis.com
gcloud services enable iap.googleapis.com


Cluster creation using the OCM CLI
Step 1: Log in to the Red Hat Hybrid Cloud Console https://console.redhat.com/


Step 2: Download and install the latest version of the OpenShift Cluster Manager (OCM) CLI from https://console.redhat.com/openshift/downloads
	

Step 3: Log in to the OCM CLI:


ocm login --use-auth-code


Step 4: Registering a Workload Identity Federation (wif) configuration: 

Background: Workload Identity Federation provides a keyless authentication mechanism for calling Google Cloud APIs. WIF is AWS STS equivalent on Google Cloud. In the context of Red Hat OpenShift Dedicated (OSD) on Google Cloud, the clusters can be deployed with short-lived, least privilege access credentials, eliminating the need for maintenance and security burden associated with the IAM service account keys

Use the PROJECT_ID (e.g. “openenv-x6jql”) that you are assigned while provisioning the “Red Hat OpenShift Dedicated (OSD) on GCP” catalog item through RHDP. You can find it in the email confirmation. Pick a WIF_NAME for your configuration and make a note of this. This WIF_NAME will be used during cluster creation.

# Register a WIF config 
ocm gcp create wif-config --name WIF_NAME --project PROJECT_ID

# Example:
ocm gcp create wif-config --name osdgcp-wif-test --project openenv-x6jql


Step 5: Create an OSD cluster referencing the wif-config (--wif-config WIF_NAME) created in the previous step. You can do this in the following ways: 

Users must use "On-Demand: Flexible usage billed through the Google Cloud Marketplace" subscription-type when creating OSD clusters. This is achieved by passing “--subscription-type=marketplace-gcp” and “--marketplace-gcp-terms=true” flags in the OCM CLI cluster creation call. 

# Example:
ocm create cluster osdgcp-gcpmark-417-demo --subscription-type=marketplace-gcp --marketplace-gcp-terms=true --provider=gcp --ccs=true --wif-config WIF_NAME --version=4.17.0 --region=us-east1 --secure-boot-for-shielded-vms=true --compute-machine-type=n2-standard-4 --multi-az=true --enable-autoscaling=true --min-replicas=3 --max-replicas=6

Users can also use interactive mode to create the cluster. Select --subscription-type=marketplace-gcp when prompted. 

## OCM CLI interactive mode
ocm create cluster -i


Alternatively, the OSD wizard in the OpenShift Cluster Manager Hybrid Cloud Console is also available for cluster creation. Users must use "On-Demand: Flexible usage billed through the Google Cloud Marketplace" subscription-type when creating OSD clusters.


Step 6: You can describe the cluster using the following command. Make note of your cluster ID, API URL and Console URL. 

ocm describe cluster CLUSTER_NAME

Step 7: Check the status of your cluster installation. The installation usually takes about 45-60min.



ocm cluster status CLUSTER_ID

# example:
-> ocm cluster status 2hjpq5ot6stp0qkg3e25n1s9omoghfuv
State:   ready
Memory:  58.37/1063.05 used
CPU:     4.23/240.00 used
->

Step 8: Create IDP

ocm create idp --cluster CLUSTER_ID --type htpasswd --name NAME --username USER --password **********

Step 9: Assign cluster-admin or dedicated-admin role to the user created

ocm create user <USER> -c <CLUSTER-NAME> --group=cluster-admins

Step 10: The user should delete the cluster after the expiration time of the demo

ocm delete cluster CLUSTER_ID

# Example:
ocm delete cluster 2a15c026iqdb4stg23cl192s5g1nkd3f

Share feedback
For any questions or feedback on this step-by-step guide, reach out to the OSD team at osd-rhdp-support@redhat.com 
