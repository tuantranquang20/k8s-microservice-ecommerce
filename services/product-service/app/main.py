# ============================================
# app/main.py — product-service FastAPI App
# ============================================
# WHY FastAPI for product-service?
#   - Auto-generated OpenAPI docs at /docs
#   - Native async support (perfect for I/O-heavy DB calls)
#   - Pydantic integration for request validation
#   - Python's ecosystem makes it easy to add ML-based product recommendations later

import os
import time
from typing import Optional, List
from datetime import datetime

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse, Response
from bson import ObjectId
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

from .database import connect_to_mongo, close_mongo_connection, get_database, settings
from .models import ProductCreate, ProductUpdate, ProductResponse

# ── App Initialisation ────────────────────────────────────────
app = FastAPI(
    title="product-service",
    description="Product catalogue microservice — FastAPI + MongoDB",
    version="1.0.0",
    # Disable Swagger UI in production (expose internally only)
    docs_url="/docs" if os.getenv("PYTHON_ENV") != "production" else None,
)

# ── Lifecycle Events ──────────────────────────────────────────
# on_event startup/shutdown is used to manage the MongoDB connection pool.
# This is the recommended pattern — connection is shared across all requests.
@app.on_event("startup")
async def startup():
    await connect_to_mongo()

@app.on_event("shutdown")
async def shutdown():
    await close_mongo_connection()

# ── Prometheus Metrics ────────────────────────────────────────
REQUEST_COUNT = Counter(
    'product_service_http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status_code']
)
REQUEST_LATENCY = Histogram(
    'product_service_request_latency_seconds',
    'Request latency in seconds',
    ['endpoint']
)

@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    REQUEST_COUNT.labels(request.method, request.url.path, response.status_code).inc()
    REQUEST_LATENCY.labels(request.url.path).observe(duration)
    return response

# ── Health Endpoint ───────────────────────────────────────────
@app.get("/health", tags=["platform"])
async def health():
    """
    Kubernetes liveness and readiness probe.
    Pings MongoDB to confirm the service is fully operational.
    """
    try:
        db = get_database()
        await db.command("ping")
        return {"status": "ok", "service": "product-service", "db": "connected"}
    except Exception as e:
        return JSONResponse(
            status_code=503,
            content={"status": "error", "service": "product-service", "db": str(e)}
        )

# ── Metrics Endpoint ──────────────────────────────────────────
@app.get("/metrics", tags=["platform"])
async def metrics():
    """Prometheus scrape endpoint."""
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

# ── Helper: serialise MongoDB document ────────────────────────
def serialise_product(doc: dict) -> dict:
    """Convert MongoDB _id (ObjectId) to a string 'id' field."""
    doc["id"] = str(doc.pop("_id"))
    return doc

# ── CRUD Endpoints ────────────────────────────────────────────

@app.get("/products", response_model=List[ProductResponse], tags=["products"])
async def list_products(
    category: Optional[str] = Query(None, description="Filter by category"),
    search:   Optional[str] = Query(None, description="Full-text search on name/description"),
    skip:     int           = Query(0, ge=0),
    limit:    int           = Query(20, ge=1, le=100),
):
    """List products with optional category filter and full-text search."""
    db = get_database()
    query = {}
    if category:
        query["category"] = category
    if search:
        # Uses the text index created in database.py startup
        query["$text"] = {"$search": search}

    cursor = db.products.find(query).skip(skip).limit(limit)
    products = [serialise_product(doc) async for doc in cursor]
    return products


@app.get("/products/{product_id}", response_model=ProductResponse, tags=["products"])
async def get_product(product_id: str):
    """Get a single product by its MongoDB ObjectId."""
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID format")

    db = get_database()
    doc = await db.products.find_one({"_id": ObjectId(product_id)})
    if not doc:
        raise HTTPException(status_code=404, detail="Product not found")

    return serialise_product(doc)


@app.post("/products", response_model=ProductResponse, status_code=201, tags=["products"])
async def create_product(payload: ProductCreate):
    """Create a new product. In production this route is gated behind key-auth Kong plugin."""
    db = get_database()
    doc = payload.model_dump()
    doc["created_at"] = datetime.utcnow()
    doc["updated_at"] = None

    result = await db.products.insert_one(doc)
    created = await db.products.find_one({"_id": result.inserted_id})
    return serialise_product(created)


@app.patch("/products/{product_id}", response_model=ProductResponse, tags=["products"])
async def update_product(product_id: str, payload: ProductUpdate):
    """Partial update — only provided fields are changed (PATCH semantics)."""
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID format")

    db = get_database()
    # model_dump(exclude_none=True) skips fields the client didn't provide
    updates = payload.model_dump(exclude_none=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields provided for update")

    updates["updated_at"] = datetime.utcnow()
    result = await db.products.update_one(
        {"_id": ObjectId(product_id)},
        {"$set": updates}
    )

    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Product not found")

    updated = await db.products.find_one({"_id": ObjectId(product_id)})
    return serialise_product(updated)


@app.delete("/products/{product_id}", status_code=204, tags=["products"])
async def delete_product(product_id: str):
    """Delete a product by ID."""
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID format")

    db = get_database()
    result = await db.products.delete_one({"_id": ObjectId(product_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Product not found")
    # 204 No Content — no body returned
