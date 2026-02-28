# ============================================================
# Dockerfile — product-service (Python + FastAPI)
# ============================================================
# Multi-stage build:
#   Stage 1 (builder) → install dependencies into a venv
#   Stage 2 (runtime) → copy the venv into a slim image
#
# WHY virtualenv in Docker? We could install globally, but copying
# a self-contained /venv directory between stages is clean and ensures
# the runtime image doesn't need pip or build tools.

# ── Stage 1: Builder ──────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /app

# Install build tools needed for some Python packages (e.g., cryptography)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Create a virtual environment to isolate dependencies
RUN python -m venv /venv
ENV PATH="/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Stage 2: Runtime ──────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Non-root user
RUN useradd --system --create-home appuser

WORKDIR /app

# Copy only the virtualenv (no pip, no gcc, no cache in final image)
COPY --from=builder /venv /venv
ENV PATH="/venv/bin:$PATH"

# Copy application source
COPY app/ ./app/

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# uvicorn: production-grade ASGI server
# --host 0.0.0.0 is required to accept traffic inside the container
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
