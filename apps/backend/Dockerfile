FROM python:3.13-slim as builder

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /app/wheels -r requirements.txt

FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/wheels /wheels
COPY --from=builder /app/requirements.txt .
RUN pip install --no-cache /wheels/*

COPY . .

# Create a non-root user
RUN addgroup --system appgroup && adduser --system --group appuser \
    && chown -R appuser:appgroup /app \
    && mkdir -p /var/lib/bhub/media \
    && chown -R appuser:appgroup /var/lib/bhub/media

# The media directory is created and owned HERE, before the volume is
# mounted over it. Docker copies an image directory's ownership into a NEW
# named volume on first use; a volume that appears unannounced belongs to
# root, which this container is not.
#
# Without it the store is unwritable, and both halves fail quietly: every
# photo save falls back to keeping the picture in the database row, and the
# migration that moves them out fails a row at a time with
# "Permission denied".
USER appuser

EXPOSE 8000

CMD ["gunicorn", "config.wsgi:application", "-c", "gunicorn.conf.py"]
