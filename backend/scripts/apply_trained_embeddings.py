from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path

from sentence_transformers import SentenceTransformer
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine


def _ensure_async_url(raw_url: str) -> str:
    if raw_url.startswith("postgresql+asyncpg://"):
        return raw_url
    if raw_url.startswith("postgresql://"):
        return raw_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    raise ValueError("DATABASE_URL postgresql:// veya postgresql+asyncpg:// formatında olmalı.")


def build_text(name: str, description: str, category: str, cuisine_type: str) -> str:
    parts = []
    if category:
        parts.append(f"Kategori: {category}")
    parts.append(f"İsim: {name}")
    if description:
        parts.append(f"Açıklama: {description}")
    if cuisine_type:
        parts.append(f"Mutfak: {cuisine_type}")
    return " | ".join(parts)


async def load_items(db_url: str, only_available: bool) -> list[dict]:
    engine = create_async_engine(_ensure_async_url(db_url), echo=False)
    where_clause = "WHERE COALESCE(m.is_available, true) = true" if only_available else ""
    query = text(
        f"""
        SELECT
            m.id,
            m.name,
            COALESCE(m.description, '') AS description,
            COALESCE(m.category, '') AS category,
            COALESCE(r.cuisine_type, '') AS cuisine_type
        FROM menu_items m
        JOIN restaurants r ON r.id = m.restaurant_id
        {where_clause}
        """
    )
    async with engine.begin() as conn:
        result = await conn.execute(query)
        rows = [dict(r) for r in result.mappings().all()]
    await engine.dispose()
    return rows


async def write_embeddings(db_url: str, item_ids: list[str], vectors: list[list[float]]) -> int:
    engine = create_async_engine(_ensure_async_url(db_url), echo=False)
    update_sql = text("UPDATE menu_items SET embedding = :embedding WHERE id = :item_id")
    async with engine.begin() as conn:
        for item_id, vec in zip(item_ids, vectors):
            await conn.execute(update_sql, {"embedding": vec, "item_id": item_id})
    await engine.dispose()
    return len(item_ids)


async def main_async(args: argparse.Namespace) -> None:
    db_url = args.database_url or os.getenv("DATABASE_URL")
    if not db_url:
        raise RuntimeError("DATABASE_URL bulunamadı. --database-url verin veya env ayarlayın.")

    model = SentenceTransformer(args.model_path, device="cuda" if args.use_cuda else "cpu")
    model.max_seq_length = args.max_seq_length

    items = await load_items(db_url, only_available=args.only_available)
    if not items:
        print(json.dumps({"updated": 0, "message": "menu_items boş"}, ensure_ascii=False))
        return

    texts = [
        build_text(
            str(item.get("name") or ""),
            str(item.get("description") or ""),
            str(item.get("category") or ""),
            str(item.get("cuisine_type") or ""),
        )
        for item in items
    ]
    item_ids = [str(item["id"]) for item in items]

    vectors = model.encode(
        texts,
        normalize_embeddings=True,
        convert_to_numpy=True,
        batch_size=args.batch_size,
        show_progress_bar=True,
    )
    updated = await write_embeddings(db_url, item_ids, [v.tolist() for v in vectors])

    out = {"updated": updated, "modelPath": args.model_path, "dim": int(vectors.shape[1])}
    print(json.dumps(out, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Eğitilmiş embedding modelini menu_items tablosuna yazar.")
    p.add_argument("--model-path", type=str, required=True, help="HuggingFace model id veya lokal model klasörü")
    p.add_argument("--database-url", type=str, default="")
    p.add_argument("--batch-size", type=int, default=128)
    p.add_argument("--max-seq-length", type=int, default=128)
    p.add_argument("--use-cuda", action="store_true")
    p.add_argument("--only-available", action="store_true")
    return p


def main() -> None:
    args = build_parser().parse_args()
    asyncio.run(main_async(args))


if __name__ == "__main__":
    main()
