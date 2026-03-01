#!/usr/bin/env bash
# ============================================================
# scripts/vault-setup.sh — Seed Vault secrets + auth for all services
# ============================================================
# Assumes Vault is running in dev mode (root token = "root").
# Run after: helm install vault hashicorp/vault -f platform/vault/vault-values.yaml
#
# This script:
#   1. Enables the KV-v2 secrets engine at secret/
#   2. Writes secrets for every service that uses Vault
#   3. Enables Kubernetes auth method
#   4. Creates one Kubernetes auth role per service (binds SA → policy)
#   5. Writes HCL policies (read-only access to own secret paths)
#
# LEARNING NOTE — Why separate kv put / role / policy?
#   vault kv put   → stores the actual secret value
#   vault policy   → defines what paths a token can access
#   vault write role → binds k8s ServiceAccount to a policy

set -e

VAULT_PORT=8200
VAULT_ADDR="http://127.0.0.1:$VAULT_PORT"
VAULT_TOKEN="root"
NAMESPACES="ecommerce-dev,ecommerce-staging,ecommerce-prod"

echo "==> Port-forwarding Vault..."
kubectl port-forward svc/vault -n default $VAULT_PORT:8200 &
PF_PID=$!
sleep 3   # Wait for port-forward to establish

export VAULT_ADDR VAULT_TOKEN

echo ""
echo "==> Enabling KV-v2 secrets engine at 'secret/'..."
vault secrets enable -path=secret kv-v2 2>/dev/null || echo "    Already enabled"

# ── Write secrets for every service ──────────────────────────
echo ""
echo "==> Writing secrets..."

echo "    user-service..."
vault kv put secret/user-service/db \
  password="changeme-prod"     # PROD: generate a strong random password
vault kv put secret/user-service/jwt \
  secret="super-secret-jwt-change-in-prod"  # PROD: min 32 random bytes

echo "    payment-service..."
vault kv put secret/payment-service/jwt \
  secret="super-secret-jwt-change-in-prod"  # Must match user-service jwt.secret!

echo "    order-service..."
vault kv put secret/order-service/db \
  password="changeme-prod"
vault kv put secret/order-service/jwt \
  secret="super-secret-jwt-change-in-prod"  # Must match user-service jwt.secret!

echo "    product-service..."
vault kv put secret/product-service/mongo \
  uri="mongodb://databases-mongodb:27017/products"  \
  username=""   \   # empty = no auth in dev; set in prod
  password=""       # empty = no auth in dev; set in prod

echo "    notification-service..."
vault kv put secret/notification-service/redis \
  password=""       # empty in dev (Redis auth disabled); set in prod

# ── Enable Kubernetes auth ────────────────────────────────────
echo ""
echo "==> Enabling Kubernetes auth method..."
vault auth enable kubernetes 2>/dev/null || echo "    Already enabled"

vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local"

# ── Create one role per service ───────────────────────────────
echo ""
echo "==> Creating Kubernetes auth roles..."

vault write auth/kubernetes/role/user-service \
  bound_service_account_names=user-service \
  bound_service_account_namespaces="$NAMESPACES" \
  policies=user-service \
  ttl=1h

vault write auth/kubernetes/role/payment-service \
  bound_service_account_names=payment-service \
  bound_service_account_namespaces="$NAMESPACES" \
  policies=payment-service \
  ttl=1h

vault write auth/kubernetes/role/order-service \
  bound_service_account_names=order-service \
  bound_service_account_namespaces="$NAMESPACES" \
  policies=order-service \
  ttl=1h

vault write auth/kubernetes/role/product-service \
  bound_service_account_names=product-service \
  bound_service_account_namespaces="$NAMESPACES" \
  policies=product-service \
  ttl=1h

vault write auth/kubernetes/role/notification-service \
  bound_service_account_names=notification-service \
  bound_service_account_namespaces="$NAMESPACES" \
  policies=notification-service \
  ttl=1h

# ── Write HCL policies for all services ──────────────────────
echo ""
echo "==> Writing Vault HCL policies (platform/vault/vault-policies.hcl)..."
# NOTE: vault-policies.hcl contains ALL service policies in one file.
# vault policy write applies the entire file as ONE named policy.
# We apply it once per service name (each policy name controls which
# paths Vault allows — the content of the HCL file defines them all).
vault policy write user-service       platform/vault/vault-policies.hcl
vault policy write payment-service    platform/vault/vault-policies.hcl
vault policy write order-service      platform/vault/vault-policies.hcl
vault policy write product-service    platform/vault/vault-policies.hcl
vault policy write notification-service platform/vault/vault-policies.hcl

kill $PF_PID 2>/dev/null

echo ""
echo "============================================================"
echo "  Vault setup complete!"
echo ""
echo "  Services configured: user-service, payment-service,"
echo "  order-service, product-service, notification-service"
echo ""
echo "  Verify with:"
echo "    vault kv get secret/user-service/db"
echo "    vault read auth/kubernetes/role/user-service"
echo "    vault policy read user-service"
echo "============================================================"
