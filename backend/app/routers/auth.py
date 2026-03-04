"""
/api/v1/auth — local email/password + JWT auth
"""
from __future__ import annotations

import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import (
    AuthenticatedUser,
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.core.database import get_db

router = APIRouter(prefix="/auth", tags=["Auth"])


class RegisterRequest(BaseModel):
    email: str
    password: str = Field(min_length=6)
    display_name: Optional[str] = None


class LoginRequest(BaseModel):
    email: str
    password: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=6)


class ChangeEmailRequest(BaseModel):
    current_password: str
    new_email: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    email: str
    role: str
    display_name: Optional[str] = None


def _token_response(*, user_id: str, email: str, role: str, display_name: Optional[str]) -> TokenResponse:
    token = create_access_token(uid=user_id, email=email, role=role)
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        user_id=user_id,
        email=email,
        role=role,
        display_name=display_name,
    )


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(
    body: RegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    email = body.email.lower().strip()
    existing = await db.execute(text("SELECT id FROM users WHERE email = :email"), {"email": email})
    if existing.first() is not None:
        raise HTTPException(status_code=409, detail="Bu e-posta zaten kayıtlı.")

    user_id = str(uuid.uuid4())
    display_name = (body.display_name or "").strip() or None
    await db.execute(
        text(
            """
            INSERT INTO users (id, email, password_hash, display_name, role)
            VALUES (:id, :email, :password_hash, :display_name, 'user')
            """
        ),
        {
            "id": user_id,
            "email": email,
            "password_hash": hash_password(body.password),
            "display_name": display_name,
        },
    )

    return _token_response(
        user_id=user_id,
        email=email,
        role="user",
        display_name=display_name,
    )


@router.post("/login", response_model=TokenResponse)
async def login(
    body: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    email = body.email.lower().strip()
    result = await db.execute(
        text(
            """
            SELECT id, email, role, display_name, password_hash
            FROM users
            WHERE email = :email
            """
        ),
        {"email": email},
    )
    row = result.mappings().first()
    if row is None:
        raise HTTPException(status_code=401, detail="E-posta veya şifre hatalı.")

    password_hash = (row.get("password_hash") or "").strip()
    if not password_hash or not verify_password(body.password, password_hash):
        raise HTTPException(status_code=401, detail="E-posta veya şifre hatalı.")

    return _token_response(
        user_id=str(row["id"]),
        email=str(row["email"]),
        role=str(row["role"]),
        display_name=row.get("display_name"),
    )


@router.post("/change-password", status_code=204)
async def change_password(
    body: ChangePasswordRequest,
    db: AsyncSession = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    result = await db.execute(
        text("SELECT password_hash FROM users WHERE id = :id"),
        {"id": current_user.uid},
    )
    row = result.mappings().first()
    if row is None or not row.get("password_hash"):
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")

    if not verify_password(body.current_password, str(row["password_hash"])):
        raise HTTPException(status_code=400, detail="Mevcut şifre hatalı.")

    await db.execute(
        text("UPDATE users SET password_hash = :password_hash, updated_at = NOW() WHERE id = :id"),
        {"password_hash": hash_password(body.new_password), "id": current_user.uid},
    )
    return None


@router.post("/change-email", response_model=TokenResponse)
async def change_email(
    body: ChangeEmailRequest,
    db: AsyncSession = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    user_result = await db.execute(
        text("SELECT id, role, display_name, password_hash FROM users WHERE id = :id"),
        {"id": current_user.uid},
    )
    user_row = user_result.mappings().first()
    if user_row is None or not user_row.get("password_hash"):
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")

    if not verify_password(body.current_password, str(user_row["password_hash"])):
        raise HTTPException(status_code=400, detail="Mevcut şifre hatalı.")

    normalized = body.new_email.lower().strip()
    existing = await db.execute(
        text("SELECT id FROM users WHERE email = :email AND id <> :id"),
        {"email": normalized, "id": current_user.uid},
    )
    if existing.first() is not None:
        raise HTTPException(status_code=409, detail="Bu e-posta başka bir hesapta kayıtlı.")

    await db.execute(
        text("UPDATE users SET email = :email, updated_at = NOW() WHERE id = :id"),
        {"email": normalized, "id": current_user.uid},
    )

    return _token_response(
        user_id=str(user_row["id"]),
        email=normalized,
        role=str(user_row["role"]),
        display_name=user_row.get("display_name"),
    )
