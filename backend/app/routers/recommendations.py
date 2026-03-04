"""
/api/v1/recommendations — öneri sistemi

Endpoint'ler:
  POST /recommendations/menu         → pgvector cosine similarity (metin sorgu)
  GET  /recommendations/personal     → saat-bazlı user-based CF (kişiselleştirilmiş)
  GET  /recommendations/popular-now  → şu anki zaman diliminde popüler ürünler
  POST /recommendations/embed/batch  → menü embedding batch üretimi
"""
from __future__ import annotations

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import AuthenticatedUser, get_current_user, get_optional_user
from app.core.config import get_settings
from app.core.database import get_db
from app.repositories.sql_repos import SQLMenuItemRepository
from app.schemas.schemas import (
    CFMenuItemOut,
    CFRecommendationItem,
    CFRecommendationOut,
    MenuItemRecommendation,
    MenuItemOut,
    RecommendationOut,
    RecommendationQuery,
)
from app.services.cf_service import CollaborativeFilteringService
from app.services.embedding_service import EmbeddingService

router = APIRouter(prefix="/recommendations", tags=["Recommendations"])
embedding_service = EmbeddingService()
logger = logging.getLogger(__name__)


# ── Kişiselleştirilmiş CF önerileri ──────────────────────────────────────────

@router.get("/personal", response_model=CFRecommendationOut)
async def personal_recommendations(
    city: Optional[str] = Query(None, description="Şehir filtresi"),
    top_n: int = Query(15, ge=1, le=50, description="Kaç öneri"),
    time_segment: Optional[str] = Query(
        None,
        description="Zaman dilimi (breakfast|lunch|afternoon|dinner|late_night). "
                    "Boş bırakılırsa otomatik hesaplanır.",
    ),
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Giriş yapmış kullanıcı için saat-bazlı collaborative filtering önerileri.

    Kullanıcının geçmiş siparişlerine göre benzer kullanıcıları bulur,
    onların tercih ettiği ama bu kullanıcının henüz almadığı ürünleri önerir.
    Yeterli veri yoksa popüler ürünlere fallback yapar.
    """
    settings = get_settings()
    cf = CollaborativeFilteringService(
        db,
        lookback_days=settings.cf_lookback_days,
        min_similarity=settings.cf_min_similarity,
        max_similar_users=settings.cf_max_similar_users,
        embedding_alpha=settings.cf_embedding_alpha if settings.use_embeddings else 0.0,
    )

    try:
        result = await cf.recommend(
            user_id=user.uid,
            time_segment=time_segment,
            city=city,
            top_n=top_n,
        )
        if not result.get("items"):
            result = await cf.popular_now(city=city, top_n=top_n)
    except Exception:
        logger.exception(
            "Personal recommendations failed for user=%s; falling back to popular-now",
            user.uid,
        )
        result = await cf.popular_now(city=city, top_n=top_n)

    return CFRecommendationOut(
        time_segment=result["time_segment"],
        label=result["label"],
        items=[
            CFRecommendationItem(
                score=it["score"],
                source=it["source"],
                supporters=it["supporters"],
                item=CFMenuItemOut(**it["item"]),
            )
            for it in result["items"]
        ],
    )


# ── Popüler ürünler (auth gerektirmez) ───────────────────────────────────────

@router.get("/popular-now", response_model=CFRecommendationOut)
async def popular_now(
    city: Optional[str] = Query(None, description="Şehir filtresi"),
    top_n: int = Query(10, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    _user: AuthenticatedUser | None = Depends(get_optional_user),
):
    """
    Şu anki zaman diliminde en çok sipariş edilen ürünler.
    Giriş yapılmamış veya yeni kullanıcılar için idealdir.
    """
    settings = get_settings()
    cf = CollaborativeFilteringService(
        db,
        lookback_days=settings.cf_lookback_days,
    )

    result = await cf.popular_now(city=city, top_n=top_n)

    return CFRecommendationOut(
        time_segment=result["time_segment"],
        label=result["label"],
        items=[
            CFRecommendationItem(
                score=it["score"],
                source=it["source"],
                supporters=it["supporters"],
                item=CFMenuItemOut(**it["item"]),
            )
            for it in result["items"]
        ],
    )


# ── Mevcut embedding-tabanlı öneri (pgvector cosine similarity) ───────────────

@router.post("/menu", response_model=RecommendationOut)
async def recommend_menu_items(
    body: RecommendationQuery,
    db: AsyncSession = Depends(get_db),
    _user: AuthenticatedUser | None = Depends(get_optional_user),
):
    """
    Serbest metin sorgusunu embed et, pgvector ile en yakın menü öğelerini bul.

    Örnek sorgu: {"query": "baharatlı tavuk burger yanında patates kızartması", "topK": 8}
    """
    settings = get_settings()
    if not settings.use_embeddings:
        raise HTTPException(
            status_code=503,
            detail="Embedding servisi devre dışı. USE_EMBEDDINGS=1 ile etkinleştirin.",
        )

    # 1. Sorguyu embed et
    query_vec = embedding_service.embed_text(body.query)
    if not query_vec:
        raise HTTPException(status_code=400, detail="Sorgu metni boş olamaz.")

    # 2. pgvector cosine similarity araması
    repo = SQLMenuItemRepository(db)
    results = await repo.find_similar(
        embedding=query_vec,
        restaurant_id=body.restaurant_id,
        top_k=body.top_k,
    )

    # 3. Cevap formatla
    recommendations = [
        MenuItemRecommendation(
            score=round(score, 4),
            item=MenuItemOut(
                id=item.id,
                restaurant_id=item.restaurant_id,
                name=item.name,
                description=item.description or "",
                price=item.price,
                image_url=item.image_url,
                category=item.category or "Diğer",
                discount_percent=item.discount_percent or 0,
                is_available=item.is_available,
                option_groups=item.option_groups or [],
                suggested_ids=item.suggested_ids or [],
                created_at=item.created_at,
            ),
        )
        for item, score in results
    ]

    return RecommendationOut(query=body.query, results=recommendations)


@router.post("/embed/batch", status_code=202)
async def batch_embed_restaurant(
    restaurant_id: str,
    db: AsyncSession = Depends(get_db),
    # Sadece admin ya da storeOwner tetikleyebilir
):
    """
    Bir restoranın tüm menü öğeleri için embedding üret (migration / sync).
    Büyük menülerde arka planda çalıştırmak için Celery/BackgroundTasks ile entegre edilebilir.
    """
    repo = SQLMenuItemRepository(db)
    items = await repo.get_by_restaurant(restaurant_id)
    if not items:
        raise HTTPException(status_code=404, detail="Menü öğesi bulunamadı.")

    texts = [
        EmbeddingService.menu_item_text(item.name, item.description or "", item.category or "")
        for item in items
    ]
    vectors = embedding_service.embed_batch(texts)

    updated = 0
    for item, vec in zip(items, vectors):
        if vec:
            await repo.update_embedding(item.id, vec)
            updated += 1

    return {"message": f"{updated} öğe için embedding oluşturuldu.", "restaurant_id": restaurant_id}
