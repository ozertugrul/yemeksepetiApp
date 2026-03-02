"""
SQLAlchemy ORM modelleri — SQL şemasıyla birebir eşleşir.
pgvector tip: from pgvector.sqlalchemy import Vector
"""
from datetime import datetime
from typing import Optional

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    Boolean, Column, DateTime, Double, ForeignKey,
    Integer, String, Text, func,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import relationship

from app.core.database import Base


class UserORM(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True)          # UUID (kendi ürettiğimiz)
    email = Column(String, unique=True, nullable=False)
    password_hash = Column(String, nullable=True)  # bcrypt hash — eski kayıtlar NULL olabilir
    display_name = Column(String)
    role = Column(String, nullable=False, default="user")
    city = Column(String)
    phone = Column(String)
    managed_restaurant_id = Column(String)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    addresses = relationship("UserAddressORM", back_populates="user", cascade="all, delete-orphan")
    orders = relationship("OrderORM", back_populates="user")


class RestaurantORM(Base):
    __tablename__ = "restaurants"

    id = Column(String, primary_key=True)
    owner_id = Column(String, ForeignKey("users.id"), nullable=True)
    name = Column(String, nullable=False)
    description = Column(Text)
    cuisine_type = Column(String)
    image_url = Column(String)
    rating = Column(Double, default=0)
    delivery_time = Column(String)
    min_order_amount = Column(Double, default=0)
    is_active = Column(Boolean, default=True)
    city = Column(String)
    allows_pickup = Column(Boolean, default=False)
    allows_cash_on_del = Column(Boolean, default=False)
    successful_order_count = Column(Integer, default=0)
    average_rating = Column(Double, default=0)
    rating_count = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    menu_items = relationship("MenuItemORM", back_populates="restaurant", cascade="all, delete-orphan")
    orders = relationship("OrderORM", back_populates="restaurant")


class MenuItemORM(Base):
    __tablename__ = "menu_items"

    id = Column(String, primary_key=True)
    restaurant_id = Column(String, ForeignKey("restaurants.id", ondelete="CASCADE"), nullable=False)
    name = Column(String, nullable=False)
    description = Column(Text)
    price = Column(Double, nullable=False)
    image_url = Column(String)
    category = Column(String, default="Diğer")
    discount_percent = Column(Double, default=0)
    is_available = Column(Boolean, default=True)
    option_groups = Column(JSONB, default=list)
    suggested_ids = Column(ARRAY(String), default=list)
    # pgvector: ozertuu/yemeksepeti-MiniLM-L12-v2 → 384 boyut
    embedding = Column(Vector(384), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    restaurant = relationship("RestaurantORM", back_populates="menu_items")


class UserAddressORM(Base):
    __tablename__ = "user_addresses"

    id = Column(String, primary_key=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title = Column(String, nullable=False)
    city = Column(String)
    district = Column(String)
    neighborhood = Column(String)
    street = Column(String)
    building_no = Column(String)
    flat_no = Column(String)
    directions = Column(String)
    is_default = Column(Boolean, default=False)
    phone = Column(String)
    latitude = Column(Double)
    longitude = Column(Double)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("UserORM", back_populates="addresses")


class OrderORM(Base):
    __tablename__ = "orders"

    id = Column(String, primary_key=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    restaurant_id = Column(String, ForeignKey("restaurants.id"), nullable=False)
    status = Column(String, nullable=False, default="pending")
    payment_method = Column(String, nullable=False)
    delivery_address = Column(JSONB)
    items = Column(JSONB, nullable=False, default=list)
    subtotal = Column(Double, default=0)
    delivery_fee = Column(Double, default=0)
    discount_amount = Column(Double, default=0)
    total_amount = Column(Double, default=0)
    coupon_code = Column(String)
    notes = Column(Text)
    is_rated = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user = relationship("UserORM", back_populates="orders")
    restaurant = relationship("RestaurantORM", back_populates="orders")


class CouponORM(Base):
    __tablename__ = "coupons"

    id = Column(String, primary_key=True)
    restaurant_id = Column(String, ForeignKey("restaurants.id"), nullable=True)
    code = Column(String, unique=True, nullable=False)
    description = Column(Text)
    discount_amount = Column(Double, default=0)
    discount_percent = Column(Double, default=0)
    minimum_order_amount = Column(Double, default=0)
    expiry_date = Column(DateTime(timezone=True), nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
