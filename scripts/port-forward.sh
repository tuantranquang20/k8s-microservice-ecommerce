#!/usr/bin/env bash
# ============================================================
# scripts/port-forward.sh — Forward all service + platform tool ports
# ============================================================
# Runs port-forwards in the background so you can reach every service
# and platform UI directly from localhost.
#
# Usage:
#   ./scripts/port-forward.sh          (default: dev namespace)
#   ./scripts/port-forward.sh staging  (staging namespace)
#
# Stop all: Ctrl-C   or:   kill $(cat /tmp/pf-pids.txt)
# ============================================================

set -e

NS="${1:-ecommerce-dev}"
echo "==> Port-forwarding services in namespace: $NS"
echo "    Press Ctrl-C to stop all port-forwards"
echo ""

pids=()

port_forward() {
  local svc=$1 ns=$2 local_port=$3 remote_port=$4
  kubectl port-forward "svc/$svc" "$local_port:$remote_port" -n "$ns" &>/dev/null &
  pids+=($!)
}

# ── Application services ──────────────────────────────────────
echo "  Application services:"
echo "    user-service        → http://localhost:3000"
echo "    product-service     → http://localhost:8000"
echo "    order-service       → http://localhost:8080"
echo "    payment-service     → http://localhost:8090"
echo "    notification-service→ http://localhost:3002"
echo "    api-gateway-bff     → http://localhost:3001"
echo "    frontend            → http://localhost:8888"
port_forward user-service         "$NS"  3000 3000
port_forward product-service      "$NS"  8000 8000
port_forward order-service        "$NS"  8080 8080
port_forward payment-service      "$NS"  8090 8090
port_forward notification-service "$NS"  3002 3002
port_forward api-gateway-bff      "$NS"  3001 3001
port_forward frontend             "$NS"  8888 80

echo ""

# ── Platform tools ────────────────────────────────────────────
echo "  Platform tools:"
echo "    ArgoCD UI    → https://localhost:8443  (admin / see below)"
echo "    Grafana UI   → http://localhost:3030   (admin / admin-local-dev)"
echo "    Prometheus   → http://localhost:9090"
echo "    Vault UI     → http://localhost:8200   (token: root)"
echo "    Kong Admin   → http://localhost:8002   (Kong OSS — no auth)"

# ArgoCD: HTTPS on 443, forward to 8443 to avoid needing sudo
port_forward argocd-server   argocd     8443 443
port_forward kube-prometheus-stack-grafana monitoring 3030 80
port_forward prometheus-operated          monitoring 9090 9090
port_forward vault                        default    8200 8200

# Kong Admin API (only available if Kong is installed)
kubectl get svc kong-proxy -n kong &>/dev/null \
  && port_forward kong-proxy kong 8002 8002 \
  || echo "    (Kong not installed — skipping Kong Admin)"

echo ""
echo "  ArgoCD admin password:"
echo '    kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d'
echo ""

# Save PIDs for external kill
printf '%s\n' "${pids[@]}" > /tmp/pf-pids.txt

# Wait until Ctrl-C
trap 'echo ""; echo "Stopping port-forwards..."; kill "${pids[@]}" 2>/dev/null; exit' INT
wait
