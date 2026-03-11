"""HTTP transport üzerinde ek uygulama-katmanı güvenlik kontrolleri.

Not: Bu katman replay ve request bütünlüğünü güçlendirir, fakat gerçek trafik gizliliği için
HTTPS/TLS zorunludur.
"""
from __future__ import annotations

import asyncio
import hashlib
import hmac
import time
from typing import Optional

from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.core.config import get_settings


class RequestSecurityMiddleware(BaseHTTPMiddleware):
    """Bearer token kullanılan isteklerde imza + nonce replay koruması uygular."""

    def __init__(self, app):
        super().__init__(app)
        self._nonce_cache: dict[str, float] = {}
        self._lock = asyncio.Lock()
        settings = get_settings()
        self._enabled = settings.enforce_signed_requests
        self._max_skew_seconds = max(10, int(settings.request_signature_max_skew_seconds))
        self._nonce_ttl_seconds = max(self._max_skew_seconds, int(settings.request_nonce_ttl_seconds))

    async def dispatch(self, request: Request, call_next) -> Response:
        if self._enabled:
            error_response = await self._validate_request(request)
            if error_response is not None:
                self._add_security_headers(error_response)
                return error_response

        response = await call_next(request)
        self._add_security_headers(response)
        return response

    async def _validate_request(self, request: Request) -> Optional[JSONResponse]:
        if request.method.upper() == "OPTIONS":
            return None

        auth_header = request.headers.get("authorization", "")
        if not auth_header.lower().startswith("bearer "):
            return None

        token = auth_header.split(" ", 1)[1].strip()
        if not token:
            return self._security_error(401, "Authorization header geçersiz.")

        ts_header = request.headers.get("x-req-ts", "").strip()
        nonce = request.headers.get("x-req-nonce", "").strip()
        signature = request.headers.get("x-req-signature", "").strip().lower()

        if not ts_header or not nonce or not signature:
            return self._security_error(401, "İstek güvenlik başlıkları eksik.")

        if len(nonce) < 12 or len(nonce) > 128:
            return self._security_error(401, "Geçersiz nonce.")

        try:
            ts_value = int(ts_header)
        except ValueError:
            return self._security_error(401, "Geçersiz zaman damgası.")

        now = int(time.time())
        if abs(now - ts_value) > self._max_skew_seconds:
            return self._security_error(401, "İstek süresi geçti.")

        body = await request.body()
        body_hash = hashlib.sha256(body).hexdigest()
        path_and_query = request.url.path
        if request.url.query:
            path_and_query += f"?{request.url.query}"

        canonical = "\n".join([
            request.method.upper(),
            path_and_query,
            str(ts_value),
            nonce,
            body_hash,
        ])
        expected_signature = hmac.new(
            token.encode("utf-8"),
            canonical.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()

        if not hmac.compare_digest(expected_signature, signature):
            return self._security_error(401, "İstek imzası doğrulanamadı.")

        nonce_key = hashlib.sha256(f"{token}:{nonce}".encode("utf-8")).hexdigest()
        replay_detected = await self._register_nonce_or_detect_replay(nonce_key, now)
        if replay_detected:
            return self._security_error(409, "Tekrarlanan istek tespit edildi.")

        return None

    async def _register_nonce_or_detect_replay(self, nonce_key: str, now: int) -> bool:
        async with self._lock:
            expired = [key for key, expiry in self._nonce_cache.items() if expiry <= now]
            for key in expired:
                self._nonce_cache.pop(key, None)

            if nonce_key in self._nonce_cache:
                return True

            self._nonce_cache[nonce_key] = now + self._nonce_ttl_seconds
            return False

    @staticmethod
    def _security_error(status_code: int, detail: str) -> JSONResponse:
        return JSONResponse(status_code=status_code, content={"detail": detail})

    @staticmethod
    def _add_security_headers(response: Response) -> None:
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
