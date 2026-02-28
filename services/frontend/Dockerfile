# ============================================================
# Dockerfile — frontend (Vanilla HTML/JS → Nginx)
# ============================================================
# Multi-stage build:
#   Stage 1 (node) → could run build tools (e.g. vite, webpack)
#                    For a vanilla HTML app we skip the build step
#                    but keep the pattern for future React/Vite migration
#   Stage 2 (nginx) → serve static files from Alpine Nginx (~25MB)
#
# Nginx serves the SPA and proxies /api/* to the api-gateway-bff.
# The proxy config is in nginx.conf.

# ── Stage 1: (reserved for build tools) ───────────────────────
FROM node:20-alpine AS builder
WORKDIR /app
# If you add a package.json + vite/webpack, install and build here:
# COPY package*.json ./
# RUN npm ci
# COPY . .
# RUN npm run build
# For now just copy static files through
COPY public/ ./dist/

# ── Stage 2: Nginx ────────────────────────────────────────────
FROM nginx:1.27-alpine AS runtime

# Remove default Nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Our custom config: serve SPA, proxy /api to BFF
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy static files from builder
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
