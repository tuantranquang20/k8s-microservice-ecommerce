# ============================================================
# security_groups.tf — Security Groups for EKS and ALB
# ============================================================
# WHY: Security groups are stateful firewalls at the resource level.
# We create explicit groups rather than relying on defaults so we
# can document and audit every allowed traffic path.

# ── ALB Security Group ────────────────────────────────────────
# The Application Load Balancer sits in public subnets and accepts
# HTTP/HTTPS from anywhere. It then forwards to Kong Gateway pods.
resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # Allow inbound HTTP from the internet
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTPS from the internet
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (to reach EKS nodes in private subnets)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-alb-sg"
  }
}

# ── EKS Node Security Group ───────────────────────────────────
# Worker nodes need to:
#   - Accept traffic from the ALB (NodePort range: 30000-32767)
#   - Communicate with each other (pod-to-pod, kubelet)
#   - Accept webhooks from the API server
resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  # Node-to-node communication (required for pod networking / CNI)
  ingress {
    description = "Node to node all traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true # "self" means: allow traffic from other resources with this same SG
  }

  # ALB → NodePort range
  ingress {
    description     = "ALB to NodePort services"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # EKS control plane → kubelet (required for kubectl exec, logs, metrics)
  ingress {
    description     = "EKS control plane to kubelet"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  # All outbound — nodes need to pull images, reach AWS APIs, etc.
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-nodes-sg"
    # EKS uses this tag to attach its own rules to the node SG
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# ── EKS Cluster (Control Plane) Security Group ───────────────
# The managed control plane API server uses this SG.
# We must allow our nodes to reach the API server on port 443.
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS control plane"
  vpc_id      = aws_vpc.main.id

  # Nodes → API server (this is the OIDC/token validation flow)
  ingress {
    description     = "Nodes to API server"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}
