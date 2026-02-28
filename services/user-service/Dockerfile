# ============================================================
# Dockerfile — user-service (Node.js + Express)
# ============================================================
# Multi-stage build:
#   Stage 1 (deps)    → install only production dependencies
#   Stage 2 (runtime) → copy app code + node_modules into slim image
#
# WHY multi-stage: the 'node:20' image is ~1GB. By copying only
# what we need into 'node:20-alpine', the final image is ~80MB.
# Smaller images = faster pulls, smaller attack surface.

# ── Stage 1: Dependencies ─────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

# Copy package files first — Docker caches this layer.
# If only src/ changes, npm install is NOT re-run on rebuild.
COPY package*.json ./

# Install production dependencies only (no devDeps)
RUN npm ci --omit=dev && npm cache clean --force

# ── Stage 2: Runtime ──────────────────────────────────────────
FROM node:20-alpine AS runtime

# Run as non-root user — security best practice.
# If a vulnerability allows code execution, the attacker gets
# the 'node' user, not root.
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy installed modules from deps stage (not re-installing here)
COPY --from=deps /app/node_modules ./node_modules

# Copy application source
COPY src/ ./src/
COPY package.json ./

# Switch to non-root user
USER appuser

# Document the port this service listens on (informational only —
# actual port binding is set via env var or Kubernetes service)
EXPOSE 3000

# Health check — Docker will mark container as unhealthy if this fails.
# Kubernetes uses its own probes (defined in the Helm chart) but this
# is useful when running locally with docker-compose.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "src/index.js"]
