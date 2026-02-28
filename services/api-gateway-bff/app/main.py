# ============================================================
# app/main.py — api-gateway-bff (Backend For Frontend)
# ============================================================
# WHY a BFF (Backend For Frontend)?
#   - The frontend doesn't need to know about 6 different service URLs
#   - The BFF aggregates multiple service calls into one API response
#     (reduces frontend round-trips and simplifies client code)
#   - Cross-cutting concerns (auth headers forwarding, timeout handling)
#     live in ONE place instead of every frontend API call
#
# This service proxies and aggregates; it owns NO data itself.
# Kong Gateway is the L4 ingress; the BFF is L7 business logic aggregation.

import os
import time
from typing import Optional

import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    PORT: int = 3001
    USER_SERVICE_URL: str    = "http://user-service:3000"
    PRODUCT_SERVICE_URL: str = "http://product-service:8000"
    ORDER_SERVICE_URL: str   = "http://order-service:8080"
    PAYMENT_SERVICE_URL: str = "http://payment-service:8090"
    # Kubernetes DNS format: http://<service-name>.<namespace>.svc.cluster.local:<port>
    # Short form works within the same namespace.

    class Config:
        env_file = ".env"


settings = Settings()

app = FastAPI(
    title="api-gateway-bff",
    description="Backend For Frontend — aggregates microservice calls",
    version="1.0.0",
)

# ── Prometheus ────────────────────────────────────────────────
REQUEST_COUNT   = Counter('bff_http_requests_total', 'BFF total requests', ['method', 'path', 'status'])
REQUEST_LATENCY = Histogram('bff_request_latency_seconds', 'BFF request latency', ['path'])

@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    REQUEST_COUNT.labels(request.method, request.url.path, response.status_code).inc()
    REQUEST_LATENCY.labels(request.url.path).observe(time.time() - start)
    return response

# ── Shared HTTP client ────────────────────────────────────────
# One client shared across all requests with connection pooling.
# timeout=10 means we fail fast if an upstream is slow.
http_client = httpx.AsyncClient(timeout=10.0)


@app.on_event("shutdown")
async def shutdown():
    await http_client.aclose()


def forward_auth(request: Request) -> dict:
    """Extract and forward the Authorization header to upstream services."""
    headers = {}
    auth = request.headers.get("Authorization")
    if auth:
        headers["Authorization"] = auth
    return headers


# ── Health & Metrics ──────────────────────────────────────────
@app.get("/health", tags=["platform"])
async def health():
    return {"status": "ok", "service": "api-gateway-bff"}


@app.get("/metrics", tags=["platform"])
async def metrics_endpoint():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


# ── Aggregated Endpoints ──────────────────────────────────────

@app.get("/api/dashboard", tags=["aggregate"])
async def dashboard(request: Request):
    """
    Returns a combined view: user profile + recent orders + featured products.
    The frontend calls ONE endpoint instead of three.
    """
    headers = forward_auth(request)

    async with httpx.AsyncClient(timeout=10.0) as client:
        # Fan-out: fire all three calls concurrently
        import asyncio
        user_task     = client.get(f"{settings.USER_SERVICE_URL}/users/me", headers=headers)
        orders_task   = client.get(f"{settings.ORDER_SERVICE_URL}/orders",  headers=headers)
        products_task = client.get(f"{settings.PRODUCT_SERVICE_URL}/products?limit=5")

        user_res, orders_res, products_res = await asyncio.gather(
            user_task, orders_task, products_task,
            return_exceptions=True
        )

    # Gracefully handle individual service failures
    user     = user_res.json()     if not isinstance(user_res, Exception)     and user_res.status_code == 200     else None
    orders   = orders_res.json()   if not isinstance(orders_res, Exception)   and orders_res.status_code == 200   else []
    products = products_res.json() if not isinstance(products_res, Exception) and products_res.status_code == 200 else []

    return {
        "user": user,
        "recent_orders": orders[:5],
        "featured_products": products,
    }


# ── Proxy Endpoints ───────────────────────────────────────────
# Simple transparent proxies — the BFF forwards requests to the right service.
# This means the frontend only needs to know the BFF URL.

@app.api_route("/api/users/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy_users(path: str, request: Request):
    return await _proxy(request, f"{settings.USER_SERVICE_URL}/{path}")

@app.api_route("/api/products/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy_products(path: str, request: Request):
    return await _proxy(request, f"{settings.PRODUCT_SERVICE_URL}/products/{path}")

@app.api_route("/api/products", methods=["GET", "POST"])
async def proxy_products_root(request: Request):
    qs = str(request.url.query)
    url = f"{settings.PRODUCT_SERVICE_URL}/products"
    if qs:
        url += f"?{qs}"
    return await _proxy(request, url)

@app.api_route("/api/orders/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy_orders(path: str, request: Request):
    return await _proxy(request, f"{settings.ORDER_SERVICE_URL}/orders/{path}")

@app.api_route("/api/orders", methods=["GET", "POST"])
async def proxy_orders_root(request: Request):
    return await _proxy(request, f"{settings.ORDER_SERVICE_URL}/orders")

@app.api_route("/api/payments/{path:path}", methods=["GET", "POST"])
async def proxy_payments(path: str, request: Request):
    return await _proxy(request, f"{settings.PAYMENT_SERVICE_URL}/payments/{path}")

@app.api_route("/api/payments", methods=["GET", "POST"])
async def proxy_payments_root(request: Request):
    return await _proxy(request, f"{settings.PAYMENT_SERVICE_URL}/payments")

@app.api_route("/api/auth/{path:path}", methods=["POST"])
async def proxy_auth(path: str, request: Request):
    return await _proxy(request, f"{settings.USER_SERVICE_URL}/auth/{path}")


async def _proxy(request: Request, target_url: str) -> Response:
    """Generic reverse proxy — forwards method, headers, and body."""
    headers = dict(request.headers)
    headers.pop("host", None)  # Remove original Host header
    body = await request.body()

    try:
        upstream = await http_client.request(
            method=request.method,
            url=target_url,
            headers=headers,
            content=body,
        )
        return Response(
            content=upstream.content,
            status_code=upstream.status_code,
            headers=dict(upstream.headers),
        )
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Upstream service timed out")
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail="Could not connect to upstream service")
