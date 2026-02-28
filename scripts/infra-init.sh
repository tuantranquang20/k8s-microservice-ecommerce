#!/usr/bin/env bash
# ============================================================
# scripts/infra-init.sh — Terraform init + validate
# ============================================================
set -e

echo "==> [1/2] Running terraform init..."
cd infrastructure/terraform
terraform init

echo ""
echo "==> [2/2] Running terraform validate..."
terraform validate

echo ""
echo "  Terraform initialised and validated successfully."
echo "  Run ./scripts/infra-apply.sh to apply the infrastructure."
