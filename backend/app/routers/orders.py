"""
/api/v1/orders — sipariş oluşturma, listeleme, durum güncelleme
"""
from __future__ import annotations

import uuid
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import FirebaseUser, get_current_user, require_role
from app.core.database import get_db
from app.models.orm_models import RestaurantORM
from app.repositories.sql_repos import SQLOrderRepository
from app.schemas.schemas import OrderCreate, OrderOut, OrderStatusUpdate

router = APIRouter(prefix="/orders", tags=["Orders"])


def _orm_to_schema(o, restaurant_name: str | None = None) -> OrderOut:
    return OrderOut(
        id=o.id,
        user_id=o.user_id,
        restaurant_id=o.restaurant_id,
        restaurant_name=restaurant_name,
        status=o.status,
        payment_method=o.payment_method,
        delivery_address=o.delivery_address,
        items=o.items or [],
        subtotal=o.subtotal or 0,
        delivery_fee=o.delivery_fee or 0,
        discount_amount=o.discount_amount or 0,
        total_amount=o.total_amount or 0,
        coupon_code=o.coupon_code,
        notes=o.notes,
        is_rated=o.is_rated or False,
        created_at=o.created_at,
    )


@router.post("", response_model=OrderOut, status_code=status.HTTP_201_CREATED)
async def create_order(
    body: OrderCreate,
    db: AsyncSession = Depends(get_db),
    user: FirebaseUser = Depends(get_current_user),
):
    data = body.model_dump(by_alias=False)
    data["id"] = str(uuid.uuid4())
    data["user_id"] = user.uid
    data["status"] = "pending"
    # delivery_address → JSON dict
    if data.get("delivery_address"):
        data["delivery_address"] = body.delivery_address.model_dump(by_alias=False) if body.delivery_address else None
    # items → plain dict list
    data["items"] = [item.model_dump(by_alias=False) for item in body.items]

    repo = SQLOrderRepository(db)
    order = await repo.create(data)
    return _orm_to_schema(order)


@router.get("/me", response_model=List[OrderOut])
async def my_orders(
    db: AsyncSession = Depends(get_db),
    user: FirebaseUser = Depends(get_current_user),
):
    repo = SQLOrderRepository(db)
    orders = await repo.get_by_user(user.uid)

    # Restoran adlarını tek sorguda çek (lazy load yok)
    r_ids = list({o.restaurant_id for o in orders})
    name_map: dict = {}
    if r_ids:
        result = await db.execute(
            select(RestaurantORM.id, RestaurantORM.name)
            .where(RestaurantORM.id.in_(r_ids))
        )
        name_map = {row[0]: row[1] for row in result.all()}

    return [_orm_to_schema(o, name_map.get(o.restaurant_id)) for o in orders]


@router.get("/restaurant/{restaurant_id}", response_model=List[OrderOut])
async def restaurant_orders(
    restaurant_id: str,
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser = Depends(require_role("storeOwner", "admin")),
):
    repo = SQLOrderRepository(db)
    orders = await repo.get_by_restaurant(restaurant_id)
    return [_orm_to_schema(o) for o in orders]


@router.get("/{order_id}", response_model=OrderOut)
async def get_order(
    order_id: str,
    db: AsyncSession = Depends(get_db),
    user: FirebaseUser = Depends(get_current_user),
):
    repo = SQLOrderRepository(db)
    order = await repo.get_by_id(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")
    if user.role not in ("admin", "storeOwner") and order.user_id != user.uid:
        raise HTTPException(status_code=403, detail="Bu siparişi görüntüleme yetkiniz yok.")
    return _orm_to_schema(order)


@router.patch("/{order_id}/status", response_model=OrderOut)
async def update_order_status(
    order_id: str,
    body: OrderStatusUpdate,
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser = Depends(require_role("storeOwner", "admin")),
):
    repo = SQLOrderRepository(db)
    order = await repo.update_status(order_id, body.status)
    if not order:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")
    return _orm_to_schema(order)
