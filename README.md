# Cloud Migration Infrastructure

This project provisions an AWS EKS (Elastic Kubernetes Service) cluster and deploys Prometheus monitoring using Terraform, GitHub Actions, and Helm.

## What Gets Created

- **VPC** — A custom VPC (`10.0.0.0/16`) with 2 public and 2 private subnets across multiple availability zones
- **EKS Cluster** — A Kubernetes 1.32 cluster (`migration-eks-cluster`) with managed node groups (1–3 `t3.medium` instances)
- **Cluster Addons** — CoreDNS, kube-proxy, and VPC-CNI
- **Prometheus Monitoring** — `kube-prometheus-stack` deployed via Helm into a `monitoring` namespace, exposed through a LoadBalancer

## Prerequisites

### 1. AWS Account and Credentials

You need an AWS account with an IAM user that has programmatic access.

**Create an IAM user with the required permissions:**

1. Sign in to the [AWS Management Console](https://console.aws.amazon.com/)
2. Navigate to **IAM** > **Users** > **Create user**
3. Enter a username (e.g., `terraform-user`)
4. Select **Attach policies directly** and add the following policies:
   - `AmazonEKSClusterPolicy`
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonVPCFullAccess`
   - `AmazonEC2FullAccess`
   - `AmazonS3FullAccess`
   - `IAMFullAccess`
   - `AmazonEKS_CNI_Policy`
5. Click **Create user**
6. Select the user, go to **Security credentials** > **Create access key**
7. Choose **Command Line Interface (CLI)** and create the key
8. Save the **Access Key ID** and **Secret Access Key** — you will need these later

### 2. AWS CLI

Skip this step if you already have the AWS CLI installed.

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

Verify the installation:

```bash
aws --version
```

Configure your credentials:

```bash
aws configure
```

Enter your Access Key ID, Secret Access Key, default region (`us-east-1`), and output format (`json`).

### 3. kubectl

Skip this step if you already have kubectl installed.

```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

Verify the installation:

```bash
kubectl version --client
```

### 4. Helm

Skip this step if you already have Helm installed.

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Verify the installation:

```bash
helm version
```

### 5. Create the S3 Bucket for Terraform State

Terraform uses an S3 bucket to store its state file remotely. Create this bucket before running the pipeline:

```bash
aws s3api create-bucket \
  --bucket terraform-eks-state-migproject \
  --region us-east-1
```

Verify the bucket was created:

```bash
aws s3 ls | grep terraform-eks-state-migproject
```

> **Note:** S3 bucket names are globally unique. If the name `terraform-eks-state-migproject` is already taken, choose a different name and update the `bucket` field in `terraform/main.tf` accordingly.

## Setup Guide

### Step 1 — Fork and Clone the Repository

1. Fork this repository to your own GitHub account
2. Clone your fork:

```bash
git clone https://github.com/<your-username>/cloud-migration-infra.git
cd cloud-migration-infra
```

### Step 2 — Configure GitHub Secrets

The GitHub Actions workflow needs your AWS credentials to provision infrastructure.

1. In your forked repository, go to **Settings** > **Secrets and variables** > **Actions**
2. Click **New repository secret** and add the following secrets:

| Secret Name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | Your IAM user access key ID |
| `AWS_SECRET_ACCESS_KEY` | Your IAM user secret access key |
| `AWS_REGION` | `us-east-1` |

### Step 3 — Review the Terraform Configuration

Before running the pipeline, review the configuration files in `terraform/`:

- **`variables.tf`** — Contains all configurable values with sensible defaults. Update any variables to match your environment (e.g., `aws_region`, `cluster_name`).
- **`main.tf`** — Defines the VPC and EKS cluster. The S3 backend block (lines 12–17) cannot use variables — update the bucket name and region directly if needed.
- **`outputs.tf`** — Exports cluster details after provisioning.

### Step 4 — Run the Terraform Pipeline

1. In your forked repository, go to **Actions** > **Terraform Pipeline**
2. Click **Run workflow**
3. Select `apply` from the dropdown and click **Run workflow**

The pipeline will execute the following steps:

1. Check out the repository
2. Initialize Terraform with the S3 backend
3. Validate the Terraform configuration
4. Plan and apply the infrastructure (VPC, EKS cluster, node groups)
5. Configure kubectl for the new cluster
6. Install Helm
7. Deploy the Prometheus monitoring stack

> **Note:** This process takes approximately 15–20 minutes. You can monitor progress in the **Actions** tab.

### Step 5 — Connect to Your EKS Cluster

Once the pipeline completes, configure your local `kubectl` to connect to the cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name migration-eks-cluster
```

Verify the connection:

```bash
kubectl get nodes
```

You should see 2 nodes in a `Ready` state.

### Step 6 — Verify the Prometheus Deployment

Check that the monitoring stack is running:

```bash
kubectl get pods -n monitoring
```

You should see pods for Prometheus, Grafana, and related components in a `Running` state.

Check the services:

```bash
kubectl get svc -n monitoring
```

### Step 7 — Access Prometheus

The Prometheus service is exposed via a LoadBalancer. Get the external URL:

```bash
kubectl get svc -n monitoring | grep LoadBalancer
```

Copy the `EXTERNAL-IP` value and open it in your browser. It may take a few minutes for the LoadBalancer DNS to become available.

## Cleanup

**Important:** Destroy all resources when you are finished to avoid ongoing AWS charges.

### Option 1 — Via GitHub Actions (Recommended)

1. Go to **Actions** > **Terraform Pipeline**
2. Click **Run workflow**
3. Select `destroy` from the dropdown and click **Run workflow**

### Option 2 — Manual Cleanup

If the pipeline is unavailable, clean up manually:

```bash
# Remove the Prometheus Helm release
helm uninstall monitoring -n monitoring

# Delete the monitoring namespace
kubectl delete namespace monitoring

# Destroy the Terraform infrastructure
cd terraform
terraform init
terraform destroy -auto-approve
```

After the infrastructure is destroyed, optionally delete the S3 state bucket:

```bash
# Empty the bucket first
aws s3 rm s3://terraform-eks-state-migproject --recursive

# Delete the bucket
aws s3api delete-bucket \
  --bucket terraform-eks-state-migproject \
  --region us-east-1
```

> **Important:** Verify in the AWS Console under **EKS**, **EC2**, and **VPC** that no resources remain.

## Troubleshooting

| Issue | Solution |
|---|---|
| Pipeline fails at `terraform init` | Verify the S3 bucket exists and your AWS credentials have S3 access |
| Pipeline fails at `terraform apply` | Check the Actions logs for specific errors. Common causes: insufficient IAM permissions or service quotas |
| `kubectl get nodes` returns no nodes | Wait a few minutes for nodes to register, then retry. Check the EKS console for node group status |
| LoadBalancer has no external IP | Wait 2–3 minutes for AWS to provision the load balancer. Run `kubectl get svc -n monitoring -w` to watch for updates |
| S3 bucket name already taken | Choose a unique bucket name and update the `bucket` field in `terraform/main.tf` |

## Project Structure

```
cloud-migration-infra/
├── .github/workflows/
│   └── terraform.yml            # GitHub Actions pipeline for Terraform + Helm
├── helm/
│   └── prometheus.sh            # Script to install kube-prometheus-stack via Helm
├── monitoring/
│   └── prometheus-values.yaml   # Custom Helm values for Prometheus configuration
└── terraform/
    ├── main.tf                  # VPC and EKS cluster definitions with S3 backend
    ├── outputs.tf               # Cluster endpoint, ARN, and security group outputs
    └── variables.tf             # Configurable variables with default values
```
