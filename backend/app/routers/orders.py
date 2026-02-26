"""
/api/v1/orders — sipariş oluşturma, listeleme, durum güncelleme
"""
from __future__ import annotations

import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import FirebaseUser, get_current_user, require_role
from app.core.database import get_db
from app.models.orm_models import OrderORM
from app.repositories.sql_repos import SQLOrderRepository
from app.schemas.schemas import (
    OrderCancelDecision,
    OrderCancelRequest,
    OrderCreate,
    OrderOut,
    OrderStatusUpdate,
)

router = APIRouter(prefix="/orders", tags=["Orders"])

CANCEL_TAG = "[[CANCEL_REQUEST]]:"


def _split_cancel_from_notes(notes: Optional[str]) -> tuple[Optional[str], bool, str]:
    if not notes:
        return None, False, ""
    raw = notes.strip()
    if not raw.startswith(CANCEL_TAG):
        return raw if raw else None, False, ""

    first_line, _, rest = raw.partition("\n")
    reason = first_line[len(CANCEL_TAG):].strip()
    user_note = rest.strip() if rest else ""
    return (user_note if user_note else None), True, reason


def _compose_notes(user_note: Optional[str], cancel_reason: Optional[str]) -> Optional[str]:
    base_note = (user_note or "").strip()
    reason = (cancel_reason or "").strip()
    if reason:
        return f"{CANCEL_TAG}{reason}\n{base_note}" if base_note else f"{CANCEL_TAG}{reason}"
    return base_note or None


def _orm_to_schema(o) -> OrderOut:
    restaurant_name = None
    try:
        if o.restaurant:
            restaurant_name = o.restaurant.name
    except Exception:
        pass
    plain_note, cancel_requested, cancel_reason = _split_cancel_from_notes(o.notes)
    return OrderOut(
        id=o.id,
        user_id=o.user_id,
        restaurant_id=o.restaurant_id,
        restaurant_name=restaurant_name,
        cancel_requested=cancel_requested,
        cancel_reason=cancel_reason,
        status=o.status,
        payment_method=o.payment_method,
        delivery_address=o.delivery_address,
        items=o.items or [],
        subtotal=o.subtotal or 0,
        delivery_fee=o.delivery_fee or 0,
        discount_amount=o.discount_amount or 0,
        total_amount=o.total_amount or 0,
        coupon_code=o.coupon_code,
        notes=plain_note,
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
    return [_orm_to_schema(o) for o in orders]


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


@router.post("/{order_id}/cancel-request", response_model=OrderOut)
async def request_cancel(
    order_id: str,
    body: OrderCancelRequest,
    db: AsyncSession = Depends(get_db),
    user: FirebaseUser = Depends(get_current_user),
):
    repo = SQLOrderRepository(db)
    order = await repo.get_by_id(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")
    if order.user_id != user.uid and user.role != "admin":
        raise HTTPException(status_code=403, detail="Bu sipariş için iptal talebi yetkiniz yok.")

    if order.status not in ("pending", "accepted", "preparing"):
        raise HTTPException(status_code=409, detail="Bu aşamadaki sipariş için iptal talebi oluşturulamaz.")

    plain_note, cancel_requested, _ = _split_cancel_from_notes(order.notes)
    if cancel_requested:
        raise HTTPException(status_code=409, detail="Bu sipariş için zaten iptal talebi var.")

    reason = body.reason.strip()
    if not reason:
        raise HTTPException(status_code=422, detail="İptal sebebi boş olamaz.")

    await db.execute(
        update(OrderORM)
        .where(OrderORM.id == order_id)
        .values(notes=_compose_notes(plain_note, reason))
    )
    updated = await repo.get_by_id(order_id)
    if not updated:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")
    return _orm_to_schema(updated)


@router.post("/{order_id}/cancel-request/decision", response_model=OrderOut)
async def decide_cancel_request(
    order_id: str,
    body: OrderCancelDecision,
    db: AsyncSession = Depends(get_db),
    _user: FirebaseUser = Depends(require_role("storeOwner", "admin")),
):
    repo = SQLOrderRepository(db)
    order = await repo.get_by_id(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")

    plain_note, cancel_requested, _ = _split_cancel_from_notes(order.notes)
    if not cancel_requested:
        raise HTTPException(status_code=409, detail="Bu sipariş için bekleyen iptal talebi yok.")

    if body.approve:
        await db.execute(
            update(OrderORM)
            .where(OrderORM.id == order_id)
            .values(status="cancelled", notes=plain_note)
        )
    else:
        await db.execute(
            update(OrderORM)
            .where(OrderORM.id == order_id)
            .values(notes=plain_note)
        )

    updated = await repo.get_by_id(order_id)
    if not updated:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")
    return _orm_to_schema(updated)
