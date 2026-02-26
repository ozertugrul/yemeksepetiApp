"""
EmbeddingService — ozertuu/yemeksepeti-MiniLM-L12-v2 ile Türkçe yemek domain
embedding üretimi.

Kendi verilerimizle (menü öğeleri, sipariş açıklamaları) fine-tune edilmiş model:
https://huggingface.co/ozertuu/yemeksepeti-MiniLM-L12-v2

Çıktı: 384-boyutlu normalize vektör.
Model ilk çağrıda HuggingFace Hub'dan indirilir, sonraki çağrılar in-memory.
"""
from __future__ import annotations

import logging
from functools import lru_cache
from typing import TYPE_CHECKING, List, Optional

from app.core.config import get_settings

logger = logging.getLogger(__name__)

if TYPE_CHECKING:
    from sentence_transformers import SentenceTransformer


@lru_cache(maxsize=1)
def _load_model(model_name: str, max_seq_length: int):
    """Model'i bir kez yükle, singleton olarak tut."""
    try:
        from sentence_transformers import SentenceTransformer
    except ModuleNotFoundError:
        logger.warning(
            "sentence_transformers paketi kurulu değil. Embedding devre dışı bırakılacak."
        )
        return None

    logger.info(f"Embedding modeli yükleniyor: {model_name}")
    model = SentenceTransformer(model_name, device="cpu")
    model.max_seq_length = max_seq_length
    logger.info("Model yüklendi.")
    return model


class EmbeddingService:
    """
    Menü öğesi ve restoran metinlerinden 384-boyutlu vektör üretir.
    Model: ozertuu/yemeksepeti-MiniLM-L12-v2 (kendi verilerimizle fine-tuned).
    """

    def __init__(self):
        settings = get_settings()
        self._model_name = settings.embedding_model
        self._enabled = settings.use_embeddings
        self._batch_size = settings.embedding_batch_size
        self._max_seq_length = settings.embedding_max_seq_length

    @property
    def model(self) -> Optional["SentenceTransformer"]:
        if not self._enabled:
            return None
        return _load_model(self._model_name, self._max_seq_length)

    # ── Embedding üretimi ─────────────────────────────────────────────────────

    def embed_text(self, text: str) -> Optional[List[float]]:
        """Tek metin → 384-boyutlu float listesi (normalize)."""
        if not self._enabled or not text.strip():
            return None
        model = self.model
        if model is None:
            return None
        vec = model.encode(
            [text],
            normalize_embeddings=True,
            convert_to_numpy=True,
            batch_size=1,
        )[0]
        return vec.tolist()

    def embed_batch(self, texts: List[str]) -> List[List[float]]:
        """Toplu metin → embedding listesi (migration için)."""
        if not self._enabled:
            return [[] for _ in texts]
        if not texts:
            return []
        model = self.model
        if model is None:
            return [[] for _ in texts]
        vecs = model.encode(
            texts,
            normalize_embeddings=True,
            convert_to_numpy=True,
            batch_size=self._batch_size,
        )
        return [v.tolist() for v in vecs]

    # ── Menü öğesi metin şablonu ──────────────────────────────────────────────

    @staticmethod
    def menu_item_text(name: str, description: str, category: str) -> str:
        """
        Anlamlı embedding için yapılandırılmış metin.
        "Kategori: Burger | İsim: Cheeseburger | Açıklama: ..."
        """
        parts = [f"Kategori: {category}"] if category else []
        parts.append(f"İsim: {name}")
        if description:
            parts.append(f"Açıklama: {description}")
        return " | ".join(parts)

    @staticmethod
    def restaurant_text(name: str, cuisine_type: str, description: str) -> str:
        """Restoran embedding metni."""
        parts = [f"Mutfak: {cuisine_type}"] if cuisine_type else []
        parts.append(f"Restoran: {name}")
        if description:
            parts.append(f"Açıklama: {description}")
        return " | ".join(parts)

    # ── Cosine similarity (local, pgvector olmadan test için) ─────────────────

    @staticmethod
    def cosine_similarity(a: List[float], b: List[float]) -> float:
        if not a or not b or len(a) != len(b):
            return 0.0
        dot = sum(x * y for x, y in zip(a, b))
        norm_a = sum(x * x for x in a) ** 0.5
        norm_b = sum(y * y for y in b) ** 0.5
        denom = norm_a * norm_b
        return float(dot / denom) if denom > 0 else 0.0
