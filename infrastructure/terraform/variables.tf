# ============================================================
# variables.tf — All Input Variables
# ============================================================
# Centralising variables here means you can change a single value
# (e.g. region) and it propagates to every resource automatically.
# Override these via terraform.tfvars or CLI flags:
#   terraform apply -var="node_count=3"

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-1" # Singapore — change to your nearest
}

variable "environment" {
  description = "Deployment environment name (used in tags and naming)"
  type        = string
  default     = "production"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "ecommerce-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

# ── VPC / Networking ─────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to span subnets across (minimum 2 for EKS)"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — EKS nodes live here"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ── EKS Node Group ────────────────────────────────────────────
variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium" # 2 vCPU, 4GB RAM — enough for learning workloads
}

variable "node_count" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum number of nodes (for cluster autoscaler)"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum number of nodes (for cluster autoscaler)"
  type        = number
  default     = 4
}

# ── Services ──────────────────────────────────────────────────
variable "services" {
  description = "List of microservice names — ECR repos are created per entry"
  type        = list(string)
  default = [
    "user-service",
    "product-service",
    "order-service",
    "payment-service",
    "notification-service",
    "api-gateway-bff",
    "frontend",
  ]
}

# ── WAF ───────────────────────────────────────────────────────
variable "waf_rate_limit" {
  description = "Max requests per 5-minute window per IP before WAF blocks"
  type        = number
  default     = 1000
}
