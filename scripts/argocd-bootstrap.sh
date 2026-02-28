#!/usr/bin/env bash
# ============================================================
# scripts/argocd-bootstrap.sh — Install ArgoCD and register the App-of-Apps
# ============================================================
set -e

ARGOCD_VERSION="v2.10.0"

echo "==> [1/4] Creating argocd namespace..."
kubectl create namespace argocd 2>/dev/null || echo "    Namespace already exists"

echo ""
echo "==> [2/4] Installing ArgoCD $ARGOCD_VERSION..."
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"

echo ""
echo "==> [3/4] Waiting for ArgoCD server to become ready..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=120s

echo ""
echo "==> [4/4] Applying App-of-Apps root Application..."
kubectl apply -f argocd/apps/app-of-apps.yaml

echo ""
echo "  ArgoCD installed! Access the UI:"
echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "    Username: admin"
echo '    Password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d'
