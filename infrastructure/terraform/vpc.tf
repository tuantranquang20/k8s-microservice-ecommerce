# ============================================================
# vpc.tf — VPC, Subnets, Internet Gateway, NAT, Route Tables
# ============================================================
# Architecture:
#   - 1 VPC (10.0.0.0/16)
#   - 2 public subnets  (one per AZ) — ALB, NAT gateway reside here
#   - 2 private subnets (one per AZ) — EKS nodes run here (never directly exposed)
#   - 1 IGW → attached to public subnets
#   - 1 NAT Gateway (single, in AZ-a) → private subnets route out through it
#
# COST NOTE: A single NAT gateway is used to save money in dev/learning.
# In production use one NAT per AZ for availability. Estimated cost:
#   NAT Gateway: ~$32/month + data transfer fees.

# ── VPC ───────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # enable_dns_hostnames is REQUIRED for EKS nodes to register with the API server
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# ── Internet Gateway ──────────────────────────────────────────
# IGW allows resources in public subnets to reach the internet.
# EKS control plane communicates with nodes via private endpoint,
# but the ALB needs the IGW for inbound traffic.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# ── Public Subnets ────────────────────────────────────────────
# count = number of AZs in var.availability_zones
# The count trick lets us create N subnets with one resource block.
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true # instances get public IPs automatically

  tags = {
    Name = "${var.cluster_name}-public-${var.availability_zones[count.index]}"

    # REQUIRED tag for AWS Load Balancer Controller to discover public subnets
    "kubernetes.io/role/elb" = "1"

    # EKS ownership tag — lets EKS add/remove rules in these subnets
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ── Private Subnets ───────────────────────────────────────────
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.cluster_name}-private-${var.availability_zones[count.index]}"

    # REQUIRED tag for internal load balancers (internal ALB / NLB)
    "kubernetes.io/role/internal-elb" = "1"

    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ── Elastic IP for NAT Gateway ────────────────────────────────
# NAT Gateway needs a static public IP. aws_eip allocates one.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }

  # EIP must be created after the IGW is attached to the VPC
  depends_on = [aws_internet_gateway.main]
}

# ── NAT Gateway ───────────────────────────────────────────────
# Lives in the first public subnet (AZ-a).
# Private subnets use this to reach the internet (e.g., pull container images).
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # placed in first public subnet

  tags = {
    Name = "${var.cluster_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# ── Route Table: Public ───────────────────────────────────────
# All traffic (0.0.0.0/0) from public subnets goes out the IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

# Associate the public route table with each public subnet
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Route Table: Private ──────────────────────────────────────
# All traffic from private subnets goes out via NAT Gateway (not IGW).
# This means private nodes have outbound internet, but are NOT reachable
# from the internet — key security principle.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
