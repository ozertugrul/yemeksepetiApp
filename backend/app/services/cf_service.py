"""
Saat-bazlı User-Based Collaborative Filtering servisi.

Pipeline:
  1. orders.items JSONB'den saat bazlı user-item-action mapping çıkar
  2. Zaman dilimine göre cosine similarity hesapla (kullanıcılar arası)
  3. Benzer kullanıcıların o dilimde aldığı ürünlerden skor üret
  4. Opsiyonel: MiniLM embedding benzerliği ile blend (α CF + β embedding)
  5. Sonuçları TTL'li in-memory cache ile sakla (Redis opsiyonel)

Zaman dilimleri (Europe/Istanbul):
  breakfast  → 06:00–10:59
  lunch      → 11:00–14:59
  afternoon  → 15:00–17:59
  dinner     → 18:00–22:59
  late_night → 23:00–05:59
"""
from __future__ import annotations

import logging
import math
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Set, Tuple

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger(__name__)

# ── Zaman Dilimleri ───────────────────────────────────────────────────────────

HOUR_SEGMENTS: Dict[str, List[int]] = {
    "breakfast":   list(range(6, 11)),          # 06–10
    "lunch":       list(range(11, 15)),         # 11–14
    "afternoon":   list(range(15, 18)),         # 15–17
    "dinner":      list(range(18, 23)),         # 18–22
    "late_night":  list(range(23, 24)) + list(range(0, 6)),  # 23–05
}

# Turkey offset: UTC+3
_TZ_OFFSET = timezone(timedelta(hours=3))

SEGMENT_LABELS_TR: Dict[str, str] = {
    "breakfast":   "Kahvaltı",
    "lunch":       "Öğle Yemeği",
    "afternoon":   "İkindi",
    "dinner":      "Akşam Yemeği",
    "late_night":  "Gece Atıştırmalığı",
}


def current_hour_turkey() -> int:
    """Türkiye saatindeki mevcut saat (0-23)."""
    return datetime.now(_TZ_OFFSET).hour


def get_time_segment(hour: int | None = None) -> str:
    """Saat → zaman dilimi etiketi."""
    if hour is None:
        hour = current_hour_turkey()
    for segment, hours in HOUR_SEGMENTS.items():
        if hour in hours:
            return segment
    return "dinner"


# ── Basit TTL Cache ──────────────────────────────────────────────────────────

_cache: Dict[str, Tuple[datetime, Any]] = {}
_CACHE_TTL = timedelta(minutes=15)


def _get_cached(key: str) -> Any | None:
    entry = _cache.get(key)
    if entry is None:
        return None
    ts, value = entry
    if datetime.now(timezone.utc) - ts > _CACHE_TTL:
        del _cache[key]
        return None
    return value


def _set_cached(key: str, value: Any) -> None:
    _cache[key] = (datetime.now(timezone.utc), value)


def invalidate_cf_cache() -> None:
    """Tüm CF önbelleğini temizle (yeni sipariş sonrası çağrılabilir)."""
    _cache.clear()


# ── Collaborative Filtering Service ──────────────────────────────────────────

class CollaborativeFilteringService:
    """
    Hafif, saat-bazlı user-based CF motoru.

    Kullanım:
        cf = CollaborativeFilteringService(db_session)
        recs = await cf.recommend(user_id="U1", top_n=10)
    """

    def __init__(
        self,
        db: AsyncSession,
        *,
        lookback_days: int = 90,
        min_similarity: float = 0.05,
        max_similar_users: int = 30,
        embedding_alpha: float = 0.0,   # 0 = sadece CF, >0 ise embedding blend
    ):
        self.db = db
        self.lookback_days = lookback_days
        self.min_similarity = min_similarity
        self.max_similar_users = max_similar_users
        self.embedding_alpha = embedding_alpha

    # ── 1. User-Item Matrisi ──────────────────────────────────────────────────

    async def _build_user_item_matrix(
        self,
        time_segment: str,
        city: str | None = None,
    ) -> Dict[str, Dict[str, float]]:
        """
        Verilen zaman dilimi için user-item etkileşim matrisi oluştur.
        Dönüş: {user_id: {menu_item_id: ağırlık}}
        """
        cache_key = f"uim:{time_segment}:{city or '*'}:{self.lookback_days}"
        cached = _get_cached(cache_key)
        if cached is not None:
            return cached

        hours = HOUR_SEGMENTS.get(time_segment, list(range(0, 24)))
        hour_list = ",".join(str(h) for h in hours)

        city_filter = ""
        params: dict[str, Any] = {"lookback": self.lookback_days}
        if city:
            city_filter = (
                "AND EXISTS ("
                "  SELECT 1 FROM restaurants r"
                "  WHERE r.id = o.restaurant_id AND LOWER(r.city) = LOWER(:city)"
                ")"
            )
            params["city"] = city

        sql = text(f"""
            SELECT
                o.user_id,
                item->>'menu_item_id'  AS menu_item_id,
                COUNT(*)               AS cnt
            FROM orders o,
                 LATERAL jsonb_array_elements(o.items) AS item
            WHERE o.status NOT IN ('cancelled', 'rejected')
              AND o.created_at >= NOW() - MAKE_INTERVAL(days => :lookback)
              AND EXTRACT(HOUR FROM o.created_at AT TIME ZONE 'Europe/Istanbul')::int
                  IN ({hour_list})
              {city_filter}
            GROUP BY o.user_id, item->>'menu_item_id'
        """)

        result = await self.db.execute(sql, params)
        rows = result.fetchall()

        matrix: Dict[str, Dict[str, float]] = defaultdict(dict)
        for user_id, item_id, cnt in rows:
            if item_id:
                # log(1+count) ağırlığı — tekrar eden siparişlere hafif bonus
                matrix[user_id][item_id] = math.log1p(cnt)

        matrix_dict = dict(matrix)
        _set_cached(cache_key, matrix_dict)
        logger.info(
            "CF matrix built: segment=%s city=%s users=%d items=%d",
            time_segment, city or "*", len(matrix_dict),
            len({i for items in matrix_dict.values() for i in items}),
        )
        return matrix_dict

    # ── 2. Cosine Similarity ──────────────────────────────────────────────────

    @staticmethod
    def _cosine_sim(a: Dict[str, float], b: Dict[str, float]) -> float:
        common = set(a) & set(b)
        if not common:
            return 0.0
        dot = sum(a[k] * b[k] for k in common)
        norm_a = math.sqrt(sum(v * v for v in a.values()))
        norm_b = math.sqrt(sum(v * v for v in b.values()))
        if norm_a == 0 or norm_b == 0:
            return 0.0
        return dot / (norm_a * norm_b)

    def _find_similar_users(
        self,
        user_id: str,
        matrix: Dict[str, Dict[str, float]],
    ) -> List[Tuple[str, float]]:
        """Hedef kullanıcıya en benzer top-K kullanıcıları bul."""
        target = matrix.get(user_id)
        if not target:
            return []

        sims: list[Tuple[str, float]] = []
        for other_id, other_vec in matrix.items():
            if other_id == user_id:
                continue
            s = self._cosine_sim(target, other_vec)
            if s >= self.min_similarity:
                sims.append((other_id, s))

        sims.sort(key=lambda x: x[1], reverse=True)
        return sims[: self.max_similar_users]

    # ── 3. Skor Hesaplama ────────────────────────────────────────────────────

    def _score_items(
        self,
        user_id: str,
        matrix: Dict[str, Dict[str, float]],
        similar_users: List[Tuple[str, float]],
    ) -> List[Tuple[str, float, int]]:
        """
        Benzer kullanıcıların tercih ettiği ama hedef kullanıcının almadığı ürünleri
        ağırlıklı olarak skorla.

        Dönüş: [(menu_item_id, score, supporter_count), ...]
        """
        user_items: Set[str] = set(matrix.get(user_id, {}).keys())
        item_scores: Dict[str, float] = defaultdict(float)
        item_supporters: Dict[str, int] = defaultdict(int)

        for sim_uid, sim_val in similar_users:
            for item_id, weight in matrix.get(sim_uid, {}).items():
                if item_id not in user_items:
                    item_scores[item_id] += sim_val * weight
                    item_supporters[item_id] += 1

        scored = sorted(item_scores.items(), key=lambda x: x[1], reverse=True)
        return [(iid, sc, item_supporters[iid]) for iid, sc in scored]

    # ── 4. Popüler Ürünler (fallback) ────────────────────────────────────────

    async def _popular_items(
        self,
        time_segment: str,
        city: str | None,
        limit: int,
    ) -> List[Tuple[str, float, int]]:
        """Zaman dilimine göre en çok sipariş edilen ürünler (cold-start / fallback)."""
        hours = HOUR_SEGMENTS.get(time_segment, list(range(0, 24)))
        hour_list = ",".join(str(h) for h in hours)

        city_filter = ""
        params: dict[str, Any] = {"lim": limit}
        if city:
            city_filter = (
                "AND EXISTS ("
                "  SELECT 1 FROM restaurants r"
                "  WHERE r.id = o.restaurant_id AND LOWER(r.city) = LOWER(:city)"
                ")"
            )
            params["city"] = city

        sql = text(f"""
            SELECT
                item->>'menu_item_id'        AS menu_item_id,
                COUNT(DISTINCT o.user_id)    AS user_count,
                COUNT(*)                     AS order_count
            FROM orders o,
                 LATERAL jsonb_array_elements(o.items) AS item
            WHERE o.status NOT IN ('cancelled', 'rejected')
              AND o.created_at >= NOW() - INTERVAL '30 days'
              AND EXTRACT(HOUR FROM o.created_at AT TIME ZONE 'Europe/Istanbul')::int
                  IN ({hour_list})
              {city_filter}
            GROUP BY item->>'menu_item_id'
            ORDER BY user_count DESC, order_count DESC
            LIMIT :lim
        """)

        result = await self.db.execute(sql, params)
        rows = result.fetchall()
        return [
            (row[0], round(float(row[1]), 4), int(row[1]))
            for row in rows
            if row[0]
        ]

    # ── 5. Ürün Detay Çekme ─────────────────────────────────────────────────

    async def _enrich_items(
        self,
        item_ids: List[str],
    ) -> Dict[str, Dict[str, Any]]:
        """menu_items tablosundan detay bilgilerini çek."""
        if not item_ids:
            return {}

        sql = text("""
            SELECT
                mi.id,
                mi.restaurant_id,
                mi.name,
                mi.description,
                mi.price,
                mi.image_url,
                mi.category,
                mi.discount_percent,
                mi.is_available,
                mi.option_groups,
                mi.suggested_ids,
                mi.created_at,
                r.name AS restaurant_name
            FROM menu_items mi
            JOIN restaurants r ON r.id = mi.restaurant_id
            WHERE mi.id = ANY(:ids)
              AND mi.is_available = true
              AND r.is_active = true
        """)

        result = await self.db.execute(sql, {"ids": item_ids})
        rows = result.fetchall()

        items: Dict[str, Dict[str, Any]] = {}
        for row in rows:
            items[row[0]] = {
                "id": row[0],
                "restaurant_id": row[1],
                "name": row[2],
                "description": row[3] or "",
                "price": row[4],
                "image_url": row[5],
                "category": row[6] or "Diğer",
                "discount_percent": row[7] or 0,
                "is_available": row[8],
                "option_groups": row[9] or [],
                "suggested_ids": row[10] or [],
                "created_at": row[11],
                "restaurant_name": row[12],
            }
        return items

    # ── 5b. Embedding Boost ──────────────────────────────────────────────────

    async def _embedding_boost_scores(
        self,
        user_id: str,
        candidate_ids: List[str],
        time_segment: str,
        city: str | None,
    ) -> Dict[str, float]:
        """
        Kullanıcının geçmiş siparişlerindeki ürün embedding'lerinin ortalamasını al,
        pgvector cosine similarity ile aday ürünlere benzerlik skoru hesapla.

        ozertuu/yemeksepeti-MiniLM-L12-v2 embedding'leri (384 boyut) kullanır.
        Dönüş: {menu_item_id: embedding_similarity_score (0-1)}
        """
        if not candidate_ids:
            return {}

        # Kullanıcının son siparişlerindeki ürünlerin embedding ortalaması
        avg_embedding_sql = text("""
            WITH user_items AS (
                SELECT DISTINCT item->>'menu_item_id' AS mid
                FROM orders o,
                     LATERAL jsonb_array_elements(o.items) AS item
                WHERE o.user_id = :uid
                  AND o.status NOT IN ('cancelled', 'rejected')
                  AND o.created_at >= NOW() - MAKE_INTERVAL(days => :lookback)
                LIMIT 50
            )
            SELECT AVG(mi.embedding) AS avg_emb
            FROM menu_items mi
            JOIN user_items ui ON ui.mid = mi.id
            WHERE mi.embedding IS NOT NULL
        """)

        result = await self.db.execute(
            avg_embedding_sql, {"uid": user_id, "lookback": self.lookback_days}
        )
        row = result.fetchone()
        if row is None or row[0] is None:
            return {}

        avg_emb = row[0]

        # Adayların embedding benzerliğini hesapla
        sim_sql = text("""
            SELECT
                mi.id,
                1 - (mi.embedding <=> :emb::vector) AS similarity
            FROM menu_items mi
            WHERE mi.id = ANY(:ids)
              AND mi.embedding IS NOT NULL
              AND mi.is_available = true
            ORDER BY similarity DESC
        """)

        result = await self.db.execute(sim_sql, {"emb": str(list(avg_emb)), "ids": candidate_ids})
        rows = result.fetchall()

        return {r[0]: max(0.0, float(r[1])) for r in rows}

    # ── 6. Kullanıcı Sipariş Sayısı (Cold-start tespiti) ────────────────────

    async def _user_order_count(self, user_id: str) -> int:
        """Son lookback_days gündeki sipariş sayısını hızlıca çek."""
        sql = text("""
            SELECT COUNT(*) FROM orders
            WHERE user_id = :uid
              AND status NOT IN ('cancelled', 'rejected')
              AND created_at >= NOW() - MAKE_INTERVAL(days => :lookback)
        """)
        result = await self.db.execute(
            sql, {"uid": user_id, "lookback": self.lookback_days}
        )
        row = result.scalar()
        return int(row) if row else 0

    # ── Near-cold-start blend yardımcısı ─────────────────────────────────────

    @staticmethod
    def _blend_cf_popular(
        cf_scored: List[Tuple[str, float, int]],
        popular_scored: List[Tuple[str, float, int]],
        cf_ratio: float = 0.6,
    ) -> List[Tuple[str, float, int]]:
        """
        1-3 siparişi olan kullanıcılar için CF sonuçlarını popüler ile harmanlayarak
        keşif çeşitliliğini artır.
        cf_ratio — CF ağırlığı (kalan kısım popüler).
        """
        merged: Dict[str, Tuple[float, int, str]] = {}
        for item_id, score, supporters in cf_scored:
            merged[item_id] = (score * cf_ratio, supporters, "cf")
        for item_id, score, supporters in popular_scored:
            if item_id in merged:
                old_score, old_sup, _ = merged[item_id]
                merged[item_id] = (old_score + score * (1 - cf_ratio), max(old_sup, supporters), "cf+popular")
            else:
                merged[item_id] = (score * (1 - cf_ratio), supporters, "popular")
        result = sorted(merged.items(), key=lambda x: x[1][0], reverse=True)
        return [(iid, sc, sup) for iid, (sc, sup, _) in result]

    # ── 7. Ana Öneri Fonksiyonu ──────────────────────────────────────────────

    async def recommend(
        self,
        user_id: str,
        *,
        time_segment: str | None = None,
        city: str | None = None,
        top_n: int = 15,
    ) -> Dict[str, Any]:
        """
        Kişiselleştirilmiş saat bazlı CF önerileri üret.

        Cold-start strateji:
          • 0 sipariş  → direkt popüler ürünler (matris oluşturulmaz)
          • 1-3 sipariş → CF + popüler blend (%60 CF, %40 popüler)
          • 4+ sipariş  → saf CF (+ opsiyonel embedding boost)

        Dönüş:
            {
                "time_segment": "lunch",
                "label": "Öğle Yemeği",
                "items": [
                    {"score": 0.82, "source": "cf", "supporters": 5, "item": {...}},
                    ...
                ]
            }
        """
        if not time_segment:
            time_segment = get_time_segment()

        # Sonuç cache kontrolü
        cache_key = f"rec:{user_id}:{time_segment}:{city or '*'}"
        cached = _get_cached(cache_key)
        if cached is not None:
            result = dict(cached)
            result["items"] = result["items"][:top_n]
            return result

        # ── Cold-start: sipariş sayısına göre dal ────────────────────────────
        order_count = await self._user_order_count(user_id)
        NEAR_COLD_THRESHOLD = 3  # bu eşik ve altı → near-cold-start

        if order_count == 0:
            # Tamamen yeni kullanıcı → popüler ürünlere direkt yönlendir
            logger.info(
                "CF cold-start: user=%s has 0 orders, returning popular items "
                "(segment=%s, city=%s)",
                user_id, time_segment, city or "*",
            )
            scored = await self._popular_items(time_segment, city, top_n * 2)
            source = "popular"
        else:
            # Matris oluştur & benzer kullanıcıları bul
            matrix = await self._build_user_item_matrix(time_segment, city)
            similar = self._find_similar_users(user_id, matrix)

            if similar:
                cf_scored = self._score_items(user_id, matrix, similar)

                if order_count <= NEAR_COLD_THRESHOLD:
                    # Near-cold-start: CF + popüler blend
                    logger.info(
                        "CF near-cold: user=%s orders=%d, blending CF with popular "
                        "(segment=%s)",
                        user_id, order_count, time_segment,
                    )
                    popular_scored = await self._popular_items(
                        time_segment, city, top_n * 2,
                    )
                    scored = self._blend_cf_popular(
                        cf_scored, popular_scored, cf_ratio=0.6,
                    )
                    source = "cf+popular"
                else:
                    scored = cf_scored
                    source = "cf"
            else:
                # Kullanıcı matrise giremedi veya benzer kimse yok → popüler
                logger.info(
                    "CF fallback: user=%s (orders=%d) has no similar users, "
                    "returning popular (segment=%s)",
                    user_id, order_count, time_segment,
                )
                scored = await self._popular_items(time_segment, city, top_n * 2)
                source = "popular"

        # Ürün detaylarını zenginleştir
        candidate_ids = [s[0] for s in scored[: top_n * 3]]
        enriched = await self._enrich_items(candidate_ids)

        # Embedding boost: α CF + (1-α) embedding blend (sadece CF kaynaklı ise)
        emb_scores: Dict[str, float] = {}
        use_blend = self.embedding_alpha > 0 and source in ("cf", "cf+popular")
        if use_blend:
            try:
                emb_scores = await self._embedding_boost_scores(
                    user_id, candidate_ids, time_segment, city,
                )
            except Exception:
                logger.warning("Embedding boost failed, falling back to pure CF", exc_info=True)

        alpha = self.embedding_alpha if emb_scores else 0.0

        items: List[Dict[str, Any]] = []
        for item_id, score, supporters in scored:
            if item_id not in enriched:
                continue
            cf_score = float(score)
            if alpha > 0 and item_id in emb_scores:
                blended = (1 - alpha) * cf_score + alpha * emb_scores[item_id]
            else:
                blended = cf_score
            items.append({
                "score": round(blended, 4),
                "source": "cf+emb" if (alpha > 0 and item_id in emb_scores) else source,
                "supporters": supporters,
                "item": enriched[item_id],
            })
            if len(items) >= top_n:
                break

        # Blend sonrası yeniden sırala
        if alpha > 0:
            items.sort(key=lambda x: x["score"], reverse=True)

        # Normalize scores to 0-1 range
        if items:
            max_score = max(float(it["score"]) for it in items) or 1.0
            for it in items:
                it["score"] = round(float(it["score"]) / max_score, 4)

        result: Dict[str, Any] = {
            "time_segment": time_segment,
            "label": SEGMENT_LABELS_TR.get(time_segment, time_segment),
            "items": items,
        }

        _set_cached(cache_key, result)
        return result

    # ── 7. Popüler (auth gerektirmeyen) ──────────────────────────────────────

    async def popular_now(
        self,
        *,
        city: str | None = None,
        top_n: int = 10,
    ) -> Dict[str, Any]:
        """
        Şu anki zaman diliminde en popüler ürünler (giriş yapmamış kullanıcılar için).
        """
        time_segment = get_time_segment()

        cache_key = f"pop:{time_segment}:{city or '*'}"
        cached = _get_cached(cache_key)
        if cached is not None:
            result_c: Dict[str, Any] = dict(cached)
            result_c["items"] = result_c["items"][:top_n]
            return result_c

        scored = await self._popular_items(time_segment, city, top_n * 2)
        candidate_ids = [s[0] for s in scored]
        enriched = await self._enrich_items(candidate_ids)

        items: List[Dict[str, Any]] = []
        for item_id, score, supporters in scored:
            if item_id not in enriched:
                continue
            items.append({
                "score": round(float(score), 4),
                "source": "popular",
                "supporters": supporters,
                "item": enriched[item_id],
            })
            if len(items) >= top_n:
                break

        if items:
            max_score = max(float(it["score"]) for it in items) or 1.0
            for it in items:
                it["score"] = round(float(it["score"]) / max_score, 4)

        result: Dict[str, Any] = {
            "time_segment": time_segment,
            "label": SEGMENT_LABELS_TR.get(time_segment, time_segment),
            "items": items,
        }

        _set_cached(cache_key, result)
        return result
