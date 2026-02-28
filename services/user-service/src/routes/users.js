// ============================================================
// src/routes/users.js — User Profile Endpoints (protected)
// ============================================================

const router = require('express').Router();
const { pool } = require('../db');
const { authMiddleware } = require('../middleware/auth');

// ── GET /users/me ─────────────────────────────────────────────
// Returns the current user's profile (requires valid JWT)
router.get('/me', authMiddleware, async (req, res) => {
    try {
        const result = await pool.query(
            'SELECT id, email, name, created_at FROM users WHERE id = $1',
            [req.user.sub]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }

        res.json(result.rows[0]);
    } catch (err) {
        console.error('[users/me]', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── GET /users/:id ────────────────────────────────────────────
// Internal service-to-service endpoint — order-service calls this
// to verify a user exists before creating an order.
router.get('/:id', authMiddleware, async (req, res) => {
    const userId = parseInt(req.params.id, 10);
    if (isNaN(userId)) {
        return res.status(400).json({ error: 'Invalid user ID' });
    }

    try {
        const result = await pool.query(
            'SELECT id, email, name, created_at FROM users WHERE id = $1',
            [userId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }

        res.json(result.rows[0]);
    } catch (err) {
        console.error('[users/:id]', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// ── PUT /users/me ─────────────────────────────────────────────
// Update own profile (name only — email changes require re-verification in prod)
router.put('/me', authMiddleware, async (req, res) => {
    const { name } = req.body;
    if (!name || typeof name !== 'string' || name.trim().length === 0) {
        return res.status(400).json({ error: 'Name is required' });
    }

    try {
        const result = await pool.query(
            `UPDATE users SET name = $1, updated_at = NOW()
       WHERE id = $2
       RETURNING id, email, name, created_at, updated_at`,
            [name.trim(), req.user.sub]
        );

        res.json(result.rows[0]);
    } catch (err) {
        console.error('[users/me PUT]', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

module.exports = router;
