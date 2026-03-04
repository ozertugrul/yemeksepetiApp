"""
Pydantic şemaları — API request / response modelleri.
iOS Swift modelleriyle birebir alan adı eşleşmesi (camelCase → snake_case alias).
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, List, Optional
from pydantic import BaseModel, ConfigDict, Field


# ── Ortak ─────────────────────────────────────────────────────────────────────

class CamelModel(BaseModel):
    """camelCase alias üreten base model (iOS JSON uyumluluğu)."""
    model_config = ConfigDict(
        populate_by_name=True,
        alias_generator=lambda s: "".join(
            w.capitalize() if i else w for i, w in enumerate(s.split("_"))
        ),
    )


# ── MenuItemOption / OptionGroup ──────────────────────────────────────────────

class MenuItemOption(CamelModel):
    id: str
    name: str
    extra_price: float = 0
    is_default: bool = False


class MenuItemOptionGroup(CamelModel):
    id: str
    name: str
    type: str = "singleSelect"
    is_required: bool = False
    min_selections: int = 0
    max_selections: int = 1
    options: List[MenuItemOption] = []


# ── MenuItem ──────────────────────────────────────────────────────────────────

class MenuItemBase(CamelModel):
    name: str
    description: str = ""
    price: float
    image_url: Optional[str] = None
    category: str = "Diğer"
    discount_percent: float = 0
    is_available: bool = True
    option_groups: List[MenuItemOptionGroup] = []
    suggested_ids: List[str] = []


class MenuItemCreate(MenuItemBase):
    id: Optional[str] = None
    restaurant_id: str


class MenuItemOut(MenuItemBase):
    id: str
    restaurant_id: str
    created_at: Optional[datetime] = None


# ── Restaurant ────────────────────────────────────────────────────────────────

class RestaurantBase(CamelModel):
    name: str
    description: str = ""
    cuisine_type: str = ""
    image_url: Optional[str] = None
    rating: float = 0
    delivery_time: str = ""
    min_order_amount: float = 0
    is_active: bool = True
    city: Optional[str] = None
    allows_pickup: bool = False
    allows_cash_on_delivery: bool = Field(False, alias="allowsCashOnDelivery")
    successful_order_count: int = 0
    average_rating: float = 0
    rating_count: int = 0


class RestaurantCreate(RestaurantBase):
    id: Optional[str] = None
    owner_id: Optional[str] = None


class RestaurantOut(RestaurantBase):
    id: str
    owner_id: Optional[str] = None
    menu: List[MenuItemOut] = []
    created_at: Optional[datetime] = None


# ── UserAddress ───────────────────────────────────────────────────────────────

class UserAddressBase(CamelModel):
    title: str
    city: str = ""
    district: str = ""
    neighborhood: str = ""
    street: str = ""
    building_no: str = ""
    flat_no: str = ""
    directions: str = ""
    is_default: bool = False
    phone: str = ""
    latitude: Optional[float] = None
    longitude: Optional[float] = None


class UserAddressCreate(UserAddressBase):
    id: Optional[str] = None


class UserAddressOut(UserAddressBase):
    id: str
    user_id: str


# ── Order ─────────────────────────────────────────────────────────────────────

class SelectedOptionGroupSchema(CamelModel):
    id: str
    group_name: str
    selected_options: List[str]
    extra_total: float = 0


class OrderItemSchema(CamelModel):
    id: str
    menu_item_id: str
    name: str
    unit_price: float
    quantity: int
    selected_option_groups: List[SelectedOptionGroupSchema] = []
    option_extras_per_unit: float = 0
    image_url: Optional[str] = None


class OrderCreate(CamelModel):
    restaurant_id: str
    payment_method: str
    delivery_address: Optional[UserAddressBase] = None
    items: List[OrderItemSchema]
    subtotal: float
    delivery_fee: float = 0
    discount_amount: float = 0
    total_amount: float
    coupon_code: Optional[str] = None
    notes: Optional[str] = None


class OrderStatusUpdate(CamelModel):
    status: str


class OrderCancelRequest(CamelModel):
    reason: str


class OrderCancelDecision(CamelModel):
    approve: bool


class OrderOut(CamelModel):
    id: str
    user_id: str
    restaurant_id: str
    restaurant_name: Optional[str] = None
    cancel_requested: bool = False
    cancel_reason: str = ""
    status: str
    payment_method: str
    delivery_address: Optional[Any] = None
    items: List[OrderItemSchema]
    subtotal: float
    delivery_fee: float
    discount_amount: float
    total_amount: float
    coupon_code: Optional[str] = None
    notes: Optional[str] = None
    is_rated: bool = False
    created_at: Optional[datetime] = None


class OrderReviewCreate(CamelModel):
    speed_rating: float = Field(..., ge=1, le=5)
    taste_rating: float = Field(..., ge=1, le=5)
    presentation_rating: float = Field(..., ge=1, le=5)
    comment: str = ""


class OrderReviewReply(CamelModel):
    reply: str


class OrderReviewOut(CamelModel):
    id: str
    order_id: str
    restaurant_id: str
    user_id: str
    user_display_name: Optional[str] = None
    speed_rating: float
    taste_rating: float
    presentation_rating: float
    average_rating: float
    comment: str = ""
    owner_reply: Optional[str] = None
    owner_replied_at: Optional[datetime] = None
    created_at: Optional[datetime] = None


# ── Coupon ───────────────────────────────────────────────────────────────────

class CouponUpsert(CamelModel):
    id: Optional[str] = None
    restaurant_id: Optional[str] = None
    code: str
    description: str = ""
    discount_amount: float = Field(0, ge=0)
    discount_percent: float = Field(0, ge=0, le=100)
    minimum_order_amount: float = Field(0, ge=0)
    expiry_date: Optional[datetime] = None
    is_active: bool = True
    is_public: bool = False
    city: Optional[str] = None


class CouponOut(CamelModel):
    id: str
    restaurant_id: Optional[str] = None
    code: str
    description: str = ""
    discount_amount: float = 0
    discount_percent: float = 0
    minimum_order_amount: float = 0
    expiry_date: Optional[datetime] = None
    is_active: bool = True
    is_public: bool = False
    city: Optional[str] = None
    restaurant_name: Optional[str] = None
    created_at: Optional[datetime] = None


# ── Recommendation ────────────────────────────────────────────────────────────

class RecommendationQuery(CamelModel):
    query: str                    # Serbest metin: "acı burger yanına patates"
    restaurant_id: Optional[str] = None
    top_k: int = 10


class MenuItemRecommendation(CamelModel):
    score: float                  # cosine similarity (0-1)
    item: MenuItemOut


class RecommendationOut(CamelModel):
    query: str
    results: List[MenuItemRecommendation]


# ── Unified Search ───────────────────────────────────────────────────────────

class SearchResultEntity(CamelModel):
    id: str
    entity_type: str                      # "store" | "menu"
    title: str
    subtitle: Optional[str] = None
    restaurant_id: Optional[str] = None
    restaurant_name: Optional[str] = None
    image_url: Optional[str] = None
    price: Optional[float] = None
    rating: Optional[float] = None
    score: float


class UnifiedSearchOut(CamelModel):
    query: str
    stores: List[SearchResultEntity] = []
    menu_items: List[SearchResultEntity] = []
    similar_menu_items: List[SearchResultEntity] = []
    next_offset: Optional[int] = None
    has_more: bool = False


# ── CF (Collaborative Filtering) Öneri ────────────────────────────────────────

class CFMenuItemOut(CamelModel):
    """CF önerisindeki menü öğesi — restoran adı dahil."""
    id: str
    restaurant_id: str
    name: str
    description: str = ""
    price: float
    image_url: Optional[str] = None
    category: str = "Diğer"
    discount_percent: float = 0
    is_available: bool = True
    option_groups: List[Any] = []
    suggested_ids: List[str] = []
    restaurant_name: Optional[str] = None
    created_at: Optional[datetime] = None


class CFRecommendationItem(CamelModel):
    """Tek bir CF önerisi."""
    score: float           # 0-1 arası normalize skor
    source: str            # "cf" | "popular"
    supporters: int        # bu ürünü alan benzer kullanıcı sayısı
    item: CFMenuItemOut


class CFRecommendationOut(CamelModel):
    """CF önerileri endpoint cevabı."""
    time_segment: str          # "breakfast" | "lunch" | …
    label: str                 # "Öğle Yemeği" (TR gösterim)
    items: List[CFRecommendationItem] = []


# ── User ──────────────────────────────────────────────────────────────────────

class UserOut(CamelModel):
    id: str
    email: Optional[str] = None
    display_name: Optional[str] = None
    role: str = "user"
    city: Optional[str] = None
    phone: Optional[str] = None
    managed_restaurant_id: Optional[str] = None
