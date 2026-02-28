# ============================================================
# eks.tf — EKS Cluster and Managed Node Group
# ============================================================
# LEARNING NOTE — EKS Architecture:
#
#   Control Plane (AWS managed):
#     - API server, etcd, controller manager, scheduler
#     - Runs in AWS's VPC — you never SSH into it
#     - Communicates with nodes over private endpoint + security groups
#
#   Data Plane (our EC2 nodes):
#     - Managed Node Group = EC2 Auto Scaling Group managed by EKS
#     - "Managed" means AWS handles AMI updates, draining, rolling upgrades
#     - Nodes run in our private subnets

# ── EKS Cluster ───────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    # Nodes and pods live in private subnets
    subnet_ids = aws_subnet.private[*].id

    # Security group for the API server (control plane)
    security_group_ids = [aws_security_group.cluster.id]

    # endpoint_private_access: kubectl from within VPC works without internet
    # endpoint_public_access:  kubectl from laptop still works (convenient for learning;
    #                          in prod you'd set this to false and use a VPN/bastion)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Enable control plane logging to CloudWatch.
  # "api" and "audit" logs are most useful for debugging auth/authz issues.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # Encryption config for secrets at rest in etcd.
  # WHY: Without this, Kubernetes Secrets in etcd are base64-encoded (not encrypted).
  # The KMS key is auto-created by EKS — in prod, bring your own CMK.
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = { Name = var.cluster_name }
}

# KMS key for EKS secrets encryption
resource "aws_kms_key" "eks" {
  description             = "EKS secrets encryption key for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = { Name = "${var.cluster_name}-eks-kms" }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ── Managed Node Group ────────────────────────────────────────
# EKS manages the lifecycle of these EC2 instances:
#   - Creates an Auto Scaling Group
#   - Uses EKS-optimized Amazon Linux 2 AMI
#   - Drains nodes gracefully before termination
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  # Spread nodes across both private subnets (and thus both AZs)
  subnet_ids = aws_subnet.private[*].id

  # Instance spec
  instance_types = [var.node_instance_type] # t3.medium: 2 vCPU, 4 GB RAM

  # Scaling config
  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_min_count
    max_size     = var.node_max_count
  }

  # Rolling update strategy: replace nodes one at a time
  update_config {
    max_unavailable = 1
  }

  # Use AL2 for better compatibility with the VPC CNI and EBS CSI driver
  ami_type      = "AL2_x86_64"
  capacity_type = "ON_DEMAND" # Use SPOT for cost savings in dev (but pods can be evicted)
  disk_size     = 30          # GB per node — 30 is comfortable for container images

  # Node labels — useful for scheduling decisions
  labels = {
    role = "worker"
    env  = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_policy,
  ]

  tags = { Name = "${var.cluster_name}-nodes" }
}

# ── EKS Add-ons ───────────────────────────────────────────────
# Add-ons are AWS-managed components that run in the cluster.
# We pin versions to avoid surprise upgrades.

# VPC CNI: assigns VPC IPs to pods (required for EKS networking)
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.18.0-eksbuild.1"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

# CoreDNS: in-cluster DNS for service discovery (e.g., user-service.default.svc.cluster.local)
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = "v1.11.1-eksbuild.9"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

# kube-proxy: maintains network rules on each node (iptables/IPVS)
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.29.3-eksbuild.2"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

# NOTE: outputs.tf and providers reference aws_eks_cluster.main directly —
# no wrapper module needed. Direct resource references are clearer for learning.
