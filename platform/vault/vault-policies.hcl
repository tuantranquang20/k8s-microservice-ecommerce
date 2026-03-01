# ============================================================
# vault-policies.hcl — HCL Policies for all services that use Vault
# ============================================================
# Vault uses HCL (HashiCorp Configuration Language) for policies.
# Policies define WHAT a token/role can do — this is the authz layer.
#
# Apply all policies at once via vault-setup.sh, or individually:
#   vault policy write <name> platform/vault/vault-policies.hcl
#
# PRINCIPLE OF LEAST PRIVILEGE: each service can only read its own
# secret paths — never another service's secrets, and never write/delete.
# ============================================================

# ── user-service ──────────────────────────────────────────────
# Reads: DB password + JWT signing secret
path "secret/data/user-service/*" {
  capabilities = ["read"]
}
path "secret/metadata/user-service/*" {
  capabilities = ["list"]
}

# ── payment-service ───────────────────────────────────────────
# Reads: JWT secret (+ future: Stripe/PayPal API keys)
path "secret/data/payment-service/*" {
  capabilities = ["read"]
}
path "secret/metadata/payment-service/*" {
  capabilities = ["list"]
}

# ── order-service ─────────────────────────────────────────────
# Reads: PostgreSQL password + JWT secret
path "secret/data/order-service/*" {
  capabilities = ["read"]
}
path "secret/metadata/order-service/*" {
  capabilities = ["list"]
}

# ── product-service ───────────────────────────────────────────
# Reads: MongoDB connection credentials
path "secret/data/product-service/*" {
  capabilities = ["read"]
}
path "secret/metadata/product-service/*" {
  capabilities = ["list"]
}

# ── notification-service ──────────────────────────────────────
# Reads: Redis password (required in production, empty in local dev)
path "secret/data/notification-service/*" {
  capabilities = ["read"]
}
path "secret/metadata/notification-service/*" {
  capabilities = ["list"]
}

# ── Dynamic Database Credentials (planned Phase 2) ────────────
# Vault's database secrets engine generates short-lived PostgreSQL
# credentials on demand — more secure than static passwords:
#   - Auto-rotate based on TTL (e.g. 1h)
#   - Compromised creds expire quickly
#   - Full audit trail per service
#
# Uncomment when the database secrets engine is configured:
# path "database/creds/user-service-role" {
#   capabilities = ["read"]
# }
# path "database/creds/order-service-role" {
#   capabilities = ["read"]
# }
