"""
PostgreSQL implementasyonları — SQLAlchemy Async ORM kullanır.
"""
from __future__ import annotations

import uuid
from typing import Any, List, Optional

from pgvector.sqlalchemy import Vector
from sqlalchemy import select, update, delete
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.orm_models import (
    MenuItemORM,
    OrderORM,
    RestaurantORM,
    UserAddressORM,
    UserORM,
    CouponORM,
)
from app.repositories.base import (
    AddressRepositoryBase,
    MenuItemRepositoryBase,
    OrderRepositoryBase,
    RestaurantRepositoryBase,
    UserRepositoryBase,
)


# ─────────────────────────────────────────────────────────────────────────────
# Restaurant
# ─────────────────────────────────────────────────────────────────────────────

class SQLRestaurantRepository(RestaurantRepositoryBase):
    def __init__(self, session: AsyncSession):
        self.db = session

    async def get_all_active(self, city: Optional[str] = None) -> List[RestaurantORM]:
        q = select(RestaurantORM).where(RestaurantORM.is_active == True)
        if city:
            q = q.where(RestaurantORM.city == city)
        result = await self.db.execute(q)
        return result.scalars().all()

    async def get_all(self) -> List[RestaurantORM]:
        result = await self.db.execute(select(RestaurantORM))
        return result.scalars().all()

    async def get_by_id(self, restaurant_id: str) -> Optional[RestaurantORM]:
        result = await self.db.execute(
            select(RestaurantORM)
            .options(selectinload(RestaurantORM.menu_items))
            .where(RestaurantORM.id == restaurant_id)
        )
        return result.scalar_one_or_none()

    async def get_by_owner(self, owner_id: str) -> Optional[RestaurantORM]:
        result = await self.db.execute(
            select(RestaurantORM)
            .options(selectinload(RestaurantORM.menu_items))
            .where(RestaurantORM.owner_id == owner_id)
        )
        return result.scalar_one_or_none()

    async def create(self, data: dict) -> RestaurantORM:
        if "id" not in data or not data["id"]:
            data["id"] = str(uuid.uuid4())
        obj = RestaurantORM(**data)
        self.db.add(obj)
        await self.db.flush()
        return obj

    async def update(self, restaurant_id: str, data: dict) -> Optional[RestaurantORM]:
        await self.db.execute(
            update(RestaurantORM)
            .where(RestaurantORM.id == restaurant_id)
            .values(**data)
        )
        return await self.get_by_id(restaurant_id)

    async def delete(self, restaurant_id: str) -> bool:
        result = await self.db.execute(
            delete(RestaurantORM).where(RestaurantORM.id == restaurant_id)
        )
        return result.rowcount > 0


# ─────────────────────────────────────────────────────────────────────────────
# MenuItem + pgvector
# ─────────────────────────────────────────────────────────────────────────────

class SQLMenuItemRepository(MenuItemRepositoryBase):
    def __init__(self, session: AsyncSession):
        self.db = session

    async def get_by_restaurant(self, restaurant_id: str) -> List[MenuItemORM]:
        result = await self.db.execute(
            select(MenuItemORM).where(MenuItemORM.restaurant_id == restaurant_id)
        )
        return result.scalars().all()

    async def get_by_id(self, item_id: str) -> Optional[MenuItemORM]:
        result = await self.db.execute(
            select(MenuItemORM).where(MenuItemORM.id == item_id)
        )
        return result.scalar_one_or_none()

    async def upsert(self, data: dict) -> MenuItemORM:
        if "id" not in data or not data["id"]:
            data["id"] = str(uuid.uuid4())
        existing = await self.get_by_id(data["id"])
        if existing:
            for k, v in data.items():
                setattr(existing, k, v)
            return existing
        obj = MenuItemORM(**data)
        self.db.add(obj)
        await self.db.flush()
        return obj

    async def update_embedding(self, item_id: str, embedding: list) -> None:
        await self.db.execute(
            update(MenuItemORM)
            .where(MenuItemORM.id == item_id)
            .values(embedding=embedding)
        )

    async def find_similar(
        self,
        embedding: list,
        restaurant_id: Optional[str],
        top_k: int = 10,
    ) -> List[Any]:
        """
        pgvector cosine distance ile en yakın menu_items'ı döndür.
        <=> operatörü cosine distance (küçük = daha benzer).
        """
        q = (
            select(
                MenuItemORM,
                MenuItemORM.embedding.cosine_distance(embedding).label("distance"),
            )
            .where(MenuItemORM.embedding.isnot(None))
            .where(MenuItemORM.is_available == True)
        )
        if restaurant_id:
            q = q.where(MenuItemORM.restaurant_id == restaurant_id)

        q = q.order_by("distance").limit(top_k)
        result = await self.db.execute(q)
        rows = result.all()
        # (ORM, distance) → (ORM, similarity_score)
        return [(row[0], 1 - row[1]) for row in rows]


# ─────────────────────────────────────────────────────────────────────────────
# Order
# ─────────────────────────────────────────────────────────────────────────────

class SQLOrderRepository(OrderRepositoryBase):
    def __init__(self, session: AsyncSession):
        self.db = session

    async def create(self, data: dict) -> OrderORM:
        if "id" not in data or not data["id"]:
            data["id"] = str(uuid.uuid4())
        obj = OrderORM(**data)
        self.db.add(obj)
        await self.db.flush()
        return obj

    async def get_by_user(self, user_id: str) -> List[OrderORM]:
        result = await self.db.execute(
            select(OrderORM)
            .where(OrderORM.user_id == user_id)
            .order_by(OrderORM.created_at.desc())
        )
        return result.scalars().all()

    async def get_by_restaurant(self, restaurant_id: str) -> List[OrderORM]:
        result = await self.db.execute(
            select(OrderORM)
            .where(OrderORM.restaurant_id == restaurant_id)
            .order_by(OrderORM.created_at.desc())
        )
        return result.scalars().all()

    async def get_by_id(self, order_id: str) -> Optional[OrderORM]:
        result = await self.db.execute(
            select(OrderORM).where(OrderORM.id == order_id)
        )
        return result.scalar_one_or_none()

    async def update_status(self, order_id: str, status: str) -> Optional[OrderORM]:
        await self.db.execute(
            update(OrderORM)
            .where(OrderORM.id == order_id)
            .values(status=status)
        )
        return await self.get_by_id(order_id)


# ─────────────────────────────────────────────────────────────────────────────
# User
# ─────────────────────────────────────────────────────────────────────────────

class SQLUserRepository(UserRepositoryBase):
    def __init__(self, session: AsyncSession):
        self.db = session

    async def get_by_id(self, user_id: str) -> Optional[UserORM]:
        result = await self.db.execute(
            select(UserORM).where(UserORM.id == user_id)
        )
        return result.scalar_one_or_none()

    async def upsert(self, data: dict) -> UserORM:
        existing = await self.get_by_id(data["id"])
        if existing:
            for k, v in data.items():
                if v is not None:
                    setattr(existing, k, v)
            return existing
        obj = UserORM(**data)
        self.db.add(obj)
        await self.db.flush()
        return obj

    async def update(self, user_id: str, data: dict) -> Optional[UserORM]:
        await self.db.execute(
            update(UserORM).where(UserORM.id == user_id).values(**data)
        )
        return await self.get_by_id(user_id)


# ─────────────────────────────────────────────────────────────────────────────
# Address
# ─────────────────────────────────────────────────────────────────────────────

class SQLAddressRepository(AddressRepositoryBase):
    def __init__(self, session: AsyncSession):
        self.db = session

    async def get_by_user(self, user_id: str) -> List[UserAddressORM]:
        result = await self.db.execute(
            select(UserAddressORM).where(UserAddressORM.user_id == user_id)
        )
        return result.scalars().all()

    async def create(self, data: dict) -> UserAddressORM:
        if "id" not in data or not data["id"]:
            data["id"] = str(uuid.uuid4())
        obj = UserAddressORM(**data)
        self.db.add(obj)
        await self.db.flush()
        return obj

    async def update(self, address_id: str, data: dict) -> Optional[UserAddressORM]:
        await self.db.execute(
            update(UserAddressORM)
            .where(UserAddressORM.id == address_id)
            .values(**data)
        )
        result = await self.db.execute(
            select(UserAddressORM).where(UserAddressORM.id == address_id)
        )
        return result.scalar_one_or_none()

    async def delete(self, address_id: str) -> bool:
        result = await self.db.execute(
            delete(UserAddressORM).where(UserAddressORM.id == address_id)
        )
        return result.rowcount > 0
