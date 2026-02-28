# ============================================================
# Dockerfile — payment-service (Rust + Actix-web)
# ============================================================
# Rust multi-stage build:
#   Stage 1 (builder) → cargo build --release (takes 5-10 min first time,
#                        then cached via layer caching tricks)
#   Stage 2 (runtime) → distroless/static — ~20MB final image
#
# CACHING TIP: Copy only Cargo.toml/Cargo.lock first, create a dummy
# src/main.rs, build dependencies (cached), then overwrite with real source.
# This avoids full recompile when only src/ changes.

# ── Stage 1: Dependency Cache Layer ───────────────────────────
FROM rust:1.78-slim AS chef
WORKDIR /app
# Install cargo-chef to cache dependency compilation
RUN cargo install cargo-chef --locked
COPY Cargo.toml Cargo.lock* ./
RUN cargo chef prepare --recipe-path recipe.json

FROM rust:1.78-slim AS planner
WORKDIR /app
RUN cargo install cargo-chef --locked
COPY --from=chef /app/recipe.json recipe.json
# This step only re-runs when dependencies (Cargo.toml/lock) change
RUN cargo chef cook --release --recipe-path recipe.json

# ── Stage 2: Builder ──────────────────────────────────────────
FROM rust:1.78-slim AS builder
WORKDIR /app
# Copy cached dependencies from planner stage
COPY --from=planner /app /app
# Now copy real source — only this step re-runs on code changes
COPY src/ ./src/
RUN cargo build --release --bin payment-service

# ── Stage 3: Runtime ──────────────────────────────────────────
FROM gcr.io/distroless/static:nonroot AS runtime
WORKDIR /app
COPY --from=builder /app/target/release/payment-service .

USER nonroot:nonroot
EXPOSE 8090

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["/app/payment-service", "--health-check"]

ENTRYPOINT ["/app/payment-service"]
