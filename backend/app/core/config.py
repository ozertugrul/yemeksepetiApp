from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # ── PostgreSQL (Supabase) ─────────────────────────────────────
    database_url: str  # postgresql+asyncpg://user:pass@host:5432/postgres

    # ── JWT Auth ──────────────────────────────────────────────────
    jwt_secret: str = "change-me-in-production-use-a-long-random-string"
    jwt_expire_days: int = 30

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
    debug: bool = False


@lru_cache
def get_settings() -> Settings:
    return Settings()
