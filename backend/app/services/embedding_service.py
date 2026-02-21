"""
EmbeddingService — all-MiniLM-L6-v2 ile Türkçe destekli metin embedding üretimi.

Model ilk çağrıda HuggingFace cache'ten yüklenir (~90 MB).
Sonraki çağrılar in-memory model kullanır.
"""
from __future__ import annotations

import logging
from functools import lru_cache
from typing import List, Optional

import numpy as np
from sentence_transformers import SentenceTransformer

from app.core.config import get_settings

logger = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def _load_model(model_name: str) -> SentenceTransformer:
    """Model'i bir kez yükle, singleton olarak tut."""
    logger.info(f"Embedding modeli yükleniyor: {model_name}")
    model = SentenceTransformer(model_name)
    logger.info("Model yüklendi.")
    return model


class EmbeddingService:
    """
    Menü öğesi ve restoran metinlerinden 384-boyutlu vektör üretir.
    """

    def __init__(self):
        settings = get_settings()
        self._model_name = settings.embedding_model
        self._enabled = settings.use_embeddings

    @property
    def model(self) -> Optional[SentenceTransformer]:
        if not self._enabled:
            return None
        return _load_model(self._model_name)

    # ── Embedding üretimi ─────────────────────────────────────────────────────

    def embed_text(self, text: str) -> Optional[List[float]]:
        """Tek metin → 384-boyutlu float listesi."""
        if not self._enabled or not text.strip():
            return None
        vec = self.model.encode(text, normalize_embeddings=True)
        return vec.tolist()

    def embed_batch(self, texts: List[str]) -> List[List[float]]:
        """Toplu metin → embedding listesi (migration için)."""
        if not self._enabled:
            return [[] for _ in texts]
        vecs = self.model.encode(texts, normalize_embeddings=True, batch_size=64)
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
        va, vb = np.array(a), np.array(b)
        denom = np.linalg.norm(va) * np.linalg.norm(vb)
        return float(np.dot(va, vb) / denom) if denom > 0 else 0.0
