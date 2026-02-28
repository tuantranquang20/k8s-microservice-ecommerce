#!/usr/bin/env bash
# ============================================================
# scripts/vault-setup.sh — Seed Vault secrets for all services (dev mode)
# ============================================================
# Assumes Vault is running in dev mode (root token = "root").
# Run after: helm install vault hashicorp/vault -f platform/vault/vault-values.yaml

set -e

VAULT_PORT=8200
VAULT_ADDR="http://127.0.0.1:$VAULT_PORT"
VAULT_TOKEN="root"

echo "==> Port-forwarding Vault..."
kubectl port-forward svc/vault -n default $VAULT_PORT:8200 &
PF_PID=$!
sleep 3   # Wait for port-forward to establish

export VAULT_ADDR VAULT_TOKEN

echo ""
echo "==> Enabling KV secrets engine at 'secret/'..."
vault secrets enable -path=secret kv-v2 2>/dev/null || echo "    Already enabled"

echo ""
echo "==> Writing user-service secrets..."
vault kv put secret/user-service/db    password="changeme-prod"
vault kv put secret/user-service/jwt   secret="super-secret-jwt-change-in-prod"

echo ""
echo "==> Writing payment-service secrets..."
vault kv put secret/payment-service/jwt secret="super-secret-jwt-change-in-prod"

echo ""
echo "==> Enabling Kubernetes auth method..."
vault auth enable kubernetes 2>/dev/null || echo "    Already enabled"

vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local"

echo ""
echo "==> Creating Vault roles for services..."
# user-service role — binds the user-service k8s ServiceAccount to the policy
vault write auth/kubernetes/role/user-service \
  bound_service_account_names=user-service \
  bound_service_account_namespaces=ecommerce-dev,ecommerce-staging \
  policies=user-service \
  ttl=1h

vault write auth/kubernetes/role/payment-service \
  bound_service_account_names=payment-service \
  bound_service_account_namespaces=ecommerce-dev,ecommerce-staging \
  policies=payment-service \
  ttl=1h

echo ""
echo "==> Writing Vault HCL policies..."
vault policy write user-service platform/vault/vault-policies.hcl
vault policy write payment-service platform/vault/vault-policies.hcl

kill $PF_PID 2>/dev/null

echo ""
echo "============================================================"
echo "  Vault setup complete!"
echo "  Services with Vault enabled can now retrieve secrets via"
echo "  the Vault Agent Injector sidecar."
echo "============================================================"
