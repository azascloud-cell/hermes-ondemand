# Hermes Agent Railway Deployment
# Multi-stage build for optimal size and caching

# Stage 1: Build dependencies
FROM python:3.12-slim AS builder

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

# Set up Python environment
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Stage 2: Runtime
FROM python:3.12-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    libsqlite3-0 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create hermes user
RUN useradd -m -s /bin/bash -u 1000 hermes

WORKDIR /home/hermes

# Copy uv from builder
COPY --from=builder /bin/uv /usr/local/bin/uv

# Switch to hermes user
USER hermes

# Set up paths
ENV PATH="/home/hermes/.local/bin:/home/hermes/.hermes/bin:${PATH}"
ENV HOME="/home/hermes"

# Install Hermes Agent
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup --skip-browser --skip-computer-use

# Pin python-telegram-bot version (fixes "Any cannot be instantiated" error)
ENV UV="/home/hermes/.hermes/bin/uv"
ENV VENV_PY="/home/hermes/.hermes/hermes-agent/venv/bin/python"
RUN if [ -x "$UV" ] && [ -x "$VENV_PY" ]; then \
    "$UV" pip install --python "$VENV_PY" --reinstall "python-telegram-bot[webhooks]==22.6"; \
    fi

# Create directories
RUN mkdir -p /home/hermes/.hermes /home/hermes/scripts

# Copy scripts and patch script
COPY --chown=hermes:hermes scripts/ /home/hermes/scripts/
COPY --chown=hermes:hermes listener/ /home/hermes/listener/
COPY --chown=hermes:hermes scripts/patch-typehandler.py /home/hermes/scripts/patch-typehandler.py

# Make scripts executable
RUN chmod +x /home/hermes/scripts/*.sh

# Run patching script
RUN python3 /home/hermes/scripts/patch-typehandler.py

# Install listener dependencies
RUN pip install --no-cache-dir -r /home/hermes/listener/requirements.txt 2>/dev/null || pip install --no-cache-dir requests

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f "hermes gateway" > /dev/null || exit 1

# Entry point
ENTRYPOINT ["/home/hermes/scripts/railway-entrypoint.sh"]