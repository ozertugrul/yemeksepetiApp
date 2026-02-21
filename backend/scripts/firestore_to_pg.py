"""
Firestore → PostgreSQL veri migration scripti.

Çalıştırmadan önce:
  1. .env dosyasını doldur (DATABASE_URL + FIREBASE_CREDENTIALS_JSON)
  2. SQL şemasını Supabase'e uygula (migrations/001_initial_schema.sql)
  3. python -m scripts.firestore_to_pg

Idempotent: mevcut kayıtlar güncellenir, yeni olanlar eklenir.
"""
import asyncio
import json
import logging
import os
import sys
from pathlib import Path

# Proje kökünü path'e ekle
sys.path.insert(0, str(Path(__file__).parent.parent))

import firebase_admin
from firebase_admin import credentials, firestore as fs
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


# ── Firebase başlat ───────────────────────────────────────────────────────────
def init_firebase():
    cred_json = os.getenv("FIREBASE_CREDENTIALS_JSON", "")
    if cred_json:
        cred = credentials.Certificate(json.loads(cred_json))
    else:
        cred = credentials.ApplicationDefault()
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(cred)
    return fs.client()


# ── PostgreSQL bağlantısı ─────────────────────────────────────────────────────
async def get_pg_session():
    from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        raise ValueError("DATABASE_URL env var eksik")
    engine = create_async_engine(db_url, echo=False)
    factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    return engine, factory


# ── Yardımcı dönüşümler ───────────────────────────────────────────────────────
def _safe_float(v, default=0.0) -> float:
    try:
        return float(v) if v is not None else default
    except (TypeError, ValueError):
        return default


def _safe_bool(v, default=False) -> bool:
    return bool(v) if v is not None else default


def _safe_str(v, default="") -> str:
    return str(v) if v is not None else default


# ── Migrate: Restaurants + MenuItems ─────────────────────────────────────────
async def migrate_restaurants(db_client, session_factory):
    from app.repositories.sql_repos import SQLMenuItemRepository, SQLRestaurantRepository
    import uuid

    logger.info("Restoranlar migrate ediliyor…")
    docs = db_client.collection("restaurants").stream()

    async with session_factory() as session:
        r_repo = SQLRestaurantRepository(session)
        m_repo = SQLMenuItemRepository(session)
        count = 0

        for doc in docs:
            data = doc.to_dict()
            restaurant_id = doc.id

            r_data = {
                "id": restaurant_id,
                "owner_id": data.get("ownerId"),
                "name": _safe_str(data.get("name"), "İsimsiz Restoran"),
                "description": _safe_str(data.get("description")),
                "cuisine_type": _safe_str(data.get("cuisineType")),
                "image_url": data.get("imageUrl"),
                "rating": _safe_float(data.get("rating")),
                "delivery_time": _safe_str(data.get("deliveryTime")),
                "min_order_amount": _safe_float(data.get("minOrderAmount")),
                "is_active": _safe_bool(data.get("isActive"), True),
                "city": data.get("city"),
                "allows_pickup": _safe_bool(data.get("allowsPickup")),
                "allows_cash_on_del": _safe_bool(data.get("allowsCashOnDelivery")),
                "successful_order_count": int(data.get("successfulOrderCount", 0)),
                "average_rating": _safe_float(data.get("averageRating")),
                "rating_count": int(data.get("ratingCount", 0)),
            }
            await r_repo.create(r_data)

            # Menü öğeleri — Firestore'da restaurant.menu array'i
            for item in (data.get("menu") or []):
                item_data = {
                    "id": item.get("id") or str(uuid.uuid4()),
                    "restaurant_id": restaurant_id,
                    "name": _safe_str(item.get("name")),
                    "description": _safe_str(item.get("description")),
                    "price": _safe_float(item.get("price")),
                    "image_url": item.get("imageUrl"),
                    "category": _safe_str(item.get("category"), "Diğer"),
                    "discount_percent": _safe_float(item.get("discountPercent")),
                    "is_available": _safe_bool(item.get("isAvailable"), True),
                    "option_groups": item.get("optionGroups") or [],
                    "suggested_ids": item.get("suggestedItemIds") or [],
                }
                await m_repo.upsert(item_data)

            count += 1
            if count % 10 == 0:
                logger.info(f"  {count} restoran işlendi…")
                await session.commit()

        await session.commit()
    logger.info(f"Restaurants migrate tamamlandı: {count} restoran.")


# ── Migrate: Users ────────────────────────────────────────────────────────────
async def migrate_users(db_client, session_factory):
    from app.repositories.sql_repos import SQLUserRepository

    logger.info("Kullanıcılar migrate ediliyor…")
    docs = db_client.collection("users").stream()

    async with session_factory() as session:
        repo = SQLUserRepository(session)
        count = 0
        for doc in docs:
            data = doc.to_dict()
            u_data = {
                "id": doc.id,
                "email": _safe_str(data.get("email")),
                "display_name": data.get("displayName") or data.get("email", "")[:20],
                "role": _safe_str(data.get("role"), "user"),
                "city": data.get("city"),
                "phone": data.get("phone"),
                "managed_restaurant_id": data.get("managedRestaurantId"),
            }
            await repo.upsert(u_data)
            count += 1
            if count % 50 == 0:
                await session.commit()
        await session.commit()
    logger.info(f"Users migrate tamamlandı: {count} kullanıcı.")


# ── Migrate: Orders ───────────────────────────────────────────────────────────
async def migrate_orders(db_client, session_factory):
    from app.repositories.sql_repos import SQLOrderRepository

    logger.info("Siparişler migrate ediliyor…")
    docs = db_client.collection("orders").stream()

    async with session_factory() as session:
        repo = SQLOrderRepository(session)
        count = 0
        for doc in docs:
            data = doc.to_dict()
            o_data = {
                "id": doc.id,
                "user_id": _safe_str(data.get("userId")),
                "restaurant_id": _safe_str(data.get("restaurantId")),
                "status": _safe_str(data.get("status"), "completed"),
                "payment_method": _safe_str(data.get("paymentMethod"), "cashOnDelivery"),
                "delivery_address": data.get("deliveryAddress"),
                "items": data.get("items") or [],
                "subtotal": _safe_float(data.get("subtotal")),
                "delivery_fee": _safe_float(data.get("deliveryFee")),
                "discount_amount": _safe_float(data.get("discountAmount")),
                "total_amount": _safe_float(data.get("totalAmount")),
                "coupon_code": data.get("couponCode"),
                "notes": data.get("notes"),
                "is_rated": _safe_bool(data.get("isRated")),
            }
            await repo.create(o_data)
            count += 1
            if count % 50 == 0:
                await session.commit()
        await session.commit()
    logger.info(f"Orders migrate tamamlandı: {count} sipariş.")


# ── Embedding üret (migration sonrası) ────────────────────────────────────────
async def generate_all_embeddings(session_factory):
    from app.repositories.sql_repos import SQLMenuItemRepository
    from app.services.embedding_service import EmbeddingService

    logger.info("Menü öğeleri için embedding üretiliyor…")
    emb = EmbeddingService()
    if not emb._enabled:
        logger.warning("USE_EMBEDDINGS=false — embedding atlandı.")
        return

    async with session_factory() as session:
        from sqlalchemy import select, text
        from app.models.orm_models import MenuItemORM
        from sqlalchemy.ext.asyncio import AsyncSession

        result = await session.execute(
            select(MenuItemORM).where(MenuItemORM.embedding.is_(None))
        )
        items = result.scalars().all()
        logger.info(f"Embedding bekleyen {len(items)} öğe bulundu.")

        BATCH = 64
        for i in range(0, len(items), BATCH):
            batch = items[i:i + BATCH]
            texts = [
                EmbeddingService.menu_item_text(it.name, it.description or "", it.category or "")
                for it in batch
            ]
            vecs = emb.embed_batch(texts)
            repo = SQLMenuItemRepository(session)
            for it, vec in zip(batch, vecs):
                if vec:
                    await repo.update_embedding(it.id, vec)
            await session.commit()
            logger.info(f"  {min(i + BATCH, len(items))}/{len(items)} embedding tamamlandı")

    logger.info("Embedding üretimi tamamlandı.")


# ── Ana akış ──────────────────────────────────────────────────────────────────
async def main():
    db_client = init_firebase()
    engine, session_factory = await get_pg_session()

    try:
        await migrate_restaurants(db_client, session_factory)
        await migrate_users(db_client, session_factory)
        await migrate_orders(db_client, session_factory)
        await generate_all_embeddings(session_factory)
        logger.info("\n✅ Migration tamamlandı.")
    finally:
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
