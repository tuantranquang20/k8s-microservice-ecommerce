# product-service

Python + FastAPI microservice for product catalog management, backed by MongoDB.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/products` | List products (filter: `?category=` `?search=`) paginated |
| GET | `/products/{id}` | Get product by MongoDB ObjectId |
| POST | `/products` | Create product |
| PATCH | `/products/{id}` | Partial update |
| DELETE | `/products/{id}` | Delete product |
| GET | `/health` | Liveness/readiness probe (pings MongoDB) |
| GET | `/metrics` | Prometheus scrape endpoint |
| GET | `/docs` | Auto-generated Swagger UI (dev only) |

## Run Locally with Docker

```bash
cp .env.example .env

# Start MongoDB
docker run -d --name mongo -p 27017:27017 mongo:7.0

# Build and run
docker build -t product-service .
docker run --rm -p 8000:8000 \
  --env-file .env \
  -e MONGO_URI=mongodb://host.docker.internal:27017 \
  product-service

# Test
curl http://localhost:8000/health
curl http://localhost:8000/docs   # Swagger UI
curl -X POST http://localhost:8000/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Widget","description":"A fine widget","price":9.99,"stock":100,"category":"widgets"}'
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8000` | Server port |
| `MONGO_URI` | `mongodb://localhost:27017` | MongoDB connection string |
| `MONGO_DB` | `products` | Database name |
| `JWT_SECRET` | *(required)* | For validating tokens from user-service |

## MongoDB Index

A compound text index on `name` + `description` is created at startup to power the `?search=` query parameter.
