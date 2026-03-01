#!/usr/bin/env bash
# ============================================================
# scripts/istio-install.sh — Install Istio on the EKS cluster
# ============================================================
# Uses istioctl binary directly (no Helm, no Homebrew).
#
# Prerequisites:
#   - istioctl binary in PATH (download from https://github.com/istio/istio/releases)
#     Example: curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.22.0 sh -
#              mv istio-1.22.0/bin/istioctl /usr/local/bin/istioctl
#   - kubectl pointed at the target EKS cluster
#   - AWS credentials configured (for EKS kubeconfig)
#
# LEARNING NOTE — Why istioctl install vs Helm?
#   istioctl install uses the IstioOperator CRD and handles:
#   - Pre-flight cluster checks (API server version, CPU, RAM)
#   - Correct ordering of CRD installation (Istio has 60+ CRDs)
#   - Profile presets: minimal, demo, default, preview
#   We use the "default" profile — suitable for production EKS.

set -e

ISTIO_VERSION="1.22.0"
NAMESPACE="istio-system"

echo "==> [1/5] Checking prerequisites..."
command -v istioctl >/dev/null 2>&1 || {
  echo "ERROR: istioctl not found."
  echo "Install: curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -"
  echo "Then: mv istio-${ISTIO_VERSION}/bin/istioctl /usr/local/bin/istioctl"
  exit 1
}
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found."; exit 1; }
echo "    Prerequisites OK (istioctl $(istioctl version --remote=false 2>/dev/null | head -1))"

echo ""
echo "==> [2/5] Running Istio pre-flight check..."
istioctl x precheck
echo "    Pre-flight check passed"

echo ""
echo "==> [3/5] Installing Istio (default profile)..."
# IstioOperator config file gives us fine-grained control.
# Using our custom config in platform/istio/istio-operator.yaml
istioctl install -f platform/istio/istio-operator.yaml --skip-confirmation

echo ""
echo "==> [4/5] Waiting for Istio control plane to be ready..."
kubectl wait --for=condition=available deployment/istiod \
  -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=available deployment/istio-ingressgateway \
  -n "$NAMESPACE" --timeout=120s
echo "    Istio control plane ready"

echo ""
echo "==> [5/5] Deploying Kiali + Jaeger addons..."
# Official Istio addon manifests (bundled with the istio release tarball)
# For learning, we apply them directly from the istio samples directory.
# Replace ISTIO_RELEASE_PATH with the path to your downloaded istio tarball.
ISTIO_RELEASE_PATH="${ISTIO_RELEASE_PATH:-./istio-${ISTIO_VERSION}}"

if [ -d "$ISTIO_RELEASE_PATH/samples/addons" ]; then
  kubectl apply -f "$ISTIO_RELEASE_PATH/samples/addons/kiali.yaml"
  kubectl apply -f "$ISTIO_RELEASE_PATH/samples/addons/jaeger.yaml"
  kubectl apply -f "$ISTIO_RELEASE_PATH/samples/addons/prometheus.yaml"
  kubectl wait --for=condition=available deployment/kiali  -n istio-system --timeout=120s
  kubectl wait --for=condition=available deployment/jaeger -n istio-system --timeout=120s
  echo "    Kiali + Jaeger ready"
else
  echo "    WARNING: Istio addons directory not found at $ISTIO_RELEASE_PATH/samples/addons"
  echo "    Apply platform/istio/kiali.yaml and platform/istio/jaeger.yaml manually."
fi

echo ""
echo "============================================================"
echo "  Istio installed!"
echo ""
echo "  Enable sidecar injection on ecommerce namespace:"
echo "    kubectl label namespace ecommerce-dev istio-injection=enabled"
echo ""
echo "  Apply all Istio resources:"
echo "    kubectl apply -f platform/istio/"
echo ""
echo "  Access Kiali dashboard:"
echo "    istioctl dashboard kiali"
echo ""
echo "  Access Jaeger dashboard:"
echo "    istioctl dashboard jaeger"
echo "============================================================"
