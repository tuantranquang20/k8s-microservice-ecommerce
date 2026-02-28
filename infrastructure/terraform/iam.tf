# ============================================================
# iam.tf — IAM Roles for EKS Cluster, Nodes, and IRSA
# ============================================================
# LEARNING NOTE — How EKS IAM works:
#
#   1. Cluster role   → the EKS control plane assumes this to manage AWS resources
#   2. Node role      → EC2 worker nodes assume this to pull images, write logs
#   3. IRSA (IAM Roles for Service Accounts) → pods assume roles via OIDC;
#      this is the modern way to give pods AWS permissions without storing
#      credentials anywhere. No more access keys in pod specs!

# ── EKS Cluster Role ──────────────────────────────────────────
# The EKS service needs permission to create/manage ENIs, security group
# rules, and other resources on our behalf.
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"

  # Trust policy: only the EKS service can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.cluster_name}-cluster-role" }
}

# AWS provides a managed policy with exactly the permissions EKS needs
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── EKS Node Group Role ───────────────────────────────────────
# Worker nodes (EC2 instances) need these managed policies:
#   - EKSWorkerNodePolicy      → join cluster, describe cluster
#   - EKS_CNI_Policy           → configure pod networking (VPC CNI)
#   - AmazonEC2ContainerRegistryReadOnly → pull images from ECR
resource "aws_iam_role" "eks_nodes" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.cluster_name}-node-role" }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_read_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── OIDC Provider (enables IRSA) ──────────────────────────────
# IRSA works by:
#   1. EKS publishes an OIDC endpoint
#   2. We register it as an Identity Provider in IAM
#   3. IAM roles can then trust JWTs from Kubernetes service accounts
#   4. The VPC CNI/AWS SDK automatically exchanges the SA token for AWS creds
#
# This replaces "kiam", "kube2iam", or embedding access keys in secrets.

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = { Name = "${var.cluster_name}-oidc" }
}

# ── IRSA: ALB Ingress Controller ─────────────────────────────
# The AWS Load Balancer Controller runs inside the cluster and creates
# ALBs when you define Kubernetes Ingress resources. It needs IAM perms
# to call ELB APIs. We use IRSA so only that specific service account can assume it.

# Policy document (inline; in prod you might store this as a JSON file)
resource "aws_iam_policy" "alb_controller" {
  name        = "${var.cluster_name}-alb-controller-policy"
  description = "IAM policy for AWS Load Balancer Controller"

  # AWS publishes this exact policy — we inline a minimal version here
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:*",
          "ec2:Describe*",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "iam:CreateServiceLinkedRole",
          "iam:GetServerCertificate",
          "iam:ListServerCertificates",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "alb_controller" {
  name = "${var.cluster_name}-alb-controller"

  # Trust policy: only the aws-load-balancer-controller service account
  # in the kube-system namespace can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.cluster_name}-alb-controller" }
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}
