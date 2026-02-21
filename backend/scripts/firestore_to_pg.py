"""
Firestore → PostgreSQL veri migration scripti.

Çalıştırmadan önce:
  1. .env dosyasını doldur (DATABASE_URL + FIREBASE_CREDENTIALS_JSON)
  2. SQL şemasını Supabase'e uygula (migrations/001_initial_schema.sql)
  3. python -m scripts.firestore_to_pg

Her çalıştırmada tabloları temizleyip yeniden doldurur (deneysel veri — kayıp önemli değil).
"""
import asyncio
import json
import logging
import os
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import asyncpg
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


# ── asyncpg bağlantısı ────────────────────────────────────────────────────────
async def get_conn() -> asyncpg.Connection:
    url = os.getenv("DATABASE_URL", "").replace("postgresql+asyncpg://", "postgresql://")
    if not url:
        raise ValueError("DATABASE_URL env var eksik")
    return await asyncpg.connect(url, statement_cache_size=0)


# ── SQLAlchemy session (sadece embedding için) ────────────────────────────────
async def get_pg_session():
    from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        raise ValueError("DATABASE_URL env var eksik")
    engine = create_async_engine(
        db_url,
        echo=False,
        connect_args={"statement_cache_size": 0, "prepared_statement_cache_size": 0},
    )
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


# ── Tablolari temizle ─────────────────────────────────────────────────────────
async def truncate_all(conn: asyncpg.Connection):
    await conn.execute(
        "TRUNCATE orders, menu_items, restaurants, user_addresses, users RESTART IDENTITY CASCADE"
    )
    logger.info("Tablolar temizlendi.")


# ── Migrate: Users ────────────────────────────────────────────────────────────
async def migrate_users(db_client, conn: asyncpg.Connection):
    logger.info("Kullanıcılar migrate ediliyor…")
    docs = list(db_client.collection("users").stream())
    seen_emails: set[str] = set()
    count = 0

    for doc in docs:
        data = doc.to_dict()
        uid = doc.id
        raw_email = _safe_str(data.get("email")) or f"{uid[:8]}@nomail.internal"

        # Aynı email birden fazla UID'de varsa dedup yap
        if raw_email in seen_emails:
            email = f"{uid[:8]}@dedup.yemeksepeti"
            logger.warning(f"  ⚠️  Email çakışması — {uid} için dedup email: {email}")
        else:
            email = raw_email
        seen_emails.add(email)

        try:
            await conn.execute(
                """
                INSERT INTO users (id, email, display_name, role, city, phone, managed_restaurant_id)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                ON CONFLICT (id) DO UPDATE SET
                    email = EXCLUDED.email,
                    display_name = EXCLUDED.display_name,
                    role = EXCLUDED.role,
                    city = EXCLUDED.city,
                    phone = EXCLUDED.phone,
                    managed_restaurant_id = EXCLUDED.managed_restaurant_id
                """,
                uid,
                email,
                _safe_str(data.get("displayName") or email[:30]),
                _safe_str(data.get("role"), "user"),
                data.get("city"),
                data.get("phone"),
                data.get("managedRestaurantId"),
            )
            count += 1
        except Exception as e:
            logger.warning(f"  ⚠️  Kullanıcı atlandı ({uid}): {e}")

    logger.info(f"Users migrate tamamlandı: {count}/{len(docs)} kullanıcı.")


# ── Migrate: Restaurants + MenuItems ─────────────────────────────────────────
async def migrate_restaurants(db_client, conn: asyncpg.Connection):
    logger.info("Restoranlar migrate ediliyor…")
    docs = list(db_client.collection("restaurants").stream())
    r_count = m_count = 0

    for doc in docs:
        data = doc.to_dict()
        rid = doc.id
        owner_id = data.get("ownerId")

        async def _insert_restaurant(oid):
            await conn.execute(
                """
                INSERT INTO restaurants (
                    id, owner_id, name, description, cuisine_type,
                    image_url, rating, delivery_time, min_order_amount,
                    is_active, city, allows_pickup, allows_cash_on_del,
                    successful_order_count, average_rating, rating_count
                ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
                ON CONFLICT (id) DO UPDATE SET
                    owner_id = EXCLUDED.owner_id,
                    name = EXCLUDED.name,
                    description = EXCLUDED.description,
                    cuisine_type = EXCLUDED.cuisine_type,
                    image_url = EXCLUDED.image_url,
                    rating = EXCLUDED.rating,
                    delivery_time = EXCLUDED.delivery_time,
                    min_order_amount = EXCLUDED.min_order_amount,
                    is_active = EXCLUDED.is_active,
                    city = EXCLUDED.city,
                    allows_pickup = EXCLUDED.allows_pickup,
                    allows_cash_on_del = EXCLUDED.allows_cash_on_del,
                    successful_order_count = EXCLUDED.successful_order_count,
                    average_rating = EXCLUDED.average_rating,
                    rating_count = EXCLUDED.rating_count
                """,
                rid, oid,
                _safe_str(data.get("name"), "İsimsiz Restoran"),
                _safe_str(data.get("description")),
                _safe_str(data.get("cuisineType")),
                data.get("imageUrl"),
                _safe_float(data.get("rating")),
                _safe_str(data.get("deliveryTime")),
                _safe_float(data.get("minOrderAmount")),
                _safe_bool(data.get("isActive"), True),
                data.get("city"),
                _safe_bool(data.get("allowsPickup")),
                _safe_bool(data.get("allowsCashOnDelivery")),
                int(data.get("successfulOrderCount", 0)),
                _safe_float(data.get("averageRating")),
                int(data.get("ratingCount", 0)),
            )

        try:
            await _insert_restaurant(owner_id)
            r_count += 1
        except asyncpg.ForeignKeyViolationError:
            # owner_id Firestore users koleksiyonunda yok → NULL ile ekle
            try:
                await _insert_restaurant(None)
                r_count += 1
                logger.warning(f"  ⚠️  Restoran ({rid}) owner_id=NULL ile eklendi")
            except Exception as e2:
                logger.warning(f"  ⚠️  Restoran atlandı ({rid}): {e2}")
                continue
        except Exception as e:
            logger.warning(f"  ⚠️  Restoran atlandı ({rid}): {e}")
            continue

        # Menü öğeleri — Firestore'da restaurant.menu array'i
        for item in data.get("menu") or []:
            item_id = item.get("id") or str(uuid.uuid4())
            try:
                await conn.execute(
                    """
                    INSERT INTO menu_items (
                        id, restaurant_id, name, description, price,
                        image_url, category, discount_percent,
                        is_available, option_groups, suggested_ids
                    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb,$11::text[])
                    ON CONFLICT (id) DO UPDATE SET
                        name = EXCLUDED.name,
                        description = EXCLUDED.description,
                        price = EXCLUDED.price,
                        image_url = EXCLUDED.image_url,
                        category = EXCLUDED.category,
                        discount_percent = EXCLUDED.discount_percent,
                        is_available = EXCLUDED.is_available,
                        option_groups = EXCLUDED.option_groups,
                        suggested_ids = EXCLUDED.suggested_ids
                    """,
                    item_id,
                    rid,
                    _safe_str(item.get("name")),
                    _safe_str(item.get("description")),
                    _safe_float(item.get("price")),
                    item.get("imageUrl"),
                    _safe_str(item.get("category"), "Diğer"),
                    _safe_float(item.get("discountPercent")),
                    _safe_bool(item.get("isAvailable"), True),
                    json.dumps(item.get("optionGroups") or []),
                    [str(s) for s in (item.get("suggestedItemIds") or [])],
                )
                m_count += 1
            except Exception as e:
                logger.warning(f"    ⚠️  Menü öğesi atlandı ({item_id}): {e}")

    logger.info(f"Restaurants migrate tamamlandı: {r_count}/{len(docs)} restoran, {m_count} menü öğesi.")


# ── Migrate: Orders ───────────────────────────────────────────────────────────
async def migrate_orders(db_client, conn: asyncpg.Connection):
    logger.info("Siparişler migrate ediliyor…")
    docs = list(db_client.collection("orders").stream())
    count = 0

    for doc in docs:
        data = doc.to_dict()
        oid = doc.id

        delivery_addr = data.get("deliveryAddress")
        if isinstance(delivery_addr, dict):
            delivery_addr = json.dumps(delivery_addr)

        items = data.get("items") or []
        if not isinstance(items, str):
            items = json.dumps(items)

        try:
            await conn.execute(
                """
                INSERT INTO orders (
                    id, user_id, restaurant_id, status, payment_method,
                    delivery_address, items, subtotal, delivery_fee,
                    discount_amount, total_amount, coupon_code, notes, is_rated
                ) VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7::jsonb,$8,$9,$10,$11,$12,$13,$14)
                ON CONFLICT (id) DO UPDATE SET
                    status = EXCLUDED.status,
                    payment_method = EXCLUDED.payment_method,
                    total_amount = EXCLUDED.total_amount
                """,
                oid,
                _safe_str(data.get("userId")),
                _safe_str(data.get("restaurantId")),
                _safe_str(data.get("status"), "completed"),
                _safe_str(data.get("paymentMethod"), "cashOnDelivery"),
                delivery_addr if delivery_addr else "null",
                items,
                _safe_float(data.get("subtotal")),
                _safe_float(data.get("deliveryFee")),
                _safe_float(data.get("discountAmount")),
                _safe_float(data.get("totalAmount")),
                data.get("couponCode"),
                data.get("notes"),
                _safe_bool(data.get("isRated")),
            )
            count += 1
        except Exception as e:
            logger.warning(f"  ⚠️  Sipariş atlandı ({oid}): {e}")

    logger.info(f"Orders migrate tamamlandı: {count}/{len(docs)} sipariş.")


# ── Embedding üret (migration sonrası) ────────────────────────────────────────
async def generate_all_embeddings(session_factory):
    from app.repositories.sql_repos import SQLMenuItemRepository
    from app.services.embedding_service import EmbeddingService
    from app.models.orm_models import MenuItemORM
    from sqlalchemy import select

    logger.info("Menü öğeleri için embedding üretiliyor…")
    emb = EmbeddingService()
    if not emb._enabled:
        logger.warning("USE_EMBEDDINGS=false — embedding atlandı.")
        return

    async with session_factory() as session:
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
async def pre_seed_missing_ids(db_client, conn: asyncpg.Connection):
    """TRUNCATE sonrası, Firestore'da users/restaurants koleksiyonunda olmayan
    ama orders/restaurants tarafından FK ile referans edilen ID'ler için stub ekler."""
    logger.info("Pre-seed: eksik FK kayıtları oluşturuluyor…")

    owner_ids: set[str] = set()
    firestore_rest_ids: set[str] = set()
    order_user_ids: set[str] = set()
    order_rest_ids: set[str] = set()
    firestore_user_ids: set[str] = set()

    for doc in db_client.collection("users").stream():
        firestore_user_ids.add(doc.id)
    for doc in db_client.collection("restaurants").stream():
        firestore_rest_ids.add(doc.id)
        oid = doc.to_dict().get("ownerId")
        if oid:
            owner_ids.add(oid)
    for doc in db_client.collection("orders").stream():
        d = doc.to_dict()
        if d.get("userId"):
            order_user_ids.add(d["userId"])
        if d.get("restaurantId"):
            order_rest_ids.add(d["restaurantId"])

    # Stub users: owner veya order'da geçip Firestore users'da olmayan UID'ler
    missing_uids = (owner_ids | order_user_ids) - firestore_user_ids
    # Stub restaurants: sadece order'da geçip Firestore restaurants'da olmayan ID'ler
    missing_rids = order_rest_ids - firestore_rest_ids

    if missing_uids:
        await conn.executemany(
            "INSERT INTO users (id, email, display_name, role) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING",
            [(uid, f"ghost_{uid[:8]}@ghost.internal", f"Ghost_{uid[:6]}", "user") for uid in missing_uids],
        )
        logger.info(f"  {len(missing_uids)} stub kullanıcı eklendi")

    if missing_rids:
        await conn.executemany(
            "INSERT INTO restaurants (id, name, is_active) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
            [(rid, "Silinmiş Restoran", False) for rid in missing_rids],
        )
        logger.info(f"  {len(missing_rids)} stub restoran eklendi")

    logger.info("Pre-seed tamamlandı.")


async def main():
    db_client = init_firebase()
    conn = await get_conn()
    engine, session_factory = await get_pg_session()

    try:
        await truncate_all(conn)                               # temiz sayfa
        await pre_seed_missing_ids(db_client, conn)            # ghost FK kayıtları
        await migrate_users(db_client, conn)                   # gerçek users (ghostları günceller)
        await migrate_restaurants(db_client, conn)             # restaurants + menu_items
        await migrate_orders(db_client, conn)                  # orders
        await generate_all_embeddings(session_factory)         # embedding üret
        logger.info("\n✅ Migration tamamlandı.")
    finally:
        await conn.close()
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
