"""
Firebase ID Token doğrulama.

iOS tarafı her istekte Authorization: Bearer <idToken> header'ı gönderir.
fastapi-firebase-auth yerine firebase-admin kullanıyoruz (daha güvenilir).
"""
import json
import os
from functools import lru_cache
from typing import Optional

import firebase_admin
from firebase_admin import auth as firebase_auth, credentials
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import get_settings

bearer_scheme = HTTPBearer(auto_error=False)


@lru_cache(maxsize=1)
def _init_firebase_app() -> firebase_admin.App:
    """Firebase Admin SDK'yı bir kez başlat (thread-safe, idempotent)."""
    settings = get_settings()

    if settings.firebase_credentials_json:
        cred_dict = json.loads(settings.firebase_credentials_json)
        cred = credentials.Certificate(cred_dict)
    else:
        # Development: GOOGLE_APPLICATION_CREDENTIALS env var ile
        cred = credentials.ApplicationDefault()

    try:
        return firebase_admin.get_app()
    except ValueError:
        return firebase_admin.initialize_app(cred)


class FirebaseUser:
    def __init__(self, uid: str, email: Optional[str], role: Optional[str] = None):
        self.uid = uid
        self.email = email
        self.role = role or "user"


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> FirebaseUser:
    """
    Bearer token'ı Firebase ile doğrula.
    Geçersiz/eksik token → 401.
    """
    _init_firebase_app()

    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header eksik",
        )

    try:
        decoded = firebase_auth.verify_id_token(credentials.credentials)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Geçersiz Firebase token: {exc}",
        )

    # Custom claims'dan role oku (varsa)
    role = decoded.get("role", "user")
    return FirebaseUser(uid=decoded["uid"], email=decoded.get("email"), role=role)


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> Optional[FirebaseUser]:
    """Public endpoint'ler için — token yoksa None döner, hata fırlatmaz."""
    if not credentials:
        return None
    try:
        return await get_current_user(credentials)
    except HTTPException:
        return None


def require_role(*roles: str):
    """Role-based access control decorator factory."""
    async def _check(user: FirebaseUser = Depends(get_current_user)) -> FirebaseUser:
        if user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Bu işlem için '{'/'.join(roles)}' rolü gerekli.",
            )
        return user
    return _check
