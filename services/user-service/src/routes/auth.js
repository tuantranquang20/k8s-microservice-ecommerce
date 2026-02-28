// ============================================================
// src/routes/auth.js — Registration and Login Endpoints
// ============================================================

const router = require('express').Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { body, validationResult } = require('express-validator');
const { pool } = require('../db');

// ── POST /auth/register ───────────────────────────────────────
// Creates a new user. Passwords are hashed with bcrypt (cost factor 12).
// NEVER store plaintext passwords.
router.post(
    '/register',
    [
        body('email').isEmail().normalizeEmail(),
        body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 chars'),
        body('name').trim().notEmpty(),
    ],
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        const { email, password, name } = req.body;

        try {
            // Check for duplicate email before hashing (fast path)
            const existing = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
            if (existing.rows.length > 0) {
                return res.status(409).json({ error: 'Email already registered' });
            }

            // bcrypt cost 12 = ~250ms on a modern CPU — good security/UX balance
            const passwordHash = await bcrypt.hash(password, 12);

            const result = await pool.query(
                `INSERT INTO users (email, password_hash, name, created_at)
         VALUES ($1, $2, $3, NOW())
         RETURNING id, email, name, created_at`,
                [email, passwordHash, name]
            );

            const user = result.rows[0];
            const token = signToken(user.id, user.email);

            res.status(201).json({ user, token });
        } catch (err) {
            console.error('[auth/register]', err.message);
            res.status(500).json({ error: 'Internal server error' });
        }
    }
);

// ── POST /auth/login ──────────────────────────────────────────
router.post(
    '/login',
    [
        body('email').isEmail().normalizeEmail(),
        body('password').notEmpty(),
    ],
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        const { email, password } = req.body;

        try {
            const result = await pool.query(
                'SELECT id, email, name, password_hash FROM users WHERE email = $1',
                [email]
            );

            if (result.rows.length === 0) {
                // Return same error for wrong email OR wrong password to prevent user enumeration
                return res.status(401).json({ error: 'Invalid credentials' });
            }

            const user = result.rows[0];
            const valid = await bcrypt.compare(password, user.password_hash);

            if (!valid) {
                return res.status(401).json({ error: 'Invalid credentials' });
            }

            const token = signToken(user.id, user.email);

            // Don't return password_hash in the response
            const { password_hash, ...safeUser } = user;
            res.json({ user: safeUser, token });
        } catch (err) {
            console.error('[auth/login]', err.message);
            res.status(500).json({ error: 'Internal server error' });
        }
    }
);

// Helper: create a signed JWT
function signToken(userId, email) {
    return jwt.sign(
        { sub: userId, email },
        process.env.JWT_SECRET,
        { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );
}

module.exports = router;
