# ============================================================
# main.tf — Root Terraform Configuration
# ============================================================
# LEARNING NOTE: The "terraform" block declares infrastructure
# requirements. We use a LOCAL backend (no S3) per AGENTS.md —
# this means terraform.tfstate lives in this directory. Fine for
# learning; in production you'd use S3 + DynamoDB locking.
#
# Three providers are needed:
#   aws        → create VPC, EKS, IAM, ECR, WAF resources
#   helm       → install ArgoCD into the EKS cluster
#   kubernetes → create K8s resources (namespaces, etc.) via Terraform

terraform {
  required_version = ">= 1.6.0"

  # LOCAL BACKEND — per AGENTS.md constraint (no S3, no DynamoDB)
  # State file will be: infrastructure/terraform/terraform.tfstate
  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.28"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# ── AWS Provider ──────────────────────────────────────────────
# Reads region from var.aws_region (default: ap-southeast-1)
# Credentials come from env vars AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# or from ~/.aws/credentials — never hardcoded here.
provider "aws" {
  region = var.aws_region

  # Default tags applied to EVERY resource created by this provider.
  # This makes cost allocation and resource tracking much easier.
  default_tags {
    tags = {
      Project     = "ecommerce-k8s"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ── Helm Provider ─────────────────────────────────────────────
# Points at the EKS cluster we create in eks.tf.
# Uses IRSA-capable kubeconfig built from EKS outputs.
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", aws_eks_cluster.main.name,
        "--region", var.aws_region,
      ]
    }
  }
}

# ── Kubernetes Provider ───────────────────────────────────────
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", aws_eks_cluster.main.name,
      "--region", var.aws_region,
    ]
  }
}

# ── Data Sources ──────────────────────────────────────────────
# Fetch current AWS account ID and partition for use in IAM ARNs.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
