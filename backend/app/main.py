"""
FastAPI uygulama giriş noktası.
"""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.core.config import get_settings
from app.core.database import engine
from app.models import orm_models  # ORM tablolarını kaydet
from app.routers import admin, orders, recommendations, restaurants, users

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

settings = get_settings()


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

# ── CORS ──────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # Production'da iOS app domain ile sınırla
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Router'lar ────────────────────────────────────────────────────────────────
PREFIX = settings.api_prefix

app.include_router(restaurants.router, prefix=PREFIX)
app.include_router(orders.router, prefix=PREFIX)
app.include_router(users.router, prefix=PREFIX)
app.include_router(recommendations.router, prefix=PREFIX)
app.include_router(admin.router, prefix=PREFIX)


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
