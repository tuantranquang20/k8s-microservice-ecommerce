#!/usr/bin/env bash
# ============================================================
# scripts/destroy.sh — Tear down Terraform infrastructure
# ============================================================
# WARNING: This DESTROYS the EKS cluster, VPC, and all AWS resources!
# Data in RDS/ElastiCache will be PERMANENTLY DELETED.

set -e

echo "============================================================"
echo "  WARNING: This will DESTROY all AWS infrastructure!"
echo "  VPC, EKS cluster, ECR repos, WAF, and NAT Gateways."
echo "  This action is IRREVERSIBLE."
echo "============================================================"
echo ""
read -rp "Type 'DESTROY' to confirm: " confirm

if [ "$confirm" != "DESTROY" ]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "==> Running terraform destroy..."
cd infrastructure/terraform
terraform destroy -auto-approve

echo ""
echo "  Infrastructure destroyed."
echo "  ⚠️  ECR images are NOT deleted by terraform destroy."
echo "     To delete ECR repos: aws ecr delete-repository --force --repository-name <name>"
