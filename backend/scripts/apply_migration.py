"""
Supabase'e SQL migration uygula (asyncpg ile, psql gerektirmez).
Çalıştır: python3 scripts/apply_migration.py
Kimlik bilgileri .env dosyasından okunur (DATABASE_URL).
"""
import asyncio
import asyncpg
import os
import re
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

SQL_FILE = Path(__file__).parent.parent / "migrations" / "001_initial_schema.sql"


def _parse_db_url(url: str):
    """postgresql+asyncpg://user:pass@host:port/db  → bileşenlerine ayır."""
    url = url.replace("postgresql+asyncpg://", "").replace("postgresql://", "")
    m = re.match(r"([^:]+):([^@]+)@([^:/]+):(\d+)/(.+)", url)
    if not m:
        raise ValueError(f"DATABASE_URL parse edilemedi: {url}")
    return m.group(1), m.group(2), m.group(3), int(m.group(4)), m.group(5)


async def main():
    db_url = os.getenv("DATABASE_URL", "")
    if not db_url:
        raise SystemExit("Hata: DATABASE_URL env var eksik (.env dosyasını kontrol et)")

    user, password, host, port, database = _parse_db_url(
        db_url.replace("%24", "$").replace("%23", "#")
    )

    print(f"Supabase'e bağlanılıyor → {host}:{port}/{database} …")
    conn = await asyncpg.connect(
        host=host, port=port, user=user,
        password=password, database=database, ssl="require",
        statement_cache_size=0,
    )
    print("Bağlantı başarılı.")

    sql = SQL_FILE.read_text(encoding="utf-8")

    # Yorumları filtrele, boş statement'ları atla
    statements = []
    current = []
    for line in sql.splitlines():
        stripped = line.strip()
        if stripped.startswith("--") or not stripped:
            continue
        current.append(line)
        if stripped.endswith(";"):
            stmt = "\n".join(current).strip()
            if stmt:
                statements.append(stmt)
            current = []

    # DO $$ ... $$ bloklarını birleştir (trigger tanımları)
    # En güvenli: tüm SQL'i tek seferde çalıştır
    print(f"\nMigration uygulanıyor ({len(statements)} statement)…")

    try:
        await conn.execute(sql)
        print("Migration başarıyla tamamlandı!")
    except Exception as e:
        print(f"Hata: {e}")
        print("\nStatement-by-statement moduna geçiliyor…")
        ok, fail = 0, 0
        for stmt in statements:
            try:
                await conn.execute(stmt)
                ok += 1
            except Exception as se:
                print(f"  SKIP: {str(se)[:80]}")
                fail += 1
        print(f"\nTamamlandı: {ok} başarılı, {fail} atlandı")

    # Tabloları doğrula
    tables = await conn.fetch(
        "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename"
    )
    print(f"\nMevcut tablolar ({len(tables)}):")
    for t in tables:
        print(f"  ✓ {t['tablename']}")

    await conn.close()


asyncio.run(main())
