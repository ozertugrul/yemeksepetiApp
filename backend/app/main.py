"""
FastAPI uygulama giriş noktası.
"""
import logging
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.requests import Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import get_settings
from app.core.database import engine
from app.models import orm_models  # ORM tablolarını kaydet
from app.routers import admin, auth, coupons, orders, recommendations, restaurants, search, users

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

settings = get_settings()


def _parse_cors_origins(raw: str) -> list[str]:
    origins = [origin.strip() for origin in (raw or "").split(",") if origin.strip()]
    return origins


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup / shutdown hook."""
    logger.info("Uygulama başlatılıyor…")
    logger.info(f"SQL backend: {'AKTIF' if settings.use_sql_backend else 'DEVRE DIŞI'}")
    logger.info(f"Embedding: {'AKTIF' if settings.use_embeddings else 'DEVRE DIŞI'}")
    yield
    logger.info("Uygulama kapatılıyor…")
    await engine.dispose()


app = FastAPI(
    title="YemeksepetiApp API",
    version="1.0.0",
    description="iOS yemek sipariş uygulaması backend — PostgreSQL + pgvector",
    lifespan=lifespan,
)


@app.exception_handler(TimeoutError)
async def timeout_exception_handler(_request: Request, _exc: TimeoutError):
    return JSONResponse(
        status_code=503,
        content={"detail": "Servis geçici olarak meşgul. Lütfen tekrar deneyin."},
    )


@app.exception_handler(SQLAlchemyError)
async def sqlalchemy_exception_handler(_request: Request, _exc: SQLAlchemyError):
    return JSONResponse(
        status_code=503,
        content={"detail": "Veritabanı geçici olarak kullanılamıyor. Lütfen tekrar deneyin."},
    )


@app.exception_handler(asyncpg.PostgresError)
async def asyncpg_exception_handler(_request: Request, _exc: asyncpg.PostgresError):
    return JSONResponse(
        status_code=503,
        content={"detail": "Veritabanı bağlantısı kesildi. Lütfen tekrar deneyin."},
    )

# ── CORS ──────────────────────────────────────────────────────────────────────
allowed_origins = _parse_cors_origins(settings.cors_allow_origins)
allow_credentials = "*" not in allowed_origins

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Router'lar ────────────────────────────────────────────────────────────────
PREFIX = settings.api_prefix

app.include_router(restaurants.router, prefix=PREFIX)
app.include_router(coupons.router, prefix=PREFIX)
app.include_router(orders.router, prefix=PREFIX)
app.include_router(users.router, prefix=PREFIX)
app.include_router(auth.router, prefix=PREFIX)
app.include_router(recommendations.router, prefix=PREFIX)
app.include_router(admin.router, prefix=PREFIX)
app.include_router(search.router, prefix=PREFIX)


# ── Health check ──────────────────────────────────────────────────────────────
@app.get("/health", tags=["System"])
async def health():
    return {
        "status": "ok",
        "sql_backend": settings.use_sql_backend,
        "embeddings": settings.use_embeddings,
    }


@app.get("/", include_in_schema=False)
async def root():
    return JSONResponse({"message": "YemeksepetiApp API — /docs"})
