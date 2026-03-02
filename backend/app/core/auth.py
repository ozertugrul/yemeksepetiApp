"""
JWT tabanlı kimlik doğrulama — Firebase bağımlılığı tamamen kaldırıldı.
Şifreler bcrypt ile hashlenir. Access token HS256 JWT'dir.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_db

bearer_scheme = HTTPBearer(auto_error=False)


# ── Model ──────────────────────────────────────────────────────────────────────

class CurrentUser:
    """Doğrulanmış kullanıcı. Tüm router'larda kullanılır."""

    def __init__(self, uid: str, email: Optional[str], role: str = "user"):
        self.uid = uid
        self.email = email
        self.role = role


# Geriye dönük uyumluluk
FirebaseUser = CurrentUser


# ── Password helpers ───────────────────────────────────────────────────────────

def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt(rounds=12)).decode()


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode(), hashed.encode())
    except Exception:
        return False


# ── JWT helpers ────────────────────────────────────────────────────────────────

def create_access_token(uid: str, email: str, role: str) -> str:
    settings = get_settings()
    expire = datetime.now(timezone.utc) + timedelta(days=settings.jwt_expire_days)
    payload = {
        "sub": uid,
        "email": email,
        "role": role,
        "exp": expire,
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def _decode_token(token: str) -> dict:
    settings = get_settings()
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token süresi dolmuş, lütfen tekrar giriş yapın.",
        )
    except jwt.InvalidTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Geçersiz token: {exc}",
        )


# ── FastAPI dependencies ───────────────────────────────────────────────────────

async def get_identity_only(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> CurrentUser:
    """Sadece token doğrular, DB'ye gitmez. /users/me bootstrap için."""
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header eksik",
        )
    payload = _decode_token(credentials.credentials)
    return CurrentUser(
        uid=payload.get("sub", ""),
        email=payload.get("email"),
        role=payload.get("role", "user"),
    )

# Geriye dönük uyumluluk alias
get_firebase_identity = get_identity_only


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> CurrentUser:
    """JWT doğrula → rolü DB'den oku."""
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header eksik",
        )
    payload = _decode_token(credentials.credentials)
    uid: str = payload.get("sub", "")
    email: Optional[str] = payload.get("email")

    from app.models.orm_models import UserORM
    try:
        result = await db.execute(select(UserORM.role).where(UserORM.id == uid))
    except (TimeoutError, SQLAlchemyError):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Veritabanı geçici olarak kullanılamıyor. Lütfen tekrar deneyin.",
        )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Kullanıcı hesabı bulunamadı.",
        )
    return CurrentUser(uid=uid, email=email, role=row)


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Optional[CurrentUser]:
    """Public endpoint'ler için — token yoksa None döner."""
    if not credentials:
        return None
    try:
        return await get_current_user(credentials, db)
    except HTTPException:
        return None


def require_role(*roles: str):
    """Role-based access control decorator factory."""
    async def _check(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Bu işlem için '{'/'.join(roles)}' rolü gerekli.",
            )
        return user
    return _check


# no-op — Firebase yoktu
def _init_firebase_app() -> None:
    pass
