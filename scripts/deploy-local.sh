#!/usr/bin/env bash
# ============================================================
# scripts/deploy-local.sh — Build & push all images, then deploy via Helm
# ============================================================
# Run after local-setup.sh has created the cluster and registry.
# Builds all 7 Docker images, pushes to k3d-local-registry:5050,
# then deploys databases first (via helm with 20m timeout) and
# services second (via helm upgrade --install for each service).
#
# WHY not use skaffold run?
#   Skaffold's k3d integration rewrites image names and adds git-hash
#   tags (e.g. localhost:5050/k3d-local-registry_5050_user-service:abc123)
#   which breaks the pre-built :latest images. Helm + values-local.yaml
#   uses the correct k3d-local-registry:5050/<service>:latest directly.

set -e

NAMESPACE="ecommerce-dev"
REGISTRY="k3d-local-registry:5050"
HELM_TIMEOUT="5m0s"
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
echo "    Registry:  $REGISTRY"
echo "    Namespace: $NAMESPACE"
echo "    Services:  ${SERVICES[*]}"
echo ""

# ── Step 1: Build and push each service image ────────────────
for svc in "${SERVICES[@]}"; do
  echo "==> [build] $svc..."
  docker build --no-cache \
    --tag "$REGISTRY/$svc:latest" \
    "services/$svc/" 
  docker push "$REGISTRY/$svc:latest"
  echo "    $svc ✓"
  echo ""
done

# ── Step 2: Install / upgrade databases (separate helm call) ─
echo "==> [databases] Installing/upgrading Bitnami charts (timeout: 20m)..."
echo "    (PostgreSQL + MongoDB + Redis images are large — this step can take 10-15 min on first run)"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if helm status databases -n "$NAMESPACE" > /dev/null 2>&1; then
  echo "    databases release exists — upgrading..."
  helm upgrade databases ./helm-charts/databases \
    -n "$NAMESPACE" \
    -f helm-charts/databases/values.yaml \
    -f helm-charts/databases/values-local.yaml \
    --wait \
    --timeout 20m0s
else
  echo "    databases release not found — installing..."
  helm install databases ./helm-charts/databases \
    -n "$NAMESPACE" \
    -f helm-charts/databases/values.yaml \
    -f helm-charts/databases/values-local.yaml \
    --wait \
    --timeout 20m0s
fi
echo "    databases ✓ All DB pods are Running"
echo ""

# ── Step 3: Deploy application services via Helm ─────────────
# We deploy directly with helm instead of skaffold because Skaffold's
# automatic k3d registry integration rewrites image names and tags,
# breaking the pre-built :latest images from step 1.
# values-local.yaml for each service already has the correct:
#   image.repository: k3d-local-registry:5050/<service>
#   image.tag: latest
echo "==> [services] Deploying application services..."
for svc in "${SERVICES[@]}"; do
  echo -n "    helm upgrade --install $svc ... "
  if helm upgrade --install "$svc" "./helm-charts/$svc" \
    -n "$NAMESPACE" \
    -f "helm-charts/$svc/values.yaml" \
    -f "helm-charts/$svc/values-local.yaml" \
    --wait \
    --timeout "$HELM_TIMEOUT" 2>&1; then
    echo "✓"
  else
    echo "✗ FAILED"
    echo "    Checking pod status..."
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$svc"
    kubectl logs -l "app.kubernetes.io/name=$svc" -n "$NAMESPACE" --tail=20 2>/dev/null || true
  fi
done

echo ""
echo "============================================================"
echo "  Deployment complete!"
echo ""
echo "  Services accessible at: http://localhost/"
echo "  API gateway:            http://localhost/api/"
echo ""
echo "  Useful commands:"
echo "    kubectl get pods -n $NAMESPACE"
echo "    kubectl logs -l app.kubernetes.io/name=user-service -n $NAMESPACE -f"
echo "    kubectl logs -l app.kubernetes.io/name=order-service -n $NAMESPACE -f"
echo "============================================================"
