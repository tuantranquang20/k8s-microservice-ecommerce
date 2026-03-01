#!/usr/bin/env bash
# ============================================================
# scripts/kong-install.sh — Install Kong Ingress Controller
# ============================================================
# Installs Kong Gateway (Ingress Controller mode) then applies
# the platform Kong config: plugins, KongIngress, and routes.
#
# Usage:
#   ./scripts/kong-install.sh             # install into kong namespace
#   ./scripts/kong-install.sh ecommerce-dev  # custom namespace
#
# Prerequisites: kubectl configured, helm installed (run get_helm.sh first)
# ============================================================

set -e

KONG_NS="kong"
KONG_VERSION="2.38.0"   # Kong Ingress Controller chart version

echo "==> [1/5] Adding Kong Helm repo..."
helm repo add kong https://charts.konghq.com 2>/dev/null || true
helm repo update

echo ""
echo "==> [2/5] Installing Kong Ingress Controller (v$KONG_VERSION)..."
echo "    Namespace: $KONG_NS"
kubectl create namespace "$KONG_NS" 2>/dev/null || echo "    Namespace already exists"

helm upgrade --install kong kong/ingress \
  --namespace "$KONG_NS" \
  --version "$KONG_VERSION" \
  --set controller.ingressClass=kong \
  --set controller.installCRDs=true \
  --wait --timeout 5m0s

echo ""
echo "==> [3/5] Waiting for Kong controller to be ready..."
kubectl wait --for=condition=available deployment \
  -l app.kubernetes.io/name=ingress-kong \
  -n "$KONG_NS" \
  --timeout=120s

echo ""
echo "==> [4/5] Applying Kong platform config..."

echo "    KongPlugin resources (rate-limiting, key-auth, request-transformer)..."
kubectl apply -f platform/kong/kong-plugins.yaml

echo "    KongIngress (upstream health checks + timeouts)..."
kubectl apply -f platform/kong/kong-ingress.yaml

echo "    Ingress routes (all service routes)..."
kubectl apply -f platform/kong/routes.yaml

echo ""
echo "==> [5/5] Verifying Kong pod status..."
kubectl get pods -n "$KONG_NS"

KONG_IP=$(kubectl get svc -n "$KONG_NS" -l app.kubernetes.io/name=ingress-kong \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "<pending>")

echo ""
echo "============================================================"
echo "  Kong installed! Gateway IP: $KONG_IP"
echo ""
echo "  Test routes:"
echo "    curl http://$KONG_IP/api/auth/login     # user-service"
echo "    curl http://$KONG_IP/api/products       # product-service"
echo "    curl http://$KONG_IP/health             # Kong health"
echo ""
echo "  Access Kong Manager (if enterprise):"
echo "    kubectl port-forward svc/kong-manager 8002:8002 -n $KONG_NS"
echo "============================================================"
