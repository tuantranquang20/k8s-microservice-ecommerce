#!/usr/bin/env bash
# ============================================================
# scripts/argocd-bootstrap.sh — Install ArgoCD + register App-of-Apps
# ============================================================
# Run ONCE after a fresh cluster to bootstrap the GitOps control plane.
# After this runs, ArgoCD manages all further deployments automatically.
#
# Full bootstrap order for a new cluster:
#   1. ./scripts/local-setup.sh      ← create k3d cluster
#   2. ./scripts/argocd-bootstrap.sh ← install ArgoCD (this script)
#   3. ./scripts/kong-install.sh     ← install Kong ingress controller
#   4. ./scripts/vault-setup.sh      ← seed Vault secrets
#   5. kubectl apply -f platform/observability/  ← ServiceMonitors + dashboards
# ============================================================

set -e

ARGOCD_VERSION="v2.10.0"

echo "==> [1/5] Creating argocd namespace..."
kubectl create namespace argocd 2>/dev/null || echo "    Namespace already exists"

echo ""
echo "==> [2/5] Installing ArgoCD $ARGOCD_VERSION..."
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"

echo ""
echo "==> [3/5] Waiting for ArgoCD server deployment to be available..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=180s

echo ""
echo "==> [4/5] Waiting for ArgoCD CRDs to be fully registered..."
# LEARNING NOTE — Race condition: kubectl apply returns as soon as the Deployment
# is created, but the CRDs (Application, AppProject) need a few more seconds to
# propagate through the API server. Applying app-of-apps.yaml too early causes:
#   "no matches for kind Application in version argoproj.io/v1alpha1"
until kubectl get crd applications.argoproj.io &>/dev/null; do
  echo "    Waiting for Application CRD..."
  sleep 5
done
echo "    ArgoCD CRDs ready!"

echo ""
echo "==> [5/5] Applying App-of-Apps root Application..."
kubectl apply -f argocd/apps/app-of-apps.yaml

echo ""
echo "============================================================"
echo "  ArgoCD installed and App-of-Apps registered!"
echo ""
echo "  Access the ArgoCD UI:"
echo "    kubectl port-forward svc/argocd-server -n argocd 8443:443"
echo "    open https://localhost:8443"
echo "    Username: admin"
echo '    Password: kubectl get secret argocd-initial-admin-secret \'
echo '              -n argocd -o jsonpath="{.data.password}" | base64 -d'
echo ""
echo "  ArgoCD will now sync all Applications from Git automatically."
echo "  Next steps:"
echo "    ./scripts/kong-install.sh    ← install Kong ingress controller"
echo "    ./scripts/vault-setup.sh     ← seed Vault secrets"
echo "============================================================"
