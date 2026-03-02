"""
/api/v1/auth — Kayıt, giriş, token yenileme.
Firebase bağımlılığı yok — tamamen kendi JWT sistemi.
"""
from __future__ import annotations

import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import (
    CurrentUser,
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.core.database import get_db
from app.models.orm_models import UserORM

router = APIRouter(prefix="/auth", tags=["Auth"])


# ── Schemas ────────────────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)
    display_name: Optional[str] = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=6)


class ChangeEmailRequest(BaseModel):
    new_email: EmailStr
    current_password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    email: str
    role: str
    display_name: Optional[str] = None


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.post("/register", response_model=TokenResponse, status_code=201)
async def register(body: RegisterRequest, db: AsyncSession = Depends(get_db)):
    """Yeni kullanıcı kaydı — email/şifre ile."""
    # Duplicate kontrol
    try:
        existing = await db.execute(select(UserORM).where(UserORM.email == body.email))
    except (TimeoutError, SQLAlchemyError):
        raise HTTPException(status_code=503, detail="Veritabanı geçici olarak kullanılamıyor.")
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Bu e-posta adresi zaten kayıtlı.")

    uid = str(uuid.uuid4())
    user = UserORM(
        id=uid,
        email=body.email,
        display_name=body.display_name,
        role="user",
        password_hash=hash_password(body.password),
    )
    db.add(user)
    try:
        await db.commit()
        await db.refresh(user)
    except SQLAlchemyError as exc:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Kayıt hatası: {exc}")

    token = create_access_token(uid=uid, email=body.email, role="user")
    return TokenResponse(
        access_token=token,
        user_id=uid,
        email=body.email,
        role="user",
        display_name=body.display_name,
    )


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Email/şifre ile giriş — JWT döner."""
    try:
        result = await db.execute(select(UserORM).where(UserORM.email == body.email))
    except (TimeoutError, SQLAlchemyError):
        raise HTTPException(status_code=503, detail="Veritabanı geçici olarak kullanılamıyor.")

    user = result.scalar_one_or_none()
    if not user or not user.password_hash or not verify_password(body.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="E-posta veya şifre hatalı.",
        )

    token = create_access_token(uid=user.id, email=user.email, role=user.role)
    return TokenResponse(
        access_token=token,
        user_id=user.id,
        email=user.email,
        role=user.role,
        display_name=user.display_name,
    )


@router.post("/change-password", status_code=204)
async def change_password(
    body: ChangePasswordRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
):
    """Şifre değiştir — mevcut şifreyi doğruladıktan sonra."""
    result = await db.execute(select(UserORM).where(UserORM.id == current_user.uid))
    user = result.scalar_one_or_none()
    if not user or not user.password_hash or not verify_password(body.current_password, user.password_hash):
        raise HTTPException(status_code=401, detail="Mevcut şifre hatalı.")
    user.password_hash = hash_password(body.new_password)
    await db.commit()


@router.post("/change-email", response_model=TokenResponse)
async def change_email(
    body: ChangeEmailRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
):
    """E-posta güncelle — mevcut şifreyi doğruladıktan sonra."""
    result = await db.execute(select(UserORM).where(UserORM.id == current_user.uid))
    user = result.scalar_one_or_none()
    if not user or not user.password_hash or not verify_password(body.current_password, user.password_hash):
        raise HTTPException(status_code=401, detail="Mevcut şifre hatalı.")

    dup = await db.execute(select(UserORM.id).where(UserORM.email == body.new_email))
    if dup.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Bu e-posta zaten kullanılıyor.")

    user.email = body.new_email
    await db.commit()
    await db.refresh(user)
    token = create_access_token(uid=user.id, email=user.email, role=user.role)
    return TokenResponse(
        access_token=token,
        user_id=user.id,
        email=user.email,
        role=user.role,
        display_name=user.display_name,
    )
