#!/usr/bin/env bash
# ============================================================
# scripts/deploy-local.sh — Build & push all images, then deploy via Skaffold
# ============================================================
# Run after local-setup.sh has created the cluster and registry.
# Builds all 7 Docker images, pushes to k3d-local-registry:5050,
# then runs Skaffold to deploy via Helm.

set -e

REGISTRY="k3d-local-registry:5050"
SERVICES=(
  "user-service"
  "product-service"
  "order-service"
  "payment-service"
  "notification-service"
  "api-gateway-bff"
  "frontend"
)

echo "==> Starting local deployment"
echo "    Registry: $REGISTRY"
echo "    Services: ${SERVICES[*]}"
echo ""

# ── Build and push each service ─────────────────────────────
for svc in "${SERVICES[@]}"; do
  echo "==> Building $svc..."
  docker build \
    --tag "$REGISTRY/$svc:latest" \
    "services/$svc/"
  echo "==> Pushing $svc to $REGISTRY..."
  docker push "$REGISTRY/$svc:latest"
  echo "    $svc ✓"
  echo ""
done

echo "==> All images pushed. Running skaffold..."
echo ""
# skaffold run renders and applies Helm charts in dependency order.
# The local profile uses values-local.yaml overrides (k3d registry, reduced resources).
skaffold run --profile=local

echo ""
echo "============================================================"
echo "  Deployment complete!"
echo "  Services should be accessible at http://localhost/"
echo "  Check pod status: kubectl get pods -n ecommerce-dev"
echo "  View logs: kubectl logs -l app.kubernetes.io/name=user-service -n ecommerce-dev"
echo "============================================================"
