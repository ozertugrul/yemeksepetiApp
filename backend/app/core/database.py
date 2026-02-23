from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.core.config import get_settings

settings = get_settings()

engine = create_async_engine(
    settings.database_url,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
    pool_recycle=300,          # Supabase idle timeout önlemi
    echo=settings.debug,
    # Supabase/PgBouncer transaction-mode: prepared statement cache KAPALI
    # 'statement_cache_size' asyncpg'nin doğal parametresi (0 = cache yok)
    # 'prepared_statement_cache_size' ise asyncpg bilmez → KALDIRILDI
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
