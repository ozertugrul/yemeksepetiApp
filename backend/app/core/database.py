from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.core.config import get_settings

settings = get_settings()


def _make_engine_url(raw_url: str) -> str:
    """
    PgBouncer transaction-mode uyumluluğu için asyncpg'ye
    statement_cache_size=0 URL parametresi olarak ilet.

    Neden URL parametresi?
    connect_args ile geçince SQLAlchemy bazen asyncpg pool'a aktarmıyor.
    asyncpg URL query params'ı her zaman doğrudan asyncpg.connect()'e geçirir.
    """
    separator = "&" if "?" in raw_url else "?"
    if "statement_cache_size" not in raw_url:
        raw_url = f"{raw_url}{separator}statement_cache_size=0"
    return raw_url


engine = create_async_engine(
    _make_engine_url(settings.database_url),
    # pool_size / max_overflow: Supabase connection limit'i aşmamak için sınırlı tut
    pool_size=5,
    max_overflow=10,
    pool_pre_ping=True,
    pool_recycle=300,           # Supabase idle-timeout önlemi
    pool_reset_on_return=True,  # Bağlantı havuza dönerken temizle
    echo=settings.debug,
    # connect_args: asyncpg.connect() doğrudan parametreleri (ikinci güvence)
    connect_args={"statement_cache_size": 0},
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    """SQLAlchemy declarative base — tüm ORM modelleri buradan türer."""
    pass


async def get_db() -> AsyncSession:
    """FastAPI Depends ile kullanılan session factory."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
