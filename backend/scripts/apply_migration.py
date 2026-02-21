"""
Supabase'e SQL migration uygula (asyncpg ile, psql gerektirmez).
Çalıştır: python3 scripts/apply_migration.py
"""
import asyncio
import asyncpg
import os
from pathlib import Path

HOST = "aws-1-eu-west-1.pooler.supabase.com"
PORT = 6543
USER = "postgres.wzyaeoqdtpvkjxorqnra"
PASSWORD = "REDACTED_FROM_HISTORY"
DATABASE = "postgres"

SQL_FILE = Path(__file__).parent.parent / "migrations" / "001_initial_schema.sql"


async def main():
    print("Supabase'e bağlanılıyor…")
    conn = await asyncpg.connect(
        host=HOST, port=PORT, user=USER,
        password=PASSWORD, database=DATABASE, ssl="require",
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
