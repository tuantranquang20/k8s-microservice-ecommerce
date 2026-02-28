#!/usr/bin/env bash
# ============================================================
# scripts/local-setup.sh — One-time local development environment setup
# ============================================================
# Run this ONCE before starting local development.
# It sets up the k3d registry and cluster.
#
# Requirements (install binaries manually per AGENTS.md — no Homebrew):
#   - k3d    https://k3d.io/latest/#installation
#   - kubectl https://kubernetes.io/docs/tasks/tools/
#   - docker  https://docs.docker.com/engine/install/

set -e  # Exit immediately on any error (AGENTS.md requirement)

echo "==> [1/4] Checking prerequisites..."
command -v k3d    >/dev/null 2>&1 || { echo "ERROR: k3d not found. Install from https://k3d.io"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found."; exit 1; }
echo "    Prerequisites OK"

echo ""
echo "==> [2/4] Creating k3d local registry..."
# Check if registry already exists
if k3d registry list 2>/dev/null | grep -q "k3d-local-registry"; then
  echo "    Registry 'k3d-local-registry' already exists — skipping"
else
  k3d registry create local-registry --port 5050
  echo "    Registry created: k3d-local-registry:5050"
fi

echo ""
echo "==> [3/4] Creating k3d cluster 'ecommerce-local'..."
if k3d cluster list 2>/dev/null | grep -q "ecommerce-local"; then
  echo "    Cluster 'ecommerce-local' already exists — skipping"
else
  k3d cluster create ecommerce-local \
    --servers 1 \
    --agents 2 \
    --port "80:80@loadbalancer" \
    --registry-use k3d-local-registry:5050 \
    --k3s-arg "--disable=traefik@server:0"
    # We disable Traefik because Kong Gateway is our ingress controller.
  echo "    Cluster created with 1 server + 2 agents"
fi

echo ""
echo "==> [4/4] Patching /etc/hosts for registry..."
REGISTRY_ENTRY="127.0.0.1 k3d-local-registry"
if grep -q "k3d-local-registry" /etc/hosts; then
  echo "    Entry already exists in /etc/hosts — skipping"
else
  echo "    Adding '$REGISTRY_ENTRY' to /etc/hosts (requires sudo)"
  echo "$REGISTRY_ENTRY" | sudo tee -a /etc/hosts >/dev/null
  echo "    /etc/hosts updated"
fi

echo ""
echo "============================================================"
echo "  Local setup complete!"
echo ""
echo "  Registry:  k3d-local-registry:5050"
echo "  Cluster:   ecommerce-local"
echo ""
echo "  Next steps:"
echo "    1. Update kubeconfig: kubectl config use-context k3d-ecommerce-local"
echo "    2. Build & deploy:    ./scripts/deploy-local.sh"
echo "============================================================"
