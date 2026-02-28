// ============================================================
// src/db.js — PostgreSQL Connection Pool
// ============================================================
// WHY a connection pool? Opening a new TCP connection per request
// is expensive (~50-100ms). A pool keeps N connections alive and
// reuses them. pg's Pool automatically handles reconnection.

const { Pool } = require('pg');

// Pool config comes entirely from environment variables — no hardcoded values.
// In production these are injected by Vault Agent sidecar.
const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'users',
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || '',
  // Keep up to 10 clients in the pool; excess requests queue up
  max:      10,
  // Release idle clients after 30s to prevent stale connections
  idleTimeoutMillis: 30000,
  // Fail fast if a connection takes > 2s (DB is down)
  connectionTimeoutMillis: 2000,
});

// Log pool errors — these surface issues like the DB being unreachable
pool.on('error', (err) => {
  console.error('[db] Unexpected pool error:', err.message);
});

module.exports = { pool };
