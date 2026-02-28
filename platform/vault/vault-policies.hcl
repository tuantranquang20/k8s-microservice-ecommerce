# ============================================================
# vault-policies.hcl — HCL Policies for Services
# ============================================================
# Vault uses HCL (HashiCorp Configuration Language) for policies.
# Policies define WHAT a token/role can do — this is the authz layer.
#
# Apply these after Vault is running:
#   vault policy write user-service platform/vault/vault-policies.hcl

# ── user-service policy ────────────────────────────────────────
# user-service needs to READ its DB credentials and JWT secret.
# It should NEVER be able to write or delete secrets.

path "secret/data/user-service/*" {
  capabilities = ["read"]
  # LEARNING NOTE: "capabilities" is a list of allowed operations:
  # create, read, update, delete, list, sudo
  # Principle of least privilege: only grant what's needed.
}

path "secret/metadata/user-service/*" {
  capabilities = ["list"]   # Allow listing secret names (not values)
}

# ── payment-service policy ────────────────────────────────────
# payment-service needs its JWT secret and (future) payment provider API keys.
path "secret/data/payment-service/*" {
  capabilities = ["read"]
}

path "secret/metadata/payment-service/*" {
  capabilities = ["list"]
}

# ── Dynamic Database Credentials (advanced — for future use) ──
# Vault's database secrets engine can generate short-lived PostgreSQL
# credentials on demand. This is more secure than static passwords:
#   - Credentials auto-rotate based on TTL
#   - Compromised creds expire quickly
#   - Full audit trail of who got which credentials
#
# PRODUCTION: enable the database secrets engine and replace static
# DB passwords with dynamic credentials:
# path "database/creds/user-service-role" {
#   capabilities = ["read"]
# }
