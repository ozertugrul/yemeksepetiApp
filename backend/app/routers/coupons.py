from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import AuthenticatedUser, require_role
from app.core.database import get_db
from app.models.orm_models import CouponORM, RestaurantORM
from app.repositories.sql_repos import SQLRestaurantRepository, SQLUserRepository
from app.schemas.schemas import CouponOut, CouponUpsert

router = APIRouter(prefix="/coupons", tags=["Coupons"])


def _to_schema(c: CouponORM, restaurant_name: str | None = None) -> CouponOut:
    return CouponOut(
        id=c.id,
        restaurant_id=c.restaurant_id,
        code=c.code,
        description=c.description or "",
        discount_amount=float(c.discount_amount or 0),
        discount_percent=float(c.discount_percent or 0),
        minimum_order_amount=float(c.minimum_order_amount or 0),
        expiry_date=c.expiry_date,
        is_active=bool(c.is_active),
        is_public=bool(c.is_public),
        city=c.city,
        restaurant_name=restaurant_name,
        created_at=c.created_at,
    )


async def _assert_owner_or_admin(
    db: AsyncSession,
    user: AuthenticatedUser,
    restaurant_id: str,
) -> None:
    if user.role == "admin":
        return

    rest_repo = SQLRestaurantRepository(db)
    user_repo = SQLUserRepository(db)
    restaurant = await rest_repo.get_by_id(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restoran bulunamadı.")

    db_user = await user_repo.get_by_id(user.uid)
    is_primary_owner = restaurant.owner_id == user.uid
    is_co_owner = bool(db_user and db_user.managed_restaurant_id == restaurant_id)
    if not (is_primary_owner or is_co_owner):
        raise HTTPException(status_code=403, detail="Bu restoranın kuponlarını yönetme yetkiniz yok.")


@router.get("/restaurant/{restaurant_id}", response_model=List[CouponOut])
async def list_store_coupons(
    restaurant_id: str,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(require_role("storeOwner", "admin")),
):
    await _assert_owner_or_admin(db, user, restaurant_id)
    result = await db.execute(
        select(CouponORM, RestaurantORM.name)
        .outerjoin(RestaurantORM, RestaurantORM.id == CouponORM.restaurant_id)
        .where(CouponORM.restaurant_id == restaurant_id)
        .order_by(CouponORM.created_at.desc())
    )
    return [_to_schema(coupon, restaurant_name=name) for coupon, name in result.all()]


@router.get("/public", response_model=List[CouponOut])
async def list_public_coupons(
    city: str | None = None,
    restaurant_id: str | None = None,
    cart_total: float | None = None,
    db: AsyncSession = Depends(get_db),
):
    now = datetime.now(timezone.utc)
    query = (
        select(CouponORM, RestaurantORM.name)
        .outerjoin(RestaurantORM, RestaurantORM.id == CouponORM.restaurant_id)
        .where(CouponORM.is_public == True)  # noqa: E712
        .where(CouponORM.is_active == True)  # noqa: E712
        .where(CouponORM.expiry_date > now)
    )

    if city and city.strip():
        city_text = city.strip().lower()
        query = query.where(
            or_(
                CouponORM.city.is_(None),
                func.lower(CouponORM.city) == city_text,
            )
        )

    if restaurant_id and restaurant_id.strip():
        rid = restaurant_id.strip()
        query = query.where(
            or_(
                CouponORM.restaurant_id.is_(None),
                CouponORM.restaurant_id == rid,
            )
        )

    if cart_total is not None:
        query = query.where(CouponORM.minimum_order_amount <= cart_total)

    query = query.order_by(CouponORM.created_at.desc())
    rows = (await db.execute(query)).all()
    return [_to_schema(coupon, restaurant_name=name) for coupon, name in rows]


@router.get("/code/{code}", response_model=CouponOut)
async def get_coupon_by_code(
    code: str,
    restaurant_id: str | None = None,
    db: AsyncSession = Depends(get_db),
):
    normalized = code.strip().upper()
    if not normalized:
        raise HTTPException(status_code=422, detail="Kupon kodu boş olamaz.")

    result = await db.execute(select(CouponORM).where(CouponORM.code == normalized))
    coupon = result.scalar_one_or_none()
    if not coupon:
        raise HTTPException(status_code=404, detail="Kupon bulunamadı.")

    if not coupon.is_active:
        raise HTTPException(status_code=409, detail="Bu kupon aktif değil.")

    if coupon.expiry_date and coupon.expiry_date <= datetime.now(timezone.utc):
        raise HTTPException(status_code=409, detail="Bu kuponun süresi dolmuş.")

    if coupon.restaurant_id and restaurant_id and coupon.restaurant_id != restaurant_id:
        raise HTTPException(status_code=409, detail="Bu kupon bu mağazada geçerli değil.")

    return _to_schema(coupon)


@router.post("", response_model=CouponOut, status_code=status.HTTP_201_CREATED)
async def create_coupon(
    body: CouponUpsert,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(require_role("storeOwner", "admin")),
):
    restaurant_id = (body.restaurant_id or "").strip()
    if not restaurant_id:
        raise HTTPException(status_code=422, detail="restaurantId zorunludur.")

    await _assert_owner_or_admin(db, user, restaurant_id)

    code = body.code.strip().upper()
    if not code:
        raise HTTPException(status_code=422, detail="Kupon kodu boş olamaz.")

    if body.discount_amount <= 0 and body.discount_percent <= 0:
        raise HTTPException(status_code=422, detail="İndirim tutarı veya yüzdesi sıfırdan büyük olmalı.")

    if body.discount_amount > 0 and body.discount_percent > 0:
        raise HTTPException(status_code=422, detail="Kupon tek bir indirim türü içermelidir.")

    expiry = body.expiry_date or (datetime.now(timezone.utc) + timedelta(days=90))

    coupon = CouponORM(
        id=body.id or str(uuid.uuid4()),
        restaurant_id=restaurant_id,
        code=code,
        description=(body.description or "").strip(),
        discount_amount=float(body.discount_amount or 0),
        discount_percent=float(body.discount_percent or 0),
        minimum_order_amount=float(body.minimum_order_amount or 0),
        expiry_date=expiry,
        is_active=body.is_active,
        is_public=body.is_public,
        city=(body.city.strip() if body.city else None),
    )
    db.add(coupon)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Bu kupon kodu zaten kullanılıyor.")

    restaurant_name: str | None = None
    if coupon.restaurant_id:
        rest = await SQLRestaurantRepository(db).get_by_id(coupon.restaurant_id)
        restaurant_name = rest.name if rest else None
    return _to_schema(coupon, restaurant_name=restaurant_name)


@router.put("/{coupon_id}", response_model=CouponOut)
async def update_coupon(
    coupon_id: str,
    body: CouponUpsert,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(require_role("storeOwner", "admin")),
):
    existing_q = await db.execute(select(CouponORM).where(CouponORM.id == coupon_id))
    existing = existing_q.scalar_one_or_none()
    if not existing:
        raise HTTPException(status_code=404, detail="Kupon bulunamadı.")

    target_restaurant_id = (body.restaurant_id or existing.restaurant_id or "").strip()
    if not target_restaurant_id:
        raise HTTPException(status_code=422, detail="restaurantId zorunludur.")

    await _assert_owner_or_admin(db, user, target_restaurant_id)

    code = body.code.strip().upper()
    if not code:
        raise HTTPException(status_code=422, detail="Kupon kodu boş olamaz.")

    if body.discount_amount <= 0 and body.discount_percent <= 0:
        raise HTTPException(status_code=422, detail="İndirim tutarı veya yüzdesi sıfırdan büyük olmalı.")

    if body.discount_amount > 0 and body.discount_percent > 0:
        raise HTTPException(status_code=422, detail="Kupon tek bir indirim türü içermelidir.")

    existing.restaurant_id = target_restaurant_id
    existing.code = code
    existing.description = (body.description or "").strip()
    existing.discount_amount = float(body.discount_amount or 0)
    existing.discount_percent = float(body.discount_percent or 0)
    existing.minimum_order_amount = float(body.minimum_order_amount or 0)
    existing.expiry_date = body.expiry_date or existing.expiry_date
    existing.is_active = body.is_active
    existing.is_public = body.is_public
    existing.city = body.city.strip() if body.city else None

    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Bu kupon kodu zaten kullanılıyor.")

    restaurant_name: str | None = None
    if existing.restaurant_id:
        rest = await SQLRestaurantRepository(db).get_by_id(existing.restaurant_id)
        restaurant_name = rest.name if rest else None
    return _to_schema(existing, restaurant_name=restaurant_name)


@router.delete("/{coupon_id}")
async def delete_coupon(
    coupon_id: str,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(require_role("storeOwner", "admin")),
):
    existing_q = await db.execute(select(CouponORM).where(CouponORM.id == coupon_id))
    existing = existing_q.scalar_one_or_none()
    if not existing:
        raise HTTPException(status_code=404, detail="Kupon bulunamadı.")

    if existing.restaurant_id:
        await _assert_owner_or_admin(db, user, existing.restaurant_id)

    await db.delete(existing)
    return {"ok": True}
