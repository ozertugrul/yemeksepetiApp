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
import uuid
from pathlib import Path

import asyncpg
import bcrypt
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

ADMIN_EMAIL    = "admin@yemeksepeti.com"
ADMIN_PASSWORD = "admin1"
ADMIN_NAME     = "Süper Admin"
ADMIN_ROLE     = "admin"


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


# ─── PostgreSQL'e kaydet ──────────────────────────────────────────────────────
async def upsert_pg_user(conn: asyncpg.Connection):
    email = ADMIN_EMAIL.lower().strip()
    password_hash = bcrypt.hashpw(ADMIN_PASSWORD.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

    existing = await conn.fetchrow("SELECT id FROM users WHERE email=$1", email)
    uid = existing["id"] if existing else str(uuid.uuid4())

    await conn.execute(
        """
        INSERT INTO users (id, email, password_hash, display_name, role, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
        ON CONFLICT (id) DO UPDATE
          SET email         = EXCLUDED.email,
              password_hash = EXCLUDED.password_hash,
              display_name  = EXCLUDED.display_name,
              role          = EXCLUDED.role,
              updated_at    = NOW()
        """,
        uid, email, password_hash, ADMIN_NAME, ADMIN_ROLE,
    )
    print(f"[PostgreSQL] users tablosuna yazıldı → id={uid}, role={ADMIN_ROLE}")
    return uid


# ─── Ana akış ────────────────────────────────────────────────────────────────
async def main():
    print("=" * 55)
    print("  Superadmin oluşturucu")
    print("=" * 55)

    conn = await get_conn()
    uid = await upsert_pg_user(conn)
    await conn.close()

    print()
    print("✅ Superadmin hazır!")
    print(f"   E-posta : {ADMIN_EMAIL}")
    print(f"   Şifre   : {ADMIN_PASSWORD}")
    print(f"   Rol     : {ADMIN_ROLE}")
    print(f"   UID     : {uid}")


asyncio.run(main())
