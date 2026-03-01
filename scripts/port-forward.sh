#!/usr/bin/env bash
# ============================================================
# scripts/port-forward.sh — Forward all service ports to localhost
# ============================================================
# Runs 6 port-forwards in the background so you can curl each service
# directly during development without going through Kong.
#
# Usage:
#   ./scripts/port-forward.sh          (default: dev namespace)
#   ./scripts/port-forward.sh staging  (staging namespace)
#
# Stop all: Ctrl-C or: kill $(cat /tmp/pf-pids.txt)

set -e

NS="${1:-ecommerce-dev}"
echo "==> Port-forwarding services in namespace: $NS"
echo "    Press Ctrl-C to stop all port-forwards"
echo ""

pids=()

port_forward() {
  local svc=$1 local_port=$2 remote_port=$3
  echo "    $svc → localhost:$local_port"
  kubectl port-forward "svc/$svc" "$local_port:$remote_port" -n "$NS" &>/dev/null &
  pids+=($!)
}

port_forward user-service      3000 3000
port_forward product-service   8000 8000
port_forward order-service     8080 8080
port_forward payment-service   8090 8090
port_forward notification-service 3002 3002
port_forward api-gateway-bff   3001 3001
port_forward frontend          8888 80

echo ""
echo "  All services forwarded! Test with:"
echo "    curl http://localhost:3000/health   # user-service"
echo "    curl http://localhost:8000/health   # product-service"
echo "    curl http://localhost:8080/health   # order-service"
echo "    curl http://localhost:3001/health   # api-gateway-bff"
echo "    open http://localhost:8888/          # frontend"
echo ""

# Save PIDs for external kill
printf '%s\n' "${pids[@]}" > /tmp/pf-pids.txt

# Wait until Ctrl-C
trap 'echo ""; echo "Stopping port-forwards..."; kill "${pids[@]}" 2>/dev/null; exit' INT
wait
