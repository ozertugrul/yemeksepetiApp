import asyncio, asyncpg, os, re
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

async def check():
    raw = os.getenv("DATABASE_URL").replace("postgresql+asyncpg://","").replace("%24","$").replace("%23","#")
    m = re.match(r"([^:]+):([^@]+)@([^:/]+):(\d+)/(.+)", raw)
    user, pwd, host, port, db = m.groups()
    conn = await asyncpg.connect(host=host, port=int(port), user=user, password=pwd,
                                  database=db, ssl="require", statement_cache_size=0)
    tables = await conn.fetch(
        "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename"
    )
    print("PostgreSQL tabloları:")
    for t in tables:
        tname = t["tablename"]
        cnt = await conn.fetchval(f'SELECT COUNT(*) FROM "{tname}"')
        print(f"  {tname}: {cnt} kayıt")
    admin = await conn.fetchrow("SELECT id, email, role FROM users WHERE role='admin'")
    print()
    print(f"ADMIN kullanıcı: {dict(admin) if admin else 'YOK'}")
    await conn.close()

asyncio.run(check())
