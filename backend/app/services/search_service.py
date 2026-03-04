from __future__ import annotations

from datetime import datetime, timezone
import math
import re
import unicodedata
from dataclasses import dataclass
from typing import Iterable, Optional

from sqlalchemy import desc, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.orm_models import MenuItemORM, RestaurantORM
from app.repositories.sql_repos import SQLMenuItemRepository
from app.services.embedding_service import EmbeddingService


@dataclass
class _ScoredStore:
    row: RestaurantORM
    lexical: float
    score: float


@dataclass
class _ScoredMenu:
    row: MenuItemORM
    restaurant_name: str
    lexical: float
    score: float


class UnifiedSearchService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.embedding_service = EmbeddingService()

    async def search(self, query: str, city: Optional[str], offset: int, limit: int) -> dict:
        normalized_query = _normalize(query)
        expanded_terms = _expand_query_terms(normalized_query)
        if not normalized_query:
            return {
                "query": query,
                "stores": [],
                "menu_items": [],
                "similar_menu_items": [],
                "next_offset": None,
                "has_more": False,
            }

        stores = await self._candidate_stores(query=query, city=city, fetch_limit=max(80, limit * 5))
        scored_stores = sorted(
            (
                _ScoredStore(
                    row=item,
                    lexical=self._store_lexical_signal(normalized_query, expanded_terms, item),
                    score=self._store_score(normalized_query, expanded_terms, item),
                )
                for item in stores
            ),
            key=lambda x: x.score,
            reverse=True,
        )

        top_store_score = scored_stores[0].score if scored_stores else 0.0
        store_first = top_store_score >= 0.62
        matched_store_ids = {x.row.id for x in scored_stores[:8] if x.score >= 0.48}

        menus = await self._candidate_menu_items(query=query, city=city, fetch_limit=max(140, limit * 8))
        scored_menus = sorted(
            (
                _ScoredMenu(
                    row=item,
                    restaurant_name=restaurant_name,
                    lexical=self._menu_lexical_signal(normalized_query, expanded_terms, item, restaurant_name),
                    score=self._menu_score(normalized_query, expanded_terms, item, restaurant_name, matched_store_ids),
                )
                for item, restaurant_name in menus
            ),
            key=lambda x: x.score,
            reverse=True,
        )

        semantic_similar = await self._semantic_similar_items(
            query=normalized_query,
            restaurant_ids=matched_store_ids if matched_store_ids else None,
            top_k=max(20, limit * 2),
        )

        ranked_stores = scored_stores[offset: offset + limit]
        ranked_menus = scored_menus[offset: offset + limit]

        stores_payload = [
            {
                "id": x.row.id,
                "entity_type": "store",
                "title": x.row.name,
                "subtitle": x.row.cuisine_type,
                "restaurant_id": x.row.id,
                "restaurant_name": x.row.name,
                "image_url": x.row.image_url,
                "price": None,
                "rating": float(x.row.average_rating or x.row.rating or 0),
                "score": round(x.score, 4),
            }
            for x in ranked_stores
            if x.score > 0.28 and (x.lexical >= 0.12 or _normalize(x.row.name).startswith(normalized_query))
        ]

        menu_payload = [
            {
                "id": x.row.id,
                "entity_type": "menu",
                "title": x.row.name,
                "subtitle": x.row.category,
                "restaurant_id": x.row.restaurant_id,
                "restaurant_name": x.restaurant_name,
                "image_url": x.row.image_url,
                "price": float(x.row.price or 0),
                "rating": None,
                "score": round(x.score, 4),
            }
            for x in ranked_menus
            if x.score > 0.24 and (x.lexical >= 0.16 or _normalize(x.row.name).startswith(normalized_query))
        ]

        similar_payload: list[dict] = []
        seen_menu_ids = {m["id"] for m in menu_payload}

        for item, similarity in semantic_similar:
            if item.id in seen_menu_ids:
                continue
            similar_payload.append(
                {
                    "id": item.id,
                    "entity_type": "menu",
                    "title": item.name,
                    "subtitle": item.category,
                    "restaurant_id": item.restaurant_id,
                    "restaurant_name": None,
                    "image_url": item.image_url,
                    "price": float(item.price or 0),
                    "rating": None,
                    "score": round(float(similarity), 4),
                }
            )

        if len(similar_payload) < limit:
            similar_payload.extend(
                self._lexical_alternatives_from_ranked(
                    ranked_menus=scored_menus,
                    seen_menu_ids=seen_menu_ids | {item["id"] for item in similar_payload},
                    limit=limit - len(similar_payload),
                )
            )

        stores_out = stores_payload
        menu_out = menu_payload
        if store_first:
            stores_out = stores_payload
            menu_out = menu_payload

        has_more = (offset + limit) < max(len(scored_stores), len(scored_menus))
        next_offset = (offset + limit) if has_more else None

        return {
            "query": query,
            "stores": stores_out,
            "menu_items": menu_out,
            "similar_menu_items": similar_payload[:limit],
            "next_offset": next_offset,
            "has_more": has_more,
        }

    async def _candidate_stores(self, query: str, city: Optional[str], fetch_limit: int) -> list[RestaurantORM]:
        terms = _sql_query_variants(query)
        stmt = select(RestaurantORM).where(RestaurantORM.is_active == True)
        if city:
            stmt = stmt.where(RestaurantORM.city.ilike(f"%{city.strip()}%"))

        store_clauses = []
        for term in terms:
            like = f"%{term}%"
            store_clauses.extend(
                [
                    RestaurantORM.name.ilike(like),
                    RestaurantORM.cuisine_type.ilike(like),
                    RestaurantORM.description.ilike(like),
                ]
            )
        if store_clauses:
            stmt = stmt.where(or_(*store_clauses))

        result = await self.db.execute(stmt.limit(fetch_limit))
        rows = result.scalars().all()
        if rows:
            return rows

        fallback_stmt = (
            select(RestaurantORM)
            .where(RestaurantORM.is_active == True)
            .order_by(desc(RestaurantORM.successful_order_count), RestaurantORM.name)
            .limit(fetch_limit)
        )
        if city:
            fallback_stmt = fallback_stmt.where(RestaurantORM.city.ilike(f"%{city.strip()}%"))

        fallback_result = await self.db.execute(fallback_stmt)
        fallback_rows = fallback_result.scalars().all()
        if fallback_rows:
            return fallback_rows

        if city:
            global_result = await self.db.execute(
                select(RestaurantORM)
                .where(RestaurantORM.is_active == True)
                .order_by(desc(RestaurantORM.successful_order_count), RestaurantORM.name)
                .limit(fetch_limit)
            )
            return global_result.scalars().all()

        return []

    async def _candidate_menu_items(self, query: str, city: Optional[str], fetch_limit: int) -> list[tuple[MenuItemORM, str]]:
        terms = _sql_query_variants(query)
        stmt = (
            select(MenuItemORM, RestaurantORM.name)
            .join(RestaurantORM, RestaurantORM.id == MenuItemORM.restaurant_id)
            .where(RestaurantORM.is_active == True)
            .where(MenuItemORM.is_available == True)
        )
        if city:
            stmt = stmt.where(RestaurantORM.city.ilike(f"%{city.strip()}%"))

        menu_clauses = []
        for term in terms:
            like = f"%{term}%"
            menu_clauses.extend(
                [
                    MenuItemORM.name.ilike(like),
                    MenuItemORM.category.ilike(like),
                    MenuItemORM.description.ilike(like),
                ]
            )
        if menu_clauses:
            stmt = stmt.where(or_(*menu_clauses))

        result = await self.db.execute(stmt.limit(fetch_limit))
        rows = [(row[0], row[1]) for row in result.all()]
        if rows:
            return rows

        fallback_stmt = (
            select(MenuItemORM, RestaurantORM.name)
            .join(RestaurantORM, RestaurantORM.id == MenuItemORM.restaurant_id)
            .where(RestaurantORM.is_active == True)
            .where(MenuItemORM.is_available == True)
            .order_by(desc(MenuItemORM.discount_percent), MenuItemORM.name)
            .limit(fetch_limit)
        )
        if city:
            fallback_stmt = fallback_stmt.where(RestaurantORM.city.ilike(f"%{city.strip()}%"))

        fallback_result = await self.db.execute(fallback_stmt)
        fallback_rows = [(row[0], row[1]) for row in fallback_result.all()]
        if fallback_rows:
            return fallback_rows

        if city:
            global_result = await self.db.execute(
                select(MenuItemORM, RestaurantORM.name)
                .join(RestaurantORM, RestaurantORM.id == MenuItemORM.restaurant_id)
                .where(RestaurantORM.is_active == True)
                .where(MenuItemORM.is_available == True)
                .order_by(desc(MenuItemORM.discount_percent), MenuItemORM.name)
                .limit(fetch_limit)
            )
            return [(row[0], row[1]) for row in global_result.all()]

        return []

    async def _semantic_similar_items(
        self,
        query: str,
        restaurant_ids: Optional[set[str]],
        top_k: int,
    ) -> list[tuple[MenuItemORM, float]]:
        vector = self.embedding_service.embed_text(query)
        if not vector:
            return []

        repo = SQLMenuItemRepository(self.db)
        if restaurant_ids and len(restaurant_ids) == 1:
            restaurant_id = next(iter(restaurant_ids))
            return await repo.find_similar(embedding=vector, restaurant_id=restaurant_id, top_k=top_k)
        return await repo.find_similar(embedding=vector, restaurant_id=None, top_k=top_k)

    def _store_score(self, normalized_query: str, expanded_terms: set[str], store: RestaurantORM) -> float:
        name = _normalize(store.name)
        cuisine = _normalize(store.cuisine_type or "")
        desc = _normalize(store.description or "")

        exact = 1.0 if name == normalized_query else 0.0
        prefix = 1.0 if name.startswith(normalized_query) else 0.0
        token = _token_overlap(_tokenize(normalized_query), _tokenize(f"{name} {cuisine} {desc}"))
        fuzzy = max(_fuzzy_similarity(normalized_query, name), _fuzzy_similarity(normalized_query, cuisine))
        lexical = self._store_lexical_signal(normalized_query, expanded_terms, store)
        popularity = _store_popularity(store)
        intent_boost = 0.10 if normalized_query and normalized_query in name else 0.0

        score = (0.30 * exact) + (0.20 * prefix) + (0.18 * token) + (0.12 * fuzzy) + (0.10 * lexical) + (0.10 * popularity) + intent_boost
        return min(1.0, score)

    def _menu_score(
        self,
        normalized_query: str,
        expanded_terms: set[str],
        item: MenuItemORM,
        restaurant_name: str,
        matched_store_ids: set[str],
    ) -> float:
        name = _normalize(item.name)
        category = _normalize(item.category or "")
        desc = _normalize(item.description or "")
        store_name = _normalize(restaurant_name)

        exact = 1.0 if name == normalized_query else 0.0
        prefix = 1.0 if name.startswith(normalized_query) else 0.0
        token = _token_overlap(_tokenize(normalized_query), _tokenize(f"{name} {category} {desc}"))
        fuzzy = max(_fuzzy_similarity(normalized_query, name), _fuzzy_similarity(normalized_query, f"{name} {category}"))
        lexical = self._menu_lexical_signal(normalized_query, expanded_terms, item, restaurant_name)
        popularity = _menu_popularity(item)
        matched_store_boost = 0.04 if item.restaurant_id in matched_store_ids else 0.0
        intent_boost = 0.18 if normalized_query and name.startswith(normalized_query) else (0.10 if normalized_query and normalized_query in name else 0.0)

        score = (0.18 * exact) + (0.14 * prefix) + (0.20 * token) + (0.19 * fuzzy) + (0.20 * lexical) + (0.09 * popularity) + matched_store_boost + intent_boost
        if not item.is_available:
            score *= 0.85
        return min(1.0, score)

    def _store_lexical_signal(self, normalized_query: str, expanded_terms: set[str], store: RestaurantORM) -> float:
        haystack = _normalize(f"{store.name} {store.cuisine_type or ''} {store.description or ''}")
        return _expanded_term_overlap(expanded_terms, haystack, normalized_query)

    def _menu_lexical_signal(
        self,
        normalized_query: str,
        expanded_terms: set[str],
        item: MenuItemORM,
        restaurant_name: str,
    ) -> float:
        haystack = _normalize(f"{item.name} {item.category or ''} {item.description or ''}")
        return _expanded_term_overlap(expanded_terms, haystack, normalized_query)

    def _lexical_alternatives_from_ranked(
        self,
        ranked_menus: list[_ScoredMenu],
        seen_menu_ids: set[str],
        limit: int,
    ) -> list[dict]:
        alternatives: list[dict] = []
        for item in ranked_menus:
            if item.row.id in seen_menu_ids:
                continue
            if item.lexical < 0.10:
                continue
            alternatives.append(
                {
                    "id": item.row.id,
                    "entity_type": "menu",
                    "title": item.row.name,
                    "subtitle": item.row.category,
                    "restaurant_id": item.row.restaurant_id,
                    "restaurant_name": item.restaurant_name,
                    "image_url": item.row.image_url,
                    "price": float(item.row.price or 0),
                    "rating": None,
                    "score": round(item.lexical, 4),
                }
            )
            if len(alternatives) >= limit:
                break
        return alternatives


def _normalize(value: str) -> str:
    text = (value or "").strip().lower()
    if not text:
        return ""

    translation = str.maketrans(
        {
            "ç": "c",
            "ğ": "g",
            "ı": "i",
            "ö": "o",
            "ş": "s",
            "ü": "u",
            "â": "a",
            "î": "i",
            "û": "u",
        }
    )
    text = text.translate(translation)
    text = unicodedata.normalize("NFKD", text)
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = re.sub(r"[^a-z0-9\s]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _tokenize(value: str) -> list[str]:
    return [token for token in _normalize(value).split(" ") if len(token) >= 2]


def _token_overlap(query_tokens: Iterable[str], target_tokens: Iterable[str]) -> float:
    q = set(query_tokens)
    t = set(target_tokens)
    if not q or not t:
        return 0.0
    return len(q & t) / len(q)


def _fuzzy_similarity(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    dist = _levenshtein(a, b)
    denom = max(len(a), len(b))
    if denom == 0:
        return 0.0
    return max(0.0, 1.0 - (dist / denom))


def _levenshtein(a: str, b: str) -> int:
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)

    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        cur = [i]
        for j, cb in enumerate(b, start=1):
            insert_cost = cur[j - 1] + 1
            delete_cost = prev[j] + 1
            replace_cost = prev[j - 1] + (0 if ca == cb else 1)
            cur.append(min(insert_cost, delete_cost, replace_cost))
        prev = cur
    return prev[-1]


def _store_popularity(store: RestaurantORM) -> float:
    order_signal = math.log1p(max(0, int(store.successful_order_count or 0))) / 6.0
    rating_signal = max(0.0, min(1.0, float(store.average_rating or 0.0) / 5.0))
    vote_signal = math.log1p(max(0, int(store.rating_count or 0))) / 6.0
    recent_signal = _recent_store_signal(store.created_at)
    return max(0.0, min(1.0, (0.40 * order_signal) + (0.32 * rating_signal) + (0.13 * vote_signal) + (0.15 * recent_signal)))


def _menu_popularity(item: MenuItemORM) -> float:
    discount_signal = max(0.0, min(1.0, float(item.discount_percent or 0.0) / 50.0))
    availability_signal = 1.0 if item.is_available else 0.2
    return (0.35 * discount_signal) + (0.65 * availability_signal)


def _expand_query_terms(normalized_query: str) -> set[str]:
    base_tokens = set(_tokenize(normalized_query))
    if normalized_query:
        base_tokens.add(normalized_query)

    synonym_map = {
        "kebap": {"kebap", "kebab", "cag", "cag kebap", "adana", "urfa", "izgara", "ocakbasi"},
        "doner": {"doner", "doner kebap", "et doner", "tavuk doner", "shawarma"},
        "cag": {"cag", "cag kebap", "erzurum"},
        "burger": {"burger", "hamburger", "cheeseburger"},
        "pizza": {"pizza", "pide"},
        "lahmacun": {"lahmacun", "findik lahmacun"},
        "pide": {"pide", "karisik pide", "kiymali pide"},
    }

    expanded = set(base_tokens)
    for token in list(base_tokens):
        for key, values in synonym_map.items():
            if token == key or key in token or token in key:
                expanded.update(_normalize(value) for value in values)

    return {token for token in expanded if token}


def _sql_query_variants(query: str) -> list[str]:
    raw = (query or "").strip().lower()
    raw = re.sub(r"\s+", " ", raw)

    raw_terms: set[str] = set()
    if raw:
        raw_terms.add(raw)
        raw_terms.update(part for part in re.split(r"\s+", raw) if len(part) >= 2)

    normalized = _normalize(query)
    expanded = _expand_query_terms(normalized)
    terms = {term for term in (expanded | raw_terms) if term}
    return sorted(terms, key=len, reverse=True)[:8]


def _expanded_term_overlap(expanded_terms: set[str], haystack: str, normalized_query: str) -> float:
    if not haystack:
        return 0.0
    if normalized_query and normalized_query in haystack:
        return 1.0
    if not expanded_terms:
        return 0.0

    hits = 0
    best_partial = 0.0
    hay_tokens = set(_tokenize(haystack))

    for term in expanded_terms:
        if term in haystack:
            hits += 1
            continue
        term_tokens = set(_tokenize(term))
        if term_tokens and hay_tokens:
            overlap = len(term_tokens & hay_tokens) / len(term_tokens)
            best_partial = max(best_partial, overlap)

    direct_score = hits / max(1, len(expanded_terms))
    return max(direct_score, best_partial)


def _recent_store_signal(created_at: Optional[datetime]) -> float:
    if not created_at:
        return 0.0
    now = datetime.now(timezone.utc)
    created = created_at if created_at.tzinfo else created_at.replace(tzinfo=timezone.utc)
    age_days = max(0.0, (now - created).total_seconds() / 86400.0)
    if age_days <= 7:
        return 1.0
    if age_days <= 21:
        return 0.7
    if age_days <= 45:
        return 0.45
    return 0.0
