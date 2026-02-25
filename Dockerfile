FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    USE_EMBEDDINGS=false \
    UVICORN_WORKERS=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backend/requirements.txt backend/requirements.core.txt backend/requirements.embeddings.txt ./

ARG ENABLE_EMBEDDINGS=false

RUN pip install --no-cache-dir -r requirements.core.txt \
    && if [ "$ENABLE_EMBEDDINGS" = "true" ]; then \
         pip install --no-cache-dir --extra-index-url https://download.pytorch.org/whl/cpu -r requirements.embeddings.txt; \
       fi

COPY backend/ ./

EXPOSE 8000

CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers ${UVICORN_WORKERS:-1} --loop asyncio --http h11 --proxy-headers"]
