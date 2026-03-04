"""
/api/v1/users — kullanıcı profili + adres yönetimi
"""
from __future__ import annotations

from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import AuthenticatedUser, get_current_user
from app.core.database import get_db
from app.models.orm_models import UserAddressORM
from app.repositories.sql_repos import SQLAddressRepository, SQLUserRepository
from app.schemas.schemas import UserAddressCreate, UserAddressOut, UserOut

router = APIRouter(prefix="/users", tags=["Users"])


# ── Profil ────────────────────────────────────────────────────────────────────

@router.get("/me", response_model=UserOut)
async def get_me(
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    repo = SQLUserRepository(db)
    u = await repo.get_by_id(user.uid)
    if not u:
        # Token geçerli ama DB'de kullanıcı yoksa otomatik oluştur
        u = await repo.upsert({
            "id": user.uid,
            "email": user.email or f"{user.uid}@unknown.user",
            "role": "user",
        })
    return UserOut(
        id=u.id, email=u.email, display_name=u.display_name,
        role=u.role, city=u.city, phone=u.phone,
        managed_restaurant_id=u.managed_restaurant_id,
    )


@router.put("/me", response_model=UserOut)
async def update_me(
    body: dict,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    allowed = {"display_name", "city", "phone"}
    data = {k: v for k, v in body.items() if k in allowed}
    repo = SQLUserRepository(db)
    u = await repo.update(user.uid, data)
    if not u:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
    return UserOut(
        id=u.id, email=u.email, display_name=u.display_name,
        role=u.role, city=u.city, phone=u.phone,
        managed_restaurant_id=u.managed_restaurant_id,
    )


# ── Adresler ──────────────────────────────────────────────────────────────────

@router.get("/me/addresses", response_model=List[UserAddressOut])
async def list_addresses(
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    repo = SQLAddressRepository(db)
    addresses = await repo.get_by_user(user.uid)
    return [_addr_schema(a) for a in addresses]


@router.post("/me/addresses", response_model=UserAddressOut, status_code=201)
async def create_address(
    body: UserAddressCreate,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    data = body.model_dump(by_alias=False)
    data["user_id"] = user.uid
    # Yeni adres varsayılan yapılacaksa diğerlerini sıfırla
    if data.get("is_default"):
        addr_repo = SQLAddressRepository(db)
        existing = await addr_repo.get_by_user(user.uid)
        for a in existing:
            if a.is_default:
                await addr_repo.update(a.id, {"is_default": False})
    repo = SQLAddressRepository(db)
    addr = await repo.create(data)
    return _addr_schema(addr)


@router.put("/me/addresses/{address_id}", response_model=UserAddressOut)
async def update_address(
    address_id: str,
    body: UserAddressCreate,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    repo = SQLAddressRepository(db)
    data = body.model_dump(by_alias=False, exclude_unset=True)
    data.pop("id", None)
    addr = await repo.update(address_id, data)
    if not addr or addr.user_id != user.uid:
        raise HTTPException(status_code=404, detail="Adres bulunamadı.")
    return _addr_schema(addr)


@router.delete("/me/addresses/{address_id}", status_code=204)
async def delete_address(
    address_id: str,
    db: AsyncSession = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    repo = SQLAddressRepository(db)

    result = await db.execute(select(UserAddressORM).where(UserAddressORM.id == address_id))
    address = result.scalar_one_or_none()
    if not address or address.user_id != user.uid:
        raise HTTPException(status_code=404, detail="Adres bulunamadı.")

    deleted = await repo.delete(address_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Adres bulunamadı.")


def _addr_schema(a) -> UserAddressOut:
    return UserAddressOut(
        id=a.id, user_id=a.user_id, title=a.title,
        city=a.city or "", district=a.district or "",
        neighborhood=a.neighborhood or "", street=a.street or "",
        building_no=a.building_no or "", flat_no=a.flat_no or "",
        directions=a.directions or "", is_default=a.is_default or False,
        phone=a.phone or "", latitude=a.latitude, longitude=a.longitude,
    )
