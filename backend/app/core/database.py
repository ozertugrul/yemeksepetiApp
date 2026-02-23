from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import NullPool

from app.core.config import get_settings

settings = get_settings()

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
    settings.database_url,
    poolclass=NullPool,
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
