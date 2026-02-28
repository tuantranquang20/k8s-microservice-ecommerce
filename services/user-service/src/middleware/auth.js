// ============================================================
// src/middleware/auth.js — JWT Authentication Middleware
// ============================================================
// Verifies Bearer tokens on protected routes.
// Usage: router.get('/profile', authMiddleware, handler)

const jwt = require('jsonwebtoken');

function authMiddleware(req, res, next) {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Missing or malformed Authorization header' });
    }

    const token = authHeader.split(' ')[1];

    try {
        // jwt.verify throws on expiry, invalid signature, or malformed token
        const payload = jwt.verify(token, process.env.JWT_SECRET);
        req.user = payload; // attach decoded payload to request for downstream handlers
        next();
    } catch (err) {
        return res.status(401).json({ error: 'Invalid or expired token' });
    }
}

module.exports = { authMiddleware };
