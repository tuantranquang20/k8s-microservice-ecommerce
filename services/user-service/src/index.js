// ============================================================
// src/index.js — user-service Entry Point
// ============================================================
// Responsibilities:
//   - Authentication (register, login, JWT issuance)
//   - User profile management (CRUD)
//   - /health endpoint for Kubernetes liveness/readiness probes
//   - /metrics endpoint for Prometheus scraping
//
// Tech: Node.js + Express + PostgreSQL (via pg pool)

require('dotenv').config(); // Load .env in development; in prod, env vars come from Vault

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const client = require('prom-client'); // Prometheus metrics

const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const { pool } = require('./db');

const app = express();
const PORT = process.env.PORT || 3000;

// ── Middleware ────────────────────────────────────────────────
// helmet: sets security-related HTTP headers (X-Frame-Options, CSP, etc.)
app.use(helmet());
// cors: allow requests from the api-gateway-bff and frontend
app.use(cors());
// morgan: HTTP access log (combined format = Apache-style logs)
app.use(morgan('combined'));
// Parse JSON request bodies
app.use(express.json());

// ── Prometheus Metrics ────────────────────────────────────────
// prom-client auto-collects: process CPU, memory, GC, event loop lag.
// We also add a custom HTTP request counter per route.
const register = new client.Registry();
client.collectDefaultMetrics({ register, prefix: 'user_service_' });

const httpRequestsTotal = new client.Counter({
    name: 'user_service_http_requests_total',
    help: 'Total number of HTTP requests',
    labelNames: ['method', 'route', 'status_code'],
    registers: [register],
});

// Middleware to record per-request metrics
app.use((req, res, next) => {
    res.on('finish', () => {
        httpRequestsTotal.inc({
            method: req.method,
            route: req.route?.path || req.path,
            status_code: res.statusCode,
        });
    });
    next();
});

// ── Health Endpoint ───────────────────────────────────────────
// Kubernetes calls /health for:
//   - Liveness probe  → restart the pod if it returns non-200
//   - Readiness probe → stop sending traffic if it returns non-200
//
// We check the DB connection here so K8s knows if the service is actually
// usable, not just that the process is alive.
app.get('/health', async (req, res) => {
    try {
        await pool.query('SELECT 1'); // cheap DB ping
        res.json({
            status: 'ok',
            service: 'user-service',
            timestamp: new Date().toISOString(),
            db: 'connected',
        });
    } catch (err) {
        // Return 503 — tells K8s readiness probe to stop routing traffic here
        res.status(503).json({
            status: 'error',
            service: 'user-service',
            db: 'disconnected',
            error: err.message,
        });
    }
});

// ── Metrics Endpoint ──────────────────────────────────────────
// Prometheus scrapes this on its schedule (default: every 15s).
// Grafana then visualises the time-series data.
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
});

// ── Routes ────────────────────────────────────────────────────
app.use('/auth', authRoutes);   // /auth/register, /auth/login
app.use('/users', userRoutes);  // /users/me, /users/:id

// ── DB Schema Init ────────────────────────────────────────────
// In production, use a migration tool (Flyway, golang-migrate, Prisma).
// For learning, we just create the table if it doesn't exist at startup.
async function initDB() {
    await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id            SERIAL PRIMARY KEY,
      email         VARCHAR(255) UNIQUE NOT NULL,
      password_hash VARCHAR(255) NOT NULL,
      name          VARCHAR(255) NOT NULL,
      created_at    TIMESTAMPTZ DEFAULT NOW(),
      updated_at    TIMESTAMPTZ
    );
    CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
  `);
    console.log('[db] Schema initialised');
}

// ── Start ─────────────────────────────────────────────────────
async function start() {
    try {
        await initDB();
        app.listen(PORT, '0.0.0.0', () => {
            console.log(`[user-service] Listening on port ${PORT} (${process.env.NODE_ENV || 'development'})`);
        });
    } catch (err) {
        console.error('[user-service] Failed to start:', err.message);
        process.exit(1);
    }
}

start();
