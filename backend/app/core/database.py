import asyncio
from uuid import uuid4

import asyncpg
from fastapi import HTTPException, status
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import NullPool

from app.core.config import get_settings

settings = get_settings()


def _is_transient_db_error(exc: Exception) -> bool:
    if isinstance(
        exc,
        (
            TimeoutError,
            ConnectionError,
            asyncpg.exceptions.ConnectionDoesNotExistError,
            asyncpg.exceptions.ConnectionFailureError,
            asyncpg.exceptions.CannotConnectNowError,
            asyncpg.exceptions.InterfaceError,
        ),
    ):
        return True
    msg = str(exc).lower()
    return "connection was closed" in msg or "connection reset" in msg


class ResilientAsyncSession(AsyncSession):
    async def execute(self, *args, **kwargs):
        try:
            return await super().execute(*args, **kwargs)
        except Exception as exc:
            if not _is_transient_db_error(exc):
                raise
            await asyncio.sleep(0.15)
            return await super().execute(*args, **kwargs)


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
    class_=ResilientAsyncSession,
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
        except (TimeoutError, asyncpg.PostgresError, SQLAlchemyError):
            await session.rollback()
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Veritabanı geçici olarak kullanılamıyor. Lütfen tekrar deneyin.",
            )
        except Exception:
            await session.rollback()
            raise
