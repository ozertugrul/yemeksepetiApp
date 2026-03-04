"""
/api/v1/orders — sipariş oluşturma, listeleme, durum güncelleme
"""
from __future__ import annotations

import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import AuthenticatedUser, get_current_user, require_role
from app.core.database import get_db
from app.models.orm_models import OrderORM, OrderReviewORM, RestaurantORM
from app.repositories.sql_repos import SQLOrderRepository, SQLRestaurantRepository, SQLUserRepository
from app.schemas.schemas import (
    OrderReviewCreate,
    OrderReviewOut,
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


def _review_to_schema(r: OrderReviewORM, user_display_name: Optional[str] = None) -> OrderReviewOut:
    return OrderReviewOut(
        id=r.id,
        order_id=r.order_id,
        restaurant_id=r.restaurant_id,
        user_id=r.user_id,
        user_display_name=user_display_name,
        speed_rating=r.speed_rating,
        taste_rating=r.taste_rating,
        presentation_rating=r.presentation_rating,
        average_rating=r.average_rating,
        comment=r.comment or "",
        owner_reply=r.owner_reply,
        owner_replied_at=r.owner_replied_at,
        created_at=r.created_at,
    )


async def _assert_owner_or_admin(
    db: AsyncSession,
    user: AuthenticatedUser,
    restaurant_id: str,
) -> None:
    if user.role == "admin":
        return
    if user.role != "storeOwner":
        raise HTTPException(status_code=403, detail="Bu işlem için yetkiniz yok.")

    rest_repo = SQLRestaurantRepository(db)
    user_repo = SQLUserRepository(db)
    restaurant = await rest_repo.get_by_id(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restoran bulunamadı.")

    db_user = await user_repo.get_by_id(user.uid)
    is_primary_owner = restaurant.owner_id == user.uid
    is_co_owner = bool(db_user and db_user.managed_restaurant_id == restaurant_id)
    if not (is_primary_owner or is_co_owner):
        raise HTTPException(status_code=403, detail="Bu restoranın siparişlerini yönetme yetkiniz yok.")


async def _refresh_restaurant_rating(db: AsyncSession, restaurant_id: str) -> None:
    avg_q = await db.execute(
        select(func.coalesce(func.avg(OrderReviewORM.average_rating), 0.0), func.count(OrderReviewORM.id))
        .where(OrderReviewORM.restaurant_id == restaurant_id)
    )
    avg_rating, rating_count = avg_q.one()
    await db.execute(
        update(RestaurantORM)
        .where(RestaurantORM.id == restaurant_id)
        .values(
            average_rating=float(avg_rating or 0.0),
            rating_count=int(rating_count or 0),
        )
    )


@router.post("", response_model=OrderOut, status_code=status.HTTP_201_CREATED)
async def create_order(
    body: OrderCreate,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
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
    user: AuthenticatedUser = Depends(get_current_user),
):
    repo = SQLOrderRepository(db)
    orders = await repo.get_by_user(user.uid)
    return [_orm_to_schema(o) for o in orders]


@router.get("/restaurant/{restaurant_id}", response_model=List[OrderOut])
async def restaurant_orders(
    restaurant_id: str,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(require_role("storeOwner", "admin")),
):
    await _assert_owner_or_admin(db, user, restaurant_id)
    repo = SQLOrderRepository(db)
    orders = await repo.get_by_restaurant(restaurant_id)
    return [_orm_to_schema(o) for o in orders]


@router.get("/{order_id}", response_model=OrderOut)
async def get_order(
    order_id: str,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    repo = SQLOrderRepository(db)
    order = await repo.get_by_id(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")
    if user.role == "admin":
        return _orm_to_schema(order)
    if user.role == "storeOwner":
        await _assert_owner_or_admin(db, user, order.restaurant_id)
        return _orm_to_schema(order)
    if order.user_id != user.uid:
        raise HTTPException(status_code=403, detail="Bu siparişi görüntüleme yetkiniz yok.")
    return _orm_to_schema(order)


@router.patch("/{order_id}/status", response_model=OrderOut)
async def update_order_status(
    order_id: str,
    body: OrderStatusUpdate,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(require_role("storeOwner", "admin")),
):
    repo = SQLOrderRepository(db)
    existing = await repo.get_by_id(order_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")
    await _assert_owner_or_admin(db, user, existing.restaurant_id)

    order = await repo.update_status(order_id, body.status)
    if not order:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")
    return _orm_to_schema(order)


@router.post("/{order_id}/cancel-request", response_model=OrderOut)
async def request_cancel(
    order_id: str,
    body: OrderCancelRequest,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
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
    user: AuthenticatedUser = Depends(require_role("storeOwner", "admin")),
):
    repo = SQLOrderRepository(db)
    order = await repo.get_by_id(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")
    await _assert_owner_or_admin(db, user, order.restaurant_id)

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


@router.post("/{order_id}/review", response_model=OrderReviewOut, status_code=status.HTTP_201_CREATED)
async def submit_order_review(
    order_id: str,
    body: OrderReviewCreate,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    repo = SQLOrderRepository(db)
    order = await repo.get_by_id(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Sipariş bulunamadı.")
    if order.user_id != user.uid and user.role != "admin":
        raise HTTPException(status_code=403, detail="Bu siparişi değerlendirme yetkiniz yok.")
    if order.status != "completed":
        raise HTTPException(status_code=409, detail="Sadece tamamlanan siparişler değerlendirilebilir.")

    existing = await db.execute(select(OrderReviewORM).where(OrderReviewORM.order_id == order_id))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Bu sipariş zaten değerlendirilmiş.")

    avg_rating = (body.speed_rating + body.taste_rating + body.presentation_rating) / 3.0
    review = OrderReviewORM(
        id=str(uuid.uuid4()),
        order_id=order_id,
        restaurant_id=order.restaurant_id,
        user_id=order.user_id,
        speed_rating=body.speed_rating,
        taste_rating=body.taste_rating,
        presentation_rating=body.presentation_rating,
        average_rating=avg_rating,
        comment=body.comment.strip(),
    )
    db.add(review)

    await db.execute(
        update(OrderORM)
        .where(OrderORM.id == order_id)
        .values(is_rated=True)
    )

    await _refresh_restaurant_rating(db, order.restaurant_id)
    await db.flush()
    return _review_to_schema(review)
