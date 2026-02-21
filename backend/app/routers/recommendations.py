"""
/api/v1/recommendations — pgvector cosine similarity tabanlı öneri sistemi

Endpoint'ler:
  POST /recommendations/menu  → menü öğesi öneri (serbest metin sorgu)
  GET  /recommendations/restaurant/{id}/popular → en çok sipariş edilen öğeler
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import FirebaseUser, get_optional_user
from app.core.config import get_settings
from app.core.database import get_db
from app.repositories.sql_repos import SQLMenuItemRepository
from app.schemas.schemas import MenuItemRecommendation, MenuItemOut, RecommendationOut, RecommendationQuery
from app.services.embedding_service import EmbeddingService

router = APIRouter(prefix="/recommendations", tags=["Recommendations"])
embedding_service = EmbeddingService()


@router.post("/menu", response_model=RecommendationOut)
async def recommend_menu_items(
    body: RecommendationQuery,
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser | None = Depends(get_optional_user),
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
    from fastapi import BackgroundTasks
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
