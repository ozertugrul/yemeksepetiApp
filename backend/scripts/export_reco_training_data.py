from __future__ import annotations

import argparse
import asyncio
import itertools
import json
import math
import os
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine


@dataclass
class MenuItemRecord:
    id: str
    restaurant_id: str
    name: str
    description: str
    category: str
    cuisine_type: str
    is_available: bool

    @property
    def training_text(self) -> str:
        parts = []
        if self.category:
            parts.append(f"Kategori: {self.category}")
        parts.append(f"İsim: {self.name}")
        if self.description:
            parts.append(f"Açıklama: {self.description}")
        if self.cuisine_type:
            parts.append(f"Mutfak: {self.cuisine_type}")
        return _normalize_text(" | ".join(parts))


def _normalize_text(text: str) -> str:
    return " ".join((text or "").strip().split())


def _ensure_async_url(raw_url: str) -> str:
    if raw_url.startswith("postgresql+asyncpg://"):
        return raw_url
    if raw_url.startswith("postgresql://"):
        return raw_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    raise ValueError("DATABASE_URL postgresql:// veya postgresql+asyncpg:// formatında olmalı.")


async def _load_menu_items(db_url: str) -> dict[str, MenuItemRecord]:
    engine = create_async_engine(_ensure_async_url(db_url), echo=False)
    query = text(
        """
        SELECT
            m.id,
            m.restaurant_id,
            m.name,
            COALESCE(m.description, '') AS description,
            COALESCE(m.category, '') AS category,
            COALESCE(r.cuisine_type, '') AS cuisine_type,
            COALESCE(m.is_available, true) AS is_available
        FROM menu_items m
        JOIN restaurants r ON r.id = m.restaurant_id
        """
    )
    async with engine.begin() as conn:
        result = await conn.execute(query)
        rows = result.mappings().all()
    await engine.dispose()

    out: dict[str, MenuItemRecord] = {}
    for row in rows:
        rec = MenuItemRecord(
            id=str(row["id"]),
            restaurant_id=str(row["restaurant_id"]),
            name=(row["name"] or "").strip(),
            description=(row["description"] or "").strip(),
            category=(row["category"] or "").strip(),
            cuisine_type=(row["cuisine_type"] or "").strip(),
            is_available=bool(row["is_available"]),
        )
        if rec.name:
            out[rec.id] = rec
    return out


async def _load_orders(
    db_url: str,
    allowed_statuses: set[str],
    batch_size: int,
) -> list[dict[str, Any]]:
    engine = create_async_engine(_ensure_async_url(db_url), echo=False)
    rows: list[dict[str, Any]] = []
    statuses = sorted(list(allowed_statuses))
    use_status = bool(statuses)

    first_query = text(
        """
        SELECT id, user_id, items, status, created_at
        FROM orders
        WHERE items IS NOT NULL
          AND (:use_status = false OR status = ANY(:statuses))
        ORDER BY created_at ASC, id ASC
        LIMIT :batch_size
        """
    )

    next_query = text(
        """
        SELECT id, user_id, items, status, created_at
        FROM orders
        WHERE items IS NOT NULL
          AND (:use_status = false OR status = ANY(:statuses))
          AND (
              created_at > :last_created_at
              OR (created_at = :last_created_at AND id > :last_id)
          )
        ORDER BY created_at ASC, id ASC
        LIMIT :batch_size
        """
    )

    last_created_at: datetime | None = None
    last_id: str = ""

    async with engine.begin() as conn:
        while True:
            if last_created_at is None:
                result = await conn.execute(
                    first_query,
                    {
                        "use_status": use_status,
                        "statuses": statuses,
                        "batch_size": batch_size,
                    },
                )
            else:
                result = await conn.execute(
                    next_query,
                    {
                        "use_status": use_status,
                        "statuses": statuses,
                        "last_created_at": last_created_at,
                        "last_id": last_id,
                        "batch_size": batch_size,
                    },
                )
            batch = [dict(r) for r in result.mappings().all()]
            if not batch:
                break

            rows.extend(batch)
            tail = batch[-1]
            last_created_at = tail.get("created_at")
            last_id = str(tail.get("id") or "")

            if len(rows) % (batch_size * 5) == 0:
                print(f"orders_loaded={len(rows)}")

    await engine.dispose()
    return rows


def _extract_item_ids(order_items: Any) -> list[str]:
    if not isinstance(order_items, list):
        return []
    ids: list[str] = []
    for obj in order_items:
        if not isinstance(obj, dict):
            continue
        menu_item_id = obj.get("menu_item_id") or obj.get("menuItemId")
        if menu_item_id:
            ids.append(str(menu_item_id))
    return ids


def _write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


async def main_async(args: argparse.Namespace) -> None:
    db_url = args.database_url or os.getenv("DATABASE_URL")
    if not db_url:
        raise RuntimeError("DATABASE_URL bulunamadı. --database-url verin veya env ayarlayın.")

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    allowed_statuses = {s.strip() for s in args.allowed_statuses.split(",") if s.strip()}

    menu_map = await _load_menu_items(db_url)
    orders = await _load_orders(
        db_url,
        allowed_statuses=allowed_statuses,
        batch_size=args.order_batch_size,
    )

    menu_rows = [
        {
            "menuItemId": rec.id,
            "restaurantId": rec.restaurant_id,
            "name": rec.name,
            "description": rec.description,
            "category": rec.category,
            "cuisineType": rec.cuisine_type,
            "isAvailable": rec.is_available,
            "text": rec.training_text,
        }
        for rec in menu_map.values()
    ]
    _write_jsonl(out_dir / "menu_items.jsonl", menu_rows)

    pair_counter: Counter[tuple[str, str]] = Counter()
    user_item_counter: defaultdict[str, Counter[str]] = defaultdict(Counter)
    user_events: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)

    skipped_by_status = 0
    used_orders = 0

    for order in orders:
        status = str(order.get("status") or "")
        if allowed_statuses and status not in allowed_statuses:
            skipped_by_status += 1
            continue

        user_id = str(order.get("user_id") or "")
        item_ids = [i for i in _extract_item_ids(order.get("items")) if i in menu_map]
        if not item_ids:
            continue
        used_orders += 1

        uniq_ids = sorted(set(item_ids))
        for a, b in itertools.combinations(uniq_ids, 2):
            pair_counter[(a, b)] += 1
            pair_counter[(b, a)] += 1

        if user_id:
            for item_id in item_ids:
                user_item_counter[user_id][item_id] += 1
            user_events[user_id].append(
                {
                    "orderId": str(order.get("id") or ""),
                    "status": str(order.get("status") or ""),
                    "createdAt": str(order.get("created_at") or ""),
                    "itemIds": item_ids,
                }
            )

    for user_id, counts in user_item_counter.items():
        repeated = [item for item, c in counts.items() if c >= 2]
        for a, b in itertools.permutations(repeated, 2):
            if a != b:
                pair_counter[(a, b)] += 1

    raw_train_rows: list[dict[str, Any]] = []
    for (anchor_id, positive_id), weight in pair_counter.items():
        if weight < args.min_pair_weight:
            continue
        anchor = menu_map.get(anchor_id)
        positive = menu_map.get(positive_id)
        if not anchor or not positive:
            continue
        if anchor_id == positive_id:
            continue

        # Aşırı popüler çiftlerin eğitimi domine etmesini azalt (log-damping)
        damped_weight = int(round(100 * math.log1p(weight)))

        raw_train_rows.append(
            {
                "anchorId": anchor_id,
                "positiveId": positive_id,
                "weight": int(weight),
                "dampedWeight": damped_weight,
                "anchorText": anchor.training_text,
                "positiveText": positive.training_text,
            }
        )

    # Anchor başına en güçlü ilk K positive bırak (bias azaltma + daha temiz sinyal)
    grouped: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in raw_train_rows:
        grouped[row["anchorId"]].append(row)

    train_rows: list[dict[str, Any]] = []
    for anchor_id, rows in grouped.items():
        rows.sort(key=lambda r: (r["weight"], r["dampedWeight"]), reverse=True)
        train_rows.extend(rows[: args.max_positives_per_anchor])

    train_rows.sort(key=lambda r: (r["weight"], r["dampedWeight"]), reverse=True)
    _write_jsonl(out_dir / "train_pairs.jsonl", train_rows)

    user_history_rows = [
        {
            "userId": user_id,
            "events": events,
            "topItems": [
                {"menuItemId": item_id, "count": int(cnt)}
                for item_id, cnt in user_item_counter[user_id].most_common(args.max_user_top_items)
            ],
        }
        for user_id, events in user_events.items()
    ]
    _write_jsonl(out_dir / "user_histories.jsonl", user_history_rows)

    summary = {
        "menuItems": len(menu_rows),
        "orders": len(orders),
        "usedOrders": used_orders,
        "skippedByStatus": skipped_by_status,
        "pairRows": len(train_rows),
        "rawPairRows": len(raw_train_rows),
        "users": len(user_history_rows),
        "minPairWeight": args.min_pair_weight,
        "maxPositivesPerAnchor": args.max_positives_per_anchor,
        "allowedStatuses": sorted(list(allowed_statuses)),
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(summary, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Reco embedding eğitimi için DB'den dataset çıkarır.")
    parser.add_argument("--database-url", type=str, default="", help="PostgreSQL URL. Verilmezse DATABASE_URL env kullanılır.")
    parser.add_argument("--output-dir", type=str, default="./kaggle_dataset", help="JSONL çıktı klasörü")
    parser.add_argument("--min-pair-weight", type=int, default=2, help="Eğitime alınacak minimum eşleşme ağırlığı")
    parser.add_argument("--max-user-top-items", type=int, default=50, help="Kullanıcı başına tutulacak top item sayısı")
    parser.add_argument(
        "--allowed-statuses",
        type=str,
        default="delivered",
        help="Sadece bu durumdaki siparişleri eğitim sinyali olarak kullan (virgülle ayrılmış)",
    )
    parser.add_argument(
        "--max-positives-per-anchor",
        type=int,
        default=40,
        help="Anchor başına tutulacak maksimum positive çift sayısı",
    )
    parser.add_argument(
        "--order-batch-size",
        type=int,
        default=20000,
        help="Orders tablosu keyset pagination batch boyutu",
    )
    return parser


def main() -> None:
    args = build_parser().parse_args()
    asyncio.run(main_async(args))


if __name__ == "__main__":
    main()
