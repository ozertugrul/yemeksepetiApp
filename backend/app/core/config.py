from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # ── PostgreSQL (Supabase) ─────────────────────────────────────
    database_url: str  # postgresql+asyncpg://user:pass@host:5432/postgres

    # ── Firebase Admin SDK ────────────────────────────────────────
    # JSON içeriği (tek satır) ya da dosya yolu
    firebase_credentials_json: str = ""
    firebase_project_id: str = ""

    # ── Feature Flags ─────────────────────────────────────────────
    # 0 = Firestore-only (rollback), 1 = SQL read/write aktif
    use_sql_backend: bool = True
    # 0 = embedding üretme, 1 = embed + pgvector öneri aktif
    use_embeddings: bool = True

    # ── Embedding ─────────────────────────────────────────────────
    embedding_model: str = "sentence-transformers/all-MiniLM-L6-v2"
    embedding_dim: int = 384

    # ── API ───────────────────────────────────────────────────────
    api_prefix: str = "/api/v1"
    debug: bool = False


@lru_cache
def get_settings() -> Settings:
    return Settings()
