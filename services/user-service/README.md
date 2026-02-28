# user-service

Node.js + Express microservice handling user registration, authentication (JWT), and profile management backed by PostgreSQL.

## Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/register` | ✗ | Register a new user |
| POST | `/auth/login` | ✗ | Login, receive JWT |
| GET | `/users/me` | ✓ | Get own profile |
| GET | `/users/:id` | ✓ | Get user by ID (service-to-service) |
| PUT | `/users/me` | ✓ | Update own name |
| GET | `/health` | ✗ | Liveness/readiness probe (checks DB) |
| GET | `/metrics` | ✗ | Prometheus metrics scrape endpoint |

## Run Locally with Docker

```bash
# 1. Copy env file
cp .env.example .env

# 2. Start Postgres + service
docker run -d --name postgres \
  -e POSTGRES_DB=users \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=changeme \
  -p 5432:5432 postgres:16-alpine

# 3. Build and run user-service
docker build -t user-service .
docker run --rm -p 3000:3000 \
  --env-file .env \
  -e DB_HOST=host.docker.internal \
  user-service

# 4. Test
curl -s http://localhost:3000/health | jq
curl -s -X POST http://localhost:3000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com","password":"password123","name":"Alice"}' | jq
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3000` | Server port |
| `NODE_ENV` | `development` | Runtime environment |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | `users` | Database name |
| `DB_USER` | `postgres` | DB username |
| `DB_PASSWORD` | *(required)* | DB password — injected by Vault in prod |
| `JWT_SECRET` | *(required)* | JWT signing secret — injected by Vault in prod |
| `JWT_EXPIRES_IN` | `7d` | Token expiry |

## Vault Secret Paths

In production, Vault Agent injects these secrets as environment variables:
- `secret/data/user-service/db` → `DB_PASSWORD`
- `secret/data/user-service/jwt` → `JWT_SECRET`

## Database Schema

```sql
CREATE TABLE users (
  id            SERIAL PRIMARY KEY,
  email         VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  name          VARCHAR(255) NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ
);
```
