from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import NullPool
from uuid import uuid4

from app.core.config import get_settings

settings = get_settings()


def _with_pg_bouncer_params(raw_url: str) -> str:
    """
    SQLAlchemy asyncpg dialect için PgBouncer-safe query param'ları ekle.

    - prepared_statement_cache_size=0: SQLAlchemy asyncpg prepared statement cache'i kapat
    - statement_cache_size=0: asyncpg statement cache'i kapat
    """
    separator = "&" if "?" in raw_url else "?"
    url = raw_url
    if "prepared_statement_cache_size=" not in url:
        url = f"{url}{separator}prepared_statement_cache_size=0"
        separator = "&"
    if "statement_cache_size=" not in url:
        url = f"{url}{separator}statement_cache_size=0"
    return url

# NullPool: PgBouncer transaction-mode kesin çözüm.
#
# Sorun: SQLAlchemy kendi iç sorgusu olan `select pg_catalog.version()`
# için bile asyncpg'de prepared statement oluşturuyor. PgBouncer
# transaction-mode'da PREPARE/EXECUTE/DEALLOCATE farklı backend
# bağlantılarına düşebilir → DuplicatePreparedStatementError.
#
# statement_cache_size=0 URL parametresi ve connect_args yöntemi
# SQLAlchemy'nin pool katmanının ilk bağlantı kurulum aşamasında
# dialect.initialize() çalışmadan önce devreye giremiyor.
#
# NullPool ile:
# - Her request için yeni bağlantı kurulur, bitince kapatılır.
# - Bağlantı hiç yeniden kullanılmaz → prepared statement çakışması imkânsız.
# - PgBouncer transaction-mod zaten kısa ömürlü bağlantı için tasarlanmıştır.
# - Koyeb / Supabase ortamında performance maliyeti ihmal edilebilir.
engine = create_async_engine(
    _with_pg_bouncer_params(settings.database_url),
    poolclass=NullPool,
    connect_args={
        "timeout": 15,
        "command_timeout": 30,
        "statement_cache_size": 0,
        "prepared_statement_name_func": lambda: f"__asyncpg_{uuid4()}__",
    },
    echo=settings.debug,
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
