"""
/api/v1/admin — Admin-only kullanıcı ve sistem yönetimi
"""
from __future__ import annotations

from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import FirebaseUser, require_role
from app.core.database import get_db
from app.repositories.sql_repos import SQLUserRepository
from app.schemas.schemas import UserOut

router = APIRouter(prefix="/admin", tags=["Admin"])


def _user_schema(u) -> UserOut:
    return UserOut(
        id=u.id, email=u.email, display_name=u.display_name,
        role=u.role, city=u.city, phone=u.phone,
        managed_restaurant_id=u.managed_restaurant_id,
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


# ── Kullanıcı Sil (ban) ───────────────────────────────────────────────────────

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
