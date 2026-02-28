#!/usr/bin/env bash
# ============================================================
# scripts/infra-apply.sh — Terraform plan + apply
# ============================================================
set -e

echo "==> [1/3] Validating Terraform config..."
cd infrastructure/terraform
terraform validate

echo ""
echo "==> [2/3] Running terraform plan..."
terraform plan -out=tfplan

echo ""
echo "==> [3/3] Applying infrastructure changes..."
echo "    This will create: VPC, EKS cluster, ECR repos, WAF, ArgoCD"
echo "    Estimated time: 15-20 minutes"
terraform apply tfplan

echo ""
echo "==> Fetching kubeconfig..."
CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw aws_region 2>/dev/null || echo "ap-southeast-1")
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

echo ""
echo "  Infrastructure applied. kubectl context updated."
echo "  Run: kubectl get nodes"
