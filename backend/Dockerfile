FROM python:3.11-slim

# Sistem bağımlılıkları
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc build-essential curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# torch CPU-only wheel kaynağını ekle, sonra diğer bağımlılıkları yükle
COPY requirements.txt .
RUN pip install --no-cache-dir \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    -r requirements.txt

# Uygulama kodunu kopyala
COPY . .

# NOT: Model, ilk istekte lazy-load edilir (build süresini kısaltır)
# İstersen manuel indir: HF_HOME=/app/.cache python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')"

EXPOSE 8000

# Koyeb/Render $PORT env var'ını kullan, yoksa 8000 default
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
