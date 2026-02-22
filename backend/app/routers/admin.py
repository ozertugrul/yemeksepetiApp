"""
/api/v1/admin — Admin-only kullanıcı ve sistem yönetimi
"""
from __future__ import annotations

import json
import os
import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import FirebaseUser, _init_firebase_app, require_role
from app.core.database import get_db
from app.repositories.sql_repos import SQLRestaurantRepository, SQLUserRepository
from app.schemas.schemas import RestaurantOut, UserOut

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
    repo = SQLUserRepository(db)
    u = await repo.update(uid, {"role": role})
    if not u:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
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
    repo = SQLUserRepository(db)
    deleted = await repo.delete_by_id(uid)
    if not deleted:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")


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

