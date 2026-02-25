"""
/api/v1/admin — Admin-only kullanıcı ve sistem yönetimi
"""
from __future__ import annotations

import json
import os
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import func as sql_func, select as sa_select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import FirebaseUser, _init_firebase_app, require_role
from app.core.database import get_db
from app.models.orm_models import OrderORM, RestaurantORM, UserORM
from app.repositories.sql_repos import SQLRestaurantRepository, SQLUserRepository
from app.schemas.schemas import CamelModel, RestaurantOut, UserOut

router = APIRouter(prefix="/admin", tags=["Admin"])


def _user_schema(u) -> UserOut:
    return UserOut(
        id=u.id, email=u.email, display_name=u.display_name,
        role=u.role, city=u.city, phone=u.phone,
        managed_restaurant_id=u.managed_restaurant_id,
    )


def _restaurant_schema(r) -> RestaurantOut:
    return RestaurantOut(
        id=r.id, owner_id=r.owner_id, name=r.name,
        description=r.description or "", cuisine_type=r.cuisine_type or "",
        image_url=r.image_url, rating=r.rating or 0,
        delivery_time=r.delivery_time or "", min_order_amount=r.min_order_amount or 0,
        is_active=r.is_active, city=r.city,
        allows_pickup=r.allows_pickup, allows_cash_on_delivery=r.allows_cash_on_del,
        successful_order_count=r.successful_order_count or 0,
        average_rating=r.average_rating or 0, rating_count=r.rating_count or 0,
        menu=[], created_at=r.created_at,
    )


# ── Kullanıcı Listesi ─────────────────────────────────────────────────────────

@router.get("/users", response_model=List[UserOut])
async def list_all_users(
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser = Depends(require_role("admin")),
):
    repo = SQLUserRepository(db)
    users = await repo.get_all()
    return [_user_schema(u) for u in users]


class AdminUsersPage(CamelModel):
    users: List[UserOut]
    total: int
    offset: int
    limit: int
    next_offset: Optional[int] = None
    has_more: bool


@router.get("/users/paged", response_model=AdminUsersPage)
async def list_users_paged(
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser = Depends(require_role("admin")),
):
    repo = SQLUserRepository(db)
    total = await repo.count_all()
    rows = await repo.get_page(offset=offset, limit=limit)
    users = [_user_schema(u) for u in rows]
    next_offset = offset + len(users)
    has_more = next_offset < total
    return AdminUsersPage(
        users=users,
        total=total,
        offset=offset,
        limit=limit,
        next_offset=next_offset if has_more else None,
        has_more=has_more,
    )


# ── Kullanıcı Oluştur ─────────────────────────────────────────────────────────

class AdminUserCreate(BaseModel):
    email: str
    password: str
    display_name: Optional[str] = None
    role: str = "user"


@router.post("/users", response_model=UserOut, status_code=201)
async def create_user(
    body: AdminUserCreate,
    db: AsyncSession = Depends(get_db),
    _admin: FirebaseUser = Depends(require_role("admin")),
):
    from firebase_admin import auth as firebase_auth

    _init_firebase_app()

    if body.role not in ("user", "storeOwner", "admin"):
        raise HTTPException(status_code=422, detail=f"Geçersiz rol: {body.role!r}")

    # Firebase'de kullanıcı oluştur
    try:
        fb_user = firebase_auth.create_user(
            email=body.email,
            password=body.password,
            display_name=body.display_name or "",
            email_verified=False,
        )
    except firebase_auth.EmailAlreadyExistsError:
        raise HTTPException(status_code=409, detail="Bu e-posta zaten kayıtlı.")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Firebase kullanıcı oluşturulamadı: {e}")

    # PostgreSQL'e kaydet
    repo = SQLUserRepository(db)
    u = await repo.upsert({
        "id": fb_user.uid,
        "email": body.email,
        "display_name": body.display_name or "",
        "role": body.role,
    })
    return _user_schema(u)


# ── Rol Güncelle ──────────────────────────────────────────────────────────────

@router.patch("/users/{uid}/role", response_model=UserOut)
async def update_user_role(
    uid: str,
    body: dict,
    db: AsyncSession = Depends(get_db),
    current_user: FirebaseUser = Depends(require_role("admin")),
):
    if uid == current_user.uid:
        raise HTTPException(status_code=400, detail="Kendi rolünüzü değiştiremezsiniz.")
    role = body.get("role")
    if role not in ("user", "storeOwner", "admin"):
        raise HTTPException(status_code=422, detail=f"Geçersiz rol: {role!r}")

    user_repo = SQLUserRepository(db)
    user = await user_repo.get_by_id(uid)
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")

    # storeOwner'dan farklı bir role düşürülüyorsa
    if user.role == "storeOwner" and role != "storeOwner":
        rest_repo = SQLRestaurantRepository(db)

        # Hangi restoranla bağlantılı? managed_restaurant_id önce, yoksa owner_id üzerinden
        managed_rest_id = user.managed_restaurant_id
        if not managed_rest_id:
            owned = await rest_repo.get_by_owner(uid)
            if owned:
                managed_rest_id = owned.id

        if managed_rest_id:
            restaurant = await rest_repo.get_by_id(managed_rest_id)

            # Başka sahip var mı? ─ managed_restaurant_id üzerinden bağlı diğer kullanıcılar
            co_owners_result = await db.execute(
                sa_select(UserORM).where(
                    UserORM.managed_restaurant_id == managed_rest_id,
                    UserORM.id != uid,
                )
            )
            co_owners = co_owners_result.scalars().all()

            # Restoranın owner_id alanı başka birine mi ait? (primary owner ayrı kişi)
            has_other_primary = (
                restaurant is not None
                and restaurant.owner_id is not None
                and restaurant.owner_id != uid
            )

            if not co_owners and not has_other_primary:
                # Gerçekten son sahip → restoranı pasife al ve sahipsizleştir
                if restaurant:
                    await rest_repo.update(restaurant.id, {"is_active": False, "owner_id": None})

        # Kullanıcının managed_restaurant_id'sini temizle
        await user_repo.update(uid, {"managed_restaurant_id": None})

    u = await user_repo.update(uid, {"role": role})
    return _user_schema(u)


# ── Kullanıcı Sil ─────────────────────────────────────────────────────────────

@router.delete("/users/{uid}", status_code=204)
async def delete_user(
    uid: str,
    db: AsyncSession = Depends(get_db),
    current_user: FirebaseUser = Depends(require_role("admin")),
):
    if uid == current_user.uid:
        raise HTTPException(status_code=400, detail="Kendinizi silemezsiniz.")

    user_repo = SQLUserRepository(db)
    user = await user_repo.get_by_id(uid)
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")

    # Önce Firebase hesabını sil: aksi halde PostgreSQL'den silinip Firebase'de kalan
    # kullanıcı /users/me ile tekrar oluşturulabilir.
    _init_firebase_app()
    try:
        from firebase_admin import auth as firebase_auth
        firebase_auth.delete_user(uid)
    except firebase_auth.UserNotFoundError:
        pass
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Firebase kullanıcı silinemedi: {e}")

    # Restoranı varsa: FK kısıtı nedeniyle kullanıcı silinemez.
    # Restoranı sahipsizleştir + pasife al — sadece gerçekten son sahipse.
    rest_repo = SQLRestaurantRepository(db)

    # Hangi restoranla bağlantılı?
    managed_rest_id = user.managed_restaurant_id
    if not managed_rest_id:
        owned = await rest_repo.get_by_owner(uid)
        if owned:
            managed_rest_id = owned.id

    if managed_rest_id:
        restaurant = await rest_repo.get_by_id(managed_rest_id)

        co_owners_result = await db.execute(
            sa_select(UserORM).where(
                UserORM.managed_restaurant_id == managed_rest_id,
                UserORM.id != uid,
            )
        )
        co_owners = co_owners_result.scalars().all()

        has_other_primary = (
            restaurant is not None
            and restaurant.owner_id is not None
            and restaurant.owner_id != uid
        )

        if not co_owners and not has_other_primary:
            if restaurant:
                await rest_repo.update(restaurant.id, {"is_active": False, "owner_id": None})

    # PostgreSQL'den sil:
    # 1. Önce kullanıcının siparişlerini sil (orders.user_id NOT NULL FK kısıtı)
    from sqlalchemy import delete as sa_delete
    from app.models.orm_models import OrderORM
    await db.execute(sa_delete(OrderORM).where(OrderORM.user_id == uid))

    # 2. Kullanıcıyı sil (user_addresses cascade ile gider)
    deleted = await user_repo.delete_by_id(uid)
    if not deleted:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")

    return None


# ── Restoran Yönetimi ─────────────────────────────────────────────────────────

@router.get("/restaurants", response_model=List[RestaurantOut])
async def list_all_restaurants(
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser = Depends(require_role("admin")),
):
    repo = SQLRestaurantRepository(db)
    restaurants = await repo.get_all()
    return [_restaurant_schema(r) for r in restaurants]


@router.patch("/restaurants/{restaurant_id}/toggle", response_model=RestaurantOut)
async def toggle_restaurant_active(
    restaurant_id: str,
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser = Depends(require_role("admin")),
):
    repo = SQLRestaurantRepository(db)
    r = await repo.get_by_id(restaurant_id)
    if not r:
        raise HTTPException(status_code=404, detail="Restoran bulunamadı.")
    updated = await repo.update(restaurant_id, {"is_active": not r.is_active})
    return _restaurant_schema(updated)


# ── Ortak Sahip Ata ───────────────────────────────────────────────────────────

class ManagedRestaurantBody(CamelModel):
    restaurant_id: Optional[str] = None   # None → ilişkiyi kes
    # CamelModel sayesinde iOS'tan gelen 'restaurantId' → restaurant_id olarak parse edilir


@router.patch("/users/{uid}/managed-restaurant", response_model=UserOut)
async def assign_managed_restaurant(
    uid: str,
    body: ManagedRestaurantBody,
    db: AsyncSession = Depends(get_db),
    _admin: FirebaseUser = Depends(require_role("admin")),
):
    """
    Bir kullanıcıya ortak sahip olarak mevcut bir restoran atar.
    - Kullanıcı otomatik olarak storeOwner yapılır.
    - restaurant_id=None gönderilirse bağ koparılır ve kullanıcı 'user' rolüne düşürülür.
    """
    user_repo = SQLUserRepository(db)
    user = await user_repo.get_by_id(uid)
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")

    if body.restaurant_id:
        rest_repo = SQLRestaurantRepository(db)
        restaurant = await rest_repo.get_by_id(body.restaurant_id)
        if not restaurant:
            raise HTTPException(status_code=404, detail="Restoran bulunamadı.")
        u = await user_repo.update(uid, {
            "managed_restaurant_id": body.restaurant_id,
            "role": "storeOwner",
        })
    else:
        # Bağ kopuyorsa: co-owner kontrolü yaparak restoranı pasife almaya gerek yok
        # (sadece bu kullanıcının bağını kopar)
        u = await user_repo.update(uid, {
            "managed_restaurant_id": None,
            "role": "user",
        })

    return _user_schema(u)


# ── İstatistikler ─────────────────────────────────────────────────────────────

@router.get("/stats")
async def get_stats(
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser = Depends(require_role("admin")),
) -> Dict[str, Any]:
    """Gerçek zamanlı admin istatistikleri."""
    # Kullanıcı sayıları (role'e göre grupla)
    role_result = await db.execute(
        sa_select(UserORM.role, sql_func.count(UserORM.id)).group_by(UserORM.role)
    )
    role_counts: Dict[str, int] = dict(role_result.all())
    total_users = sum(role_counts.values())
    store_owner_count = role_counts.get("storeOwner", 0)

    # Restoran sayıları
    rest_result = await db.execute(
        sa_select(RestaurantORM.is_active, sql_func.count(RestaurantORM.id))
        .group_by(RestaurantORM.is_active)
    )
    rest_counts: Dict[bool, int] = dict(rest_result.all())
    total_restaurants = sum(rest_counts.values())
    active_restaurants = rest_counts.get(True, 0)

    # Toplam sipariş
    total_orders_result = await db.execute(
        sa_select(sql_func.count(OrderORM.id))
    )
    total_orders: int = total_orders_result.scalar() or 0

    # Bugünkü sipariş (UTC)
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    today_orders_result = await db.execute(
        sa_select(sql_func.count(OrderORM.id)).where(OrderORM.created_at >= today_start)
    )
    today_orders: int = today_orders_result.scalar() or 0

    return {
        "totalUsers": total_users,
        "storeOwnerCount": store_owner_count,
        "totalRestaurants": total_restaurants,
        "activeRestaurants": active_restaurants,
        "totalOrders": total_orders,
        "todayOrders": today_orders,
    }
