FROM python:3.11-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.core.txt requirements.embeddings.txt ./

ARG ENABLE_EMBEDDINGS=false

RUN python -m pip wheel --wheel-dir /wheels -r requirements.core.txt \
    && if [ "$ENABLE_EMBEDDINGS" = "true" ]; then \
         python -m pip wheel --wheel-dir /wheels \
         --extra-index-url https://download.pytorch.org/whl/cpu \
         -r requirements.embeddings.txt; \
       fi


FROM python:3.11-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONMALLOC=malloc \
    MALLOC_ARENA_MAX=2 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UVICORN_WORKERS=1 \
    USE_EMBEDDINGS=false

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.core.txt requirements.embeddings.txt ./
COPY --from=builder /wheels /wheels

ARG ENABLE_EMBEDDINGS=false

RUN python -m pip install --no-index --find-links=/wheels -r requirements.core.txt \
    && if [ "$ENABLE_EMBEDDINGS" = "true" ]; then \
         python -m pip install --no-index --find-links=/wheels -r requirements.embeddings.txt; \
       fi \
    && rm -rf /wheels

COPY app ./app
COPY migrations ./migrations

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",\"8000\")}/health', timeout=4)" || exit 1

CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers ${UVICORN_WORKERS:-1} --loop asyncio --http h11 --proxy-headers"]
