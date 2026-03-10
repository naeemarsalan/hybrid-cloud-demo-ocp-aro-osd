# OSD on GCP - Deployment Guide

## Overview

This document describes the steps taken to deploy a Red Hat OpenShift Dedicated (OSD) cluster on Google Cloud Platform (GCP) using Workload Identity Federation (WIF).

## Environment Details

| Parameter | Value |
|---|---|
| GCP Project ID | `openenv-qcrrv` |
| GCP Organization ID | `54643501348` |
| DNS Zone | `qcrrv.gcp.redhatworkshops.io` |
| Service Account | `sa-openenv-qcrrv@rhpds-345620.iam.gserviceaccount.com` |
| Cluster Name | `osd-demo` |
| Cluster ID | `2ov4utjqjvvbtb76koqavvscimmeoe9n` |
| Region | `us-east1` |
| DNS Base Domain | `aynb.p2.openshiftapps.com` |
| WIF Config Name | `osd-demo-wif` |
| Compute Type | `n2-standard-4` |
| Multi-AZ | `true` |
| Autoscaling | `3-6 replicas` |

## Prerequisites

- gcloud CLI installed
- ocm CLI installed (v1.0.12+)
- Red Hat SSO credentials
- Access to the RHDP-provisioned GCP project

## Step-by-Step Deployment

### Step 1: Authenticate gcloud CLI

```bash
gcloud init
# Selected project: openenv-qcrrv
# Authenticated with Red Hat SSO credentials

gcloud auth application-default login
```

### Step 2: Install and authenticate OCM CLI

Downloaded from https://console.redhat.com/openshift/downloads and logged in:

```bash
ocm login --use-auth-code
```

### Step 3: Enable required GCP APIs

```bash
gcloud services enable \
  deploymentmanager.googleapis.com \
  compute.googleapis.com \
  cloudapis.googleapis.com \
  cloudresourcemanager.googleapis.com \
  dns.googleapis.com \
  networksecurity.googleapis.com \
  iamcredentials.googleapis.com \
  iam.googleapis.com \
  servicemanagement.googleapis.com \
  serviceusage.googleapis.com \
  storage-api.googleapis.com \
  storage-component.googleapis.com \
  orgpolicy.googleapis.com \
  iap.googleapis.com
```

### Step 4: Create Workload Identity Federation (WIF) config

WIF provides keyless authentication for Google Cloud APIs, eliminating the need for long-lived service account keys.

```bash
ocm gcp create wif-config --name osd-demo-wif --project openenv-qcrrv
```

### Step 5: Create OSD cluster

```bash
ocm create cluster osd-demo \
  --subscription-type=marketplace-gcp \
  --marketplace-gcp-terms=true \
  --provider=gcp \
  --ccs=true \
  --wif-config osd-demo-wif \
  --region=us-east1 \
  --secure-boot-for-shielded-vms=true \
  --compute-machine-type=n2-standard-4 \
  --multi-az=true \
  --enable-autoscaling=true \
  --min-replicas=3 \
  --max-replicas=6
```

### Step 6: Create IDP and admin user

Once the cluster reaches `ready` state (~45-60 min):

```bash
# Create htpasswd identity provider
ocm create idp --cluster 2ov4utjqjvvbtb76koqavvscimmeoe9n \
  --type htpasswd --name htpasswd \
  --username kubeadmin --password 'Kubeadmin2024*'

# Assign cluster-admin role
ocm create user kubeadmin -c osd-demo --group=cluster-admins
```

## Monitoring

```bash
# Check cluster status
ocm cluster status 2ov4utjqjvvbtb76koqavvscimmeoe9n

# Describe cluster (get API URL, Console URL, etc.)
ocm describe cluster osd-demo
```

## Cleanup

```bash
# Delete the cluster
ocm delete cluster 2ov4utjqjvvbtb76koqavvscimmeoe9n
```
