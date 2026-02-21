"""
Superadmin kullanıcısı oluştur.

Giriş bilgileri:
  E-posta  : admin@yemeksepeti.com
  Şifre    : admin
  Rol      : admin

Çalıştır:
  cd backend
  conda run -n ertu python scripts/create_superadmin.py
"""
import asyncio
import os
import json
from pathlib import Path

import asyncpg
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, auth as firebase_auth

load_dotenv(Path(__file__).parent.parent / ".env")

ADMIN_EMAIL    = "admin@yemeksepeti.com"
ADMIN_PASSWORD = "admin1"   # Firebase min 6 karakter gerektirir
ADMIN_NAME     = "Süper Admin"
ADMIN_ROLE     = "admin"


# ─── Firebase init ────────────────────────────────────────────────────────────
def init_firebase():
    cred_json = os.getenv("FIREBASE_CREDENTIALS_JSON", "")
    if not cred_json:
        raise SystemExit("FIREBASE_CREDENTIALS_JSON env var eksik")
    cred = credentials.Certificate(json.loads(cred_json))
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)


# ─── asyncpg bağlantısı ───────────────────────────────────────────────────────
async def get_conn() -> asyncpg.Connection:
    import re
    raw = os.getenv("DATABASE_URL", "")
    if not raw:
        raise SystemExit("DATABASE_URL env var eksik")
    url = raw.replace("postgresql+asyncpg://", "").replace("%24", "$").replace("%23", "#")
    m = re.match(r"([^:]+):([^@]+)@([^:/]+):(\d+)/(.+)", url)
    user, password, host, port, database = m.groups()
    return await asyncpg.connect(
        host=host, port=int(port), user=user,
        password=password, database=database, ssl="require",
        statement_cache_size=0,
    )


# ─── Firebase kullanıcısı oluştur / güncelle ──────────────────────────────────
def ensure_firebase_user() -> str:
    """Kullanıcı zaten varsa UID'ini döner, yoksa oluşturur."""
    try:
        user = firebase_auth.get_user_by_email(ADMIN_EMAIL)
        print(f"[Firebase] Kullanıcı zaten mevcut → {user.uid}")
        # Şifreyi güncelle (admin olsun diye)
        firebase_auth.update_user(user.uid, password=ADMIN_PASSWORD, display_name=ADMIN_NAME)
        return user.uid
    except firebase_auth.UserNotFoundError:
        user = firebase_auth.create_user(
            email=ADMIN_EMAIL,
            password=ADMIN_PASSWORD,
            display_name=ADMIN_NAME,
            email_verified=True,
        )
        print(f"[Firebase] Yeni kullanıcı oluşturuldu → {user.uid}")
        return user.uid


# ─── PostgreSQL'e kaydet ──────────────────────────────────────────────────────
async def upsert_pg_user(conn: asyncpg.Connection, uid: str):
    # Önce email ile var mı diye bak (farklı UID'de kayıtlı olabilir)
    existing = await conn.fetchrow("SELECT id FROM users WHERE email=$1", ADMIN_EMAIL)
    if existing and existing["id"] != uid:
        # Eski kaydı sil, Firebase UID ile yeniden ekle
        await conn.execute("DELETE FROM users WHERE email=$1", ADMIN_EMAIL)
        print(f"[PostgreSQL] Eski kayıt temizlendi → {existing['id']}")

    await conn.execute(
        """
        INSERT INTO users (id, email, display_name, role, created_at, updated_at)
        VALUES ($1, $2, $3, $4, NOW(), NOW())
        ON CONFLICT (id) DO UPDATE
          SET email        = EXCLUDED.email,
              display_name = EXCLUDED.display_name,
              role         = EXCLUDED.role,
              updated_at   = NOW()
        """,
        uid, ADMIN_EMAIL, ADMIN_NAME, ADMIN_ROLE,
    )
    print(f"[PostgreSQL] users tablosuna yazıldı → id={uid}, role={ADMIN_ROLE}")


# ─── Ana akış ────────────────────────────────────────────────────────────────
async def main():
    print("=" * 55)
    print("  Superadmin oluşturucu")
    print("=" * 55)

    init_firebase()
    uid = ensure_firebase_user()

    conn = await get_conn()
    await upsert_pg_user(conn, uid)
    await conn.close()

    print()
    print("✅ Superadmin hazır!")
    print(f"   E-posta : {ADMIN_EMAIL}")
    print(f"   Şifre   : {ADMIN_PASSWORD}")
    print(f"   Rol     : {ADMIN_ROLE}")
    print(f"   UID     : {uid}")


asyncio.run(main())
