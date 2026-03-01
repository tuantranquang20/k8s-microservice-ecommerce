# ============================================================
# Dockerfile — payment-service (Rust + Actix-web)
# ============================================================

# ── Stage 1: cargo-chef installer (base dùng chung) ──────────
FROM rust:1.88-slim AS chef
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN cargo install cargo-chef --locked

# ── Stage 2: Planner — phân tích dependency graph ────────────
FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# ── Stage 3: Builder — build deps trước, sau đó build app ────
FROM chef AS builder
# Bước này chỉ re-run khi Cargo.toml/Cargo.lock thay đổi
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json

# Bước này re-run khi src/ thay đổi (deps đã được cache ở trên)
COPY . .
RUN cargo build --release --bin payment-service

# ── Stage 4: Runtime ─────────────────────────────────────────
# Dùng debian-slim thay distroless/static vì actix-web cần
# dynamic linking (libssl, libc, libgcc...)
FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y \
    libssl3 \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/payment-service .

RUN useradd -r -s /bin/false nonroot
USER nonroot:nonroot

EXPOSE 8090

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:8090/health || exit 1

ENTRYPOINT ["/app/payment-service"]
