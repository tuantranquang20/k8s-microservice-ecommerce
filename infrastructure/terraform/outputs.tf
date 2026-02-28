# ============================================================
# outputs.tf — Terraform Outputs
# ============================================================
# Outputs are printed after `terraform apply` and can also be
# consumed by other Terraform workspaces via data sources.
# Use: terraform output -raw kubeconfig_command

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint (used by kubectl)"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA cert for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "kubeconfig_command" {
  description = "Run this command locally to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of private subnets where EKS nodes run"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of public subnets where the ALB will be placed"
  value       = aws_subnet.public[*].id
}

output "ecr_repository_urls" {
  description = "Map of service name → ECR repository URL for CI/CD pipelines"
  value = {
    for name, repo in aws_ecr_repository.services : name => repo.repository_url
  }
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF WebACL — attach to ALB in the AWS console or via aws_alb resource"
  value       = aws_wafv2_web_acl.main.arn
}

output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed"
  value       = "argocd"
}
