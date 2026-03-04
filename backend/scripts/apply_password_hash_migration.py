"""
users.password_hash kolonunu ekler.

Çalıştır:
  cd backend
  /Users/ertu-mac/anaconda3/envs/ertu/bin/python scripts/apply_password_hash_migration.py
"""
import asyncio
import os
import re
from pathlib import Path

import asyncpg
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")


async def main() -> None:
    raw = os.getenv("DATABASE_URL", "")
    if not raw:
        raise SystemExit("DATABASE_URL env var eksik")

    url = raw.replace("postgresql+asyncpg://", "").replace("%24", "$").replace("%23", "#")
    match = re.match(r"([^:]+):([^@]+)@([^:/]+):(\d+)/(.+)", url)
    if not match:
        raise SystemExit("DATABASE_URL parse edilemedi")

    user, password, host, port, database = match.groups()
    conn = await asyncpg.connect(
        host=host,
        port=int(port),
        user=user,
        password=password,
        database=database,
        ssl="require",
        statement_cache_size=0,
        timeout=20,
    )

    try:
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT")
        exists = await conn.fetchval(
            """
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'users' AND column_name = 'password_hash'
            LIMIT 1
            """
        )
        if exists:
            print("OK: users.password_hash kolonu hazır")
        else:
            raise SystemExit("HATA: password_hash kolonu doğrulanamadı")
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main())
