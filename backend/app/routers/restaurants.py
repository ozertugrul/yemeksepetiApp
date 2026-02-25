"""
/api/v1/restaurants  — CRUD + menü yönetimi
"""
from __future__ import annotations

import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import FirebaseUser, get_current_user, get_optional_user, require_role
from app.core.database import get_db
from app.repositories.sql_repos import SQLMenuItemRepository, SQLRestaurantRepository, SQLUserRepository  # noqa: F401 (SQLUserRepository co-owner için)
from app.schemas.schemas import (
    MenuItemCreate, MenuItemOut,
    RestaurantCreate, RestaurantOut,
)
from app.services.embedding_service import EmbeddingService

router = APIRouter(prefix="/restaurants", tags=["Restaurants"])
embedding_service = EmbeddingService()


def _orm_menu_to_schema(item) -> MenuItemOut:
    return MenuItemOut(
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
    )


def _orm_to_schema(r, include_menu: bool = False) -> RestaurantOut:
    menu = [_orm_menu_to_schema(m) for m in (r.menu_items or [])] if include_menu else []
    return RestaurantOut(
        id=r.id,
        owner_id=r.owner_id,
        name=r.name,
        description=r.description or "",
        cuisine_type=r.cuisine_type or "",
        image_url=r.image_url,
        rating=r.rating or 0,
        delivery_time=r.delivery_time or "",
        min_order_amount=r.min_order_amount or 0,
        is_active=r.is_active,
        city=r.city,
        allows_pickup=r.allows_pickup,
        allows_cash_on_delivery=r.allows_cash_on_del,
        successful_order_count=r.successful_order_count or 0,
        average_rating=r.average_rating or 0,
        rating_count=r.rating_count or 0,
        menu=menu,
        created_at=r.created_at,
    )


# ── Listele ───────────────────────────────────────────────────────────────────

@router.get("", response_model=List[RestaurantOut])
async def list_restaurants(
    city: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    _user: Optional[FirebaseUser] = Depends(get_optional_user),
):
    repo = SQLRestaurantRepository(db)
    restaurants = await repo.get_all_active(city=city)
    return [_orm_to_schema(r) for r in restaurants]


@router.get("/admin/all", response_model=List[RestaurantOut])
async def list_all_restaurants_admin(
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser = Depends(require_role("admin")),
):
    repo = SQLRestaurantRepository(db)
    return [_orm_to_schema(r) for r in await repo.get_all()]


@router.get("/my", response_model=RestaurantOut)
async def get_my_restaurant(
    db: AsyncSession = Depends(get_db),
    user: FirebaseUser = Depends(require_role("storeOwner", "admin")),
):
    """
    Sahip veya ortak sahip olunan restoranı döndürür.
    Önce kullanıcının managed_restaurant_id'sini kullanır (co-owner desteği),
    bulunamazsa owner_id ile geriye dönük arama yapar.
    """
    repo = SQLRestaurantRepository(db)
    user_repo = SQLUserRepository(db)

    db_user = await user_repo.get_by_id(user.uid)
    if db_user and db_user.managed_restaurant_id:
        r = await repo.get_by_id(db_user.managed_restaurant_id, include_menu=True)
        if r:
            return _orm_to_schema(r, include_menu=True)

    # Fallback: primary owner_id ile ara
    r = await repo.get_by_owner(user.uid, include_menu=True)
    if not r:
        raise HTTPException(status_code=404, detail="Restoranınız bulunamadı.")
    return _orm_to_schema(r, include_menu=True)


@router.get("/{restaurant_id}", response_model=RestaurantOut)
async def get_restaurant(
    restaurant_id: str,
    db: AsyncSession = Depends(get_db),
    _user: Optional[FirebaseUser] = Depends(get_optional_user),
):
    repo = SQLRestaurantRepository(db)
    r = await repo.get_by_id(restaurant_id, include_menu=True)
    if not r:
        raise HTTPException(status_code=404, detail="Restoran bulunamadı.")
    return _orm_to_schema(r, include_menu=True)


# ── Oluştur / Güncelle ────────────────────────────────────────────────────────

@router.post("", response_model=RestaurantOut, status_code=status.HTTP_201_CREATED)
async def create_restaurant(
    body: RestaurantCreate,
    db: AsyncSession = Depends(get_db),
    user: FirebaseUser = Depends(get_current_user),
):
    # Sadece storeOwner veya admin mağaza açabilir
    if user.role not in ("storeOwner", "admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Mağaza açmak için 'storeOwner' veya 'admin' rolü gerekli.",
        )

    repo = SQLRestaurantRepository(db)

    # storeOwner: zaten bir mağazası varsa ikincisini açamaz
    if user.role == "storeOwner":
        existing = await repo.get_by_owner(user.uid)
        if existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Zaten bir mağazanız mevcut. Her store owner yalnızca 1 mağaza açabilir.",
            )

    data = body.model_dump(by_alias=False)
    data.setdefault("id", str(uuid.uuid4()))
    actual_owner_id = data.get("owner_id") or user.uid
    data["owner_id"] = actual_owner_id
    data["allows_cash_on_del"] = data.pop("allows_cash_on_delivery", False)
    r = await repo.create(data)

    # managed_restaurant_id'yi sahip kullanıcıda da güncelle.
    # Bu olmadan co-owner kontrolü primary owner'ı bulamaz → yanlış kapatma.
    try:
        user_repo = SQLUserRepository(db)
        await user_repo.update(actual_owner_id, {"managed_restaurant_id": r.id})
    except Exception:
        pass  # Non-critical — restoranı döndür

    return _orm_to_schema(r)


@router.put("/{restaurant_id}", response_model=RestaurantOut)
async def update_restaurant(
    restaurant_id: str,
    body: RestaurantCreate,
    db: AsyncSession = Depends(get_db),
    user: FirebaseUser = Depends(get_current_user),
):
    repo = SQLRestaurantRepository(db)
    user_repo = SQLUserRepository(db)
    existing = await repo.get_by_id(restaurant_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Restoran bulunamadı.")

    # Rol + sahiplik kontrolü
    if user.role not in ("storeOwner", "admin"):
        raise HTTPException(status_code=403, detail="Bu restoranı değiştirme yetkiniz yok.")

    if user.role != "admin":
        db_user = await user_repo.get_by_id(user.uid)
        is_primary_owner = existing.owner_id == user.uid
        is_co_owner = bool(db_user and db_user.managed_restaurant_id == restaurant_id)
        if not is_primary_owner and not is_co_owner:
            raise HTTPException(status_code=403, detail="Bu restoranı değiştirme yetkiniz yok.")

    data = body.model_dump(by_alias=False, exclude_unset=True)
    data.pop("id", None)
    if "allows_cash_on_delivery" in data:
        data["allows_cash_on_del"] = data.pop("allows_cash_on_delivery")
    r = await repo.update(restaurant_id, data, include_menu=True)
    return _orm_to_schema(r, include_menu=True)


# ── Menü öğeleri ──────────────────────────────────────────────────────────────

@router.post("/{restaurant_id}/menu", response_model=MenuItemOut, status_code=201)
async def add_menu_item(
    restaurant_id: str,
    body: MenuItemCreate,
    db: AsyncSession = Depends(get_db),
    user: FirebaseUser = Depends(get_current_user),
):
    rest_repo = SQLRestaurantRepository(db)
    user_repo = SQLUserRepository(db)

    restaurant = await rest_repo.get_by_id(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restoran bulunamadı.")

    if user.role not in ("storeOwner", "admin"):
        raise HTTPException(status_code=403, detail="Bu restorana menü ekleme yetkiniz yok.")

    if user.role != "admin":
        db_user = await user_repo.get_by_id(user.uid)
        is_primary_owner = restaurant.owner_id == user.uid
        is_co_owner = bool(db_user and db_user.managed_restaurant_id == restaurant_id)
        if not is_primary_owner and not is_co_owner:
            raise HTTPException(status_code=403, detail="Bu restorana menü ekleme yetkiniz yok.")

    data = body.model_dump(by_alias=False)
    data["restaurant_id"] = restaurant_id
    data.setdefault("id", str(uuid.uuid4()))
    # option_groups: Pydantic obj → dict
    data["option_groups"] = [og.model_dump(by_alias=False) for og in body.option_groups]
    data["suggested_ids"] = body.suggested_ids

    item_repo = SQLMenuItemRepository(db)
    item = await item_repo.upsert(data)

    # Embedding üret (async — non-blocking)
    text = EmbeddingService.menu_item_text(item.name, item.description or "", item.category or "")
    vec = embedding_service.embed_text(text)
    if vec:
        await item_repo.update_embedding(item.id, vec)

    return _orm_menu_to_schema(item)


@router.delete("/{restaurant_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_restaurant(
    restaurant_id: str,
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser = Depends(require_role("admin")),
):
    repo = SQLRestaurantRepository(db)
    deleted = await repo.delete(restaurant_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Restoran bulunamadı.")
