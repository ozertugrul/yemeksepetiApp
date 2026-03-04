"""
JWT tabanlı kimlik doğrulama.

iOS tarafı her istekte Authorization: Bearer <access_token> header'ı gönderir.
"""
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


def _jwt_secret() -> str:
    settings = get_settings()
    secret = (settings.jwt_secret or settings.jwt_secret_key or "").strip()
    if not secret or secret == "change-this-jwt-secret" or len(secret) < 32:
        raise RuntimeError("JWT secret güvenli şekilde yapılandırılmamış.")
    return secret


class AuthenticatedUser:
    def __init__(self, uid: str, email: Optional[str], role: Optional[str] = None):
        self.uid = uid
        self.email = email
        self.role = role or "user"


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except Exception:
        return False


def create_access_token(uid: str, email: str, role: str) -> str:
    settings = get_settings()
    try:
        secret = _jwt_secret()
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Kimlik doğrulama servisi geçici olarak kullanılamıyor.",
        ) from exc
    now = datetime.now(timezone.utc)
    payload = {
        "sub": uid,
        "email": email,
        "role": role,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=settings.jwt_expire_minutes)).timestamp()),
    }
    return jwt.encode(payload, secret, algorithm=settings.jwt_algorithm)


def _decode_access_token(token: str) -> dict:
    settings = get_settings()
    try:
        secret = _jwt_secret()
    except RuntimeError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Kimlik doğrulama servisi geçici olarak kullanılamıyor.",
        )
    try:
        return jwt.decode(token, secret, algorithms=[settings.jwt_algorithm])
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Oturum süresi doldu. Lütfen tekrar giriş yapın.",
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Geçersiz erişim token'ı.",
        )


async def get_bearer_identity(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> AuthenticatedUser:
    """
    Bearer token'ı JWT ile doğrula.
    DB rol kontrolü yapmaz; bootstrap endpoint'lerde kullanılabilir.
    """
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header eksik",
        )
    decoded = _decode_access_token(credentials.credentials)

    uid = decoded.get("sub")
    email = decoded.get("email")
    role = decoded.get("role") or "user"
    if not uid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token içinde kullanıcı bilgisi eksik.",
        )

    return AuthenticatedUser(uid=uid, email=email, role=role)


async def get_current_user(
    identity: AuthenticatedUser = Depends(get_bearer_identity),
    db: AsyncSession = Depends(get_db),
) -> AuthenticatedUser:
    """
    Bearer token'ı JWT ile doğrula, ardından rolü PostgreSQL'den oku.
    Geçersiz/eksik token → 401.
    """
    uid = identity.uid
    email = identity.email

    # Rolü her zaman PostgreSQL'den oku — ORM select() kullan:
    # text()+named-param yaklaşımı asyncpg'de prepared statement üretiyor,
    # PgBouncer transaction-mode ile çakışıyor → ORM select saha testiyle daha güvenli.
    from app.models.orm_models import UserORM
    try:
        result = await db.execute(
            select(UserORM.role).where(UserORM.id == uid)
        )
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
    role = row

    return AuthenticatedUser(uid=uid, email=email, role=role)


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Optional[AuthenticatedUser]:
    """Public endpoint'ler için — token yoksa None döner, hata fırlatmaz."""
    if not credentials:
        return None
    try:
        # İlk olarak token doğrulaması yapılır, ardından rol kontrolü uygulanır.
        identity = await get_bearer_identity(credentials)
        return await get_current_user(identity, db)
    except Exception:
        return None


def require_role(*roles: str):
    """Role-based access control decorator factory."""
    async def _check(user: AuthenticatedUser = Depends(get_current_user)) -> AuthenticatedUser:
        if user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Bu işlem için '{'/'.join(roles)}' rolü gerekli.",
            )
        return user
    return _check
