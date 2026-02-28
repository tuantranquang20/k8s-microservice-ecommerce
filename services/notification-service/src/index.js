// ============================================================
// src/index.js — notification-service Entry Point
// ============================================================
// WHY Node.js for this service?
//   - Event-driven I/O is perfect for "listen and react" patterns
//   - Redis subscriber connections are long-lived; Node's event loop
//     handles this with zero overhead (no threads needed)
//   - Fast to prototype notification logic (email, webhooks, SMS)
//
// Architecture:
//   - Two Redis connections: one SUBSCRIBER (receives messages),
//     one regular client (used by the health check to ping Redis)
//   - An Express server runs on the side for /health and /metrics
//     so Kubernetes can probe the service

require('dotenv').config();

const express = require('express');
const Redis = require('ioredis');
const client = require('prom-client');
const morgan = require('morgan');

const PORT = process.env.PORT || 3002;
const REDIS_URL = `redis://${process.env.REDIS_HOST || 'localhost'}:${process.env.REDIS_PORT || 6379}`;

// ── Prometheus Metrics ────────────────────────────────────────
const register = new client.Registry();
client.collectDefaultMetrics({ register, prefix: 'notification_service_' });

const notificationsProcessed = new client.Counter({
    name: 'notification_service_events_processed_total',
    help: 'Total order.created events processed',
    labelNames: ['status'], // 'success' | 'error'
    registers: [register],
});

// ── Redis Setup ───────────────────────────────────────────────
// IMPORTANT: Redis Pub/Sub requires a DEDICATED subscriber connection.
// A connection in subscriber mode can ONLY receive messages (no SET/GET).
// We use a separate 'healthClient' for the /health DB ping.

const subscriber = new Redis(REDIS_URL, {
    retryStrategy: (times) => Math.min(times * 100, 3000), // retry with backoff
});

const healthClient = new Redis(REDIS_URL, {
    retryStrategy: (times) => Math.min(times * 100, 3000),
});

subscriber.on('connect', () => console.log('[redis] Subscriber connected'));
subscriber.on('error', (err) => console.error('[redis] Subscriber error:', err.message));

// ── Subscribe to order.created channel ───────────────────────
// Published by order-service in Go (main.go publishOrderCreated())
subscriber.subscribe('order.created', (err, count) => {
    if (err) {
        console.error('[redis] Failed to subscribe:', err.message);
        return;
    }
    console.log(`[redis] Subscribed to ${count} channel(s)`);
});

subscriber.on('message', (channel, message) => {
    if (channel !== 'order.created') return;

    try {
        const event = JSON.parse(message);
        console.log(`[notification] Received order.created event:`, event);

        // ── Notification Logic ────────────────────────────────────
        // In a real system, this would call:
        //   - Email service (SendGrid, SES)
        //   - Push notification provider
        //   - Internal webhook
        // For learning, we just log the event.
        processOrderCreated(event);
        notificationsProcessed.inc({ status: 'success' });
    } catch (err) {
        console.error('[notification] Failed to process event:', err.message);
        notificationsProcessed.inc({ status: 'error' });
    }
});

function processOrderCreated(event) {
    // Simulated notification — replace with real email/SMS logic
    console.log(`
    ✅ [notification] Order #${event.order_id} placed
    User:     ${event.user_id}
    Product:  ${event.product_id}
    Total:    $${event.total_price}
    → Sending confirmation email to user ${event.user_id}...
  `.trim());
}

// ── HTTP Server (health + metrics) ────────────────────────────
const app = express();
app.use(morgan('combined'));

app.get('/health', async (req, res) => {
    try {
        await healthClient.ping();
        res.json({ status: 'ok', service: 'notification-service', redis: 'connected' });
    } catch (err) {
        res.status(503).json({ status: 'error', redis: err.message });
    }
});

app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`[notification-service] HTTP server on :${PORT}`);
});
