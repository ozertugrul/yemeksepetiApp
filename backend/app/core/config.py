from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # ── PostgreSQL (Local Docker) ─────────────────────────────────
    database_url: str = ""  # postgresql+asyncpg://user:pass@host:5432/postgres

    # ── Auth (JWT) ────────────────────────────────────────────────
    jwt_secret_key: str = ""
    jwt_secret: str = ""
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7
    anon_key: str = ""
    service_role_key: str = ""

    # ── Feature Flags ─────────────────────────────────────────────
    # 0 = Firestore-only (rollback), 1 = SQL read/write aktif
    use_sql_backend: bool = True
    # 0 = embedding üretme, 1 = embed + pgvector öneri aktif
    use_embeddings: bool = False

    # ── Embedding ─────────────────────────────────────────────────
    embedding_model: str = "ozertuu/yemeksepeti-MiniLM-L12-v2"
    embedding_dim: int = 384
    embedding_batch_size: int = 16
    embedding_max_seq_length: int = 256

    # ── Collaborative Filtering ───────────────────────────────────
    cf_lookback_days: int = 90           # kaç günlük sipariş verisini kullan
    cf_min_similarity: float = 0.05      # minimum cosine benzerlik eşiği
    cf_max_similar_users: int = 30       # en fazla kaç benzer kullanıcı
    cf_cache_ttl_minutes: int = 15       # öneri cache TTL (dakika)
    cf_embedding_alpha: float = 0.3      # 0=sadece CF, 1=sadece embedding, 0.3=blend

    # ── API ───────────────────────────────────────────────────────
    api_prefix: str = "/api/v1"
    cors_allow_origins: str = "http://localhost:3000,http://127.0.0.1:3000,http://localhost:5173,http://127.0.0.1:5173"
    debug: bool = False

    # ── HTTP Üzerinde Ek Güvenlik Katmanı ───────────────────────
    enforce_signed_requests: bool = True
    request_signature_max_skew_seconds: int = 45
    request_nonce_ttl_seconds: int = 120


@lru_cache
def get_settings() -> Settings:
    return Settings()
