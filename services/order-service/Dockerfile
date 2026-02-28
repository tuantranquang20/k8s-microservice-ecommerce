# ============================================================
# Dockerfile — order-service (Go + Gin)
# ============================================================
# Multi-stage build:
#   Stage 1 (builder) → compile the Go binary inside the full Go image
#   Stage 2 (runtime) → copy the static binary into a zero-dependency image
#
# WHY scratch? A Go binary is self-contained (no libc, no runtime).
# The final image is ~15MB — about the smallest possible Docker image.
# NOTE: scratch has no shell, so debugging requires adding busybox
# or using 'kubectl exec' with ephemeral debug containers.

# ── Stage 1: Builder ──────────────────────────────────────────
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Download dependencies first (cached layer if go.mod/go.sum unchanged)
COPY go.mod go.sum* ./
RUN go mod download

# Copy source and build
COPY . .

# CGO_ENABLED=0 — produces a fully static binary (no shared libs)
# GOOS=linux     — cross-compile for the target OS if building on macOS
RUN CGO_ENABLED=0 GOOS=linux go build -a -ldflags="-s -w" -o order-service .
#   -s     strip symbol table (smaller binary)
#   -w     strip DWARF debug info (smaller binary)

# ── Stage 2: Runtime ──────────────────────────────────────────
# Use distroless/static instead of scratch for CA certs (needed for HTTPS calls)
FROM gcr.io/distroless/static:nonroot AS runtime

WORKDIR /app
COPY --from=builder /app/order-service .

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/app/order-service", "-healthcheck"]

# distroless images use uid 65532 (nonroot) by default
USER nonroot:nonroot

ENTRYPOINT ["/app/order-service"]
