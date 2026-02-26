from __future__ import annotations

import json
import math
import random
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import numpy as np
import torch
from sentence_transformers import InputExample, SentenceTransformer, losses
from sentence_transformers.evaluation import EmbeddingSimilarityEvaluator
from sentence_transformers.trainer import SentenceTransformerTrainer
from torch import Tensor, nn
from torch.utils.data import DataLoader


@dataclass
class TrainConfig:
    dataset_dir_candidates: list[str]
    output_dir: str
    base_model: str
    epochs: int
    batch_size: int
    lr: float
    max_seq_length: int
    warmup_ratio: float
    seed: int
    eval_size: int
    log_every_steps: int
    loss_log_file: str
    max_replication_factor: int
    eval_negative_ratio: int
    user_profile_max_items: int
    user_profile_decay: float
    encoding_batch_size: int


# Kaggle'da doğrudan çalışacak inline config.
KAGGLE_CONFIG = TrainConfig(
    dataset_dir_candidates=[
        "/kaggle/input/ds-refined",
        "/kaggle/input/ds_refined",
        "/kaggle/working/ds_refined",
        "./ds_refined",
    ],
    output_dir="/kaggle/working/menu-embedding-model",
    base_model="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
    epochs=3,
    batch_size=64,
    lr=2e-5,
    max_seq_length=128,
    warmup_ratio=0.1,
    seed=42,
    eval_size=3000,
    log_every_steps=25,
    loss_log_file="loss_log.jsonl",
    max_replication_factor=6,
    eval_negative_ratio=2,
    user_profile_max_items=80,
    user_profile_decay=0.96,
    encoding_batch_size=256,
)


class LoggedMultipleNegativesRankingLoss(nn.Module):
    """MultipleNegativesRankingLoss wrapper'ı: adım bazlı loss logu tutar."""

    def __init__(
        self,
        model: SentenceTransformer,
        output_dir: Path,
        log_every_steps: int,
        log_file_name: str,
    ):
        super().__init__()
        self.base_loss = losses.MultipleNegativesRankingLoss(model)
        self.log_every_steps = max(1, log_every_steps)
        self.global_step = 0
        self._window_losses: list[float] = []
        self._window_start = time.time()
        self.log_path = output_dir / log_file_name

        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self.log_path.write_text("", encoding="utf-8")

    def _append_log(self, payload: dict) -> None:
        with self.log_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(payload, ensure_ascii=False) + "\n")

    def forward(self, sentence_features, labels: Tensor) -> Tensor:
        loss = self.base_loss(sentence_features, labels)
        self.global_step += 1

        current = float(loss.detach().cpu().item())
        self._window_losses.append(current)

        if self.global_step % self.log_every_steps == 0:
            now = time.time()
            avg_loss = sum(self._window_losses) / len(self._window_losses)
            payload = {
                "type": "train",
                "step": self.global_step,
                "loss": current,
                "avgLossWindow": avg_loss,
                "windowSize": len(self._window_losses),
                "windowSec": round(now - self._window_start, 3),
            }
            self._append_log(payload)
            print(
                f"[TRAIN] step={self.global_step} loss={current:.6f} "
                f"avg({len(self._window_losses)})={avg_loss:.6f}"
            )
            self._window_losses = []
            self._window_start = now

        return loss


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def _patch_trainer_compatibility() -> dict[str, Any]:
    patched = False

    if not hasattr(SentenceTransformerTrainer, "_nested_gather"):
        patched = True

        def _nested_gather_fallback(self, values):
            return values

        SentenceTransformerTrainer._nested_gather = _nested_gather_fallback  # type: ignore[attr-defined]

    return {
        "patchedNestedGather": patched,
        "trainerClass": SentenceTransformerTrainer.__name__,
    }


def _find_dataset_dir(candidates: list[str]) -> Path:
    for candidate in candidates:
        path = Path(candidate)
        if (path / "train_pairs.jsonl").exists() and (path / "menu_items.jsonl").exists() and (path / "user_histories.jsonl").exists():
            return path
    checked = "\n".join(candidates)
    raise RuntimeError(f"Dataset bulunamadı. Kontrol edilen path'ler:\n{checked}")


def _load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def _build_menu_maps(menu_rows: list[dict[str, Any]]) -> tuple[dict[str, str], dict[str, dict[str, Any]]]:
    text_by_item_id: dict[str, str] = {}
    meta_by_item_id: dict[str, dict[str, Any]] = {}
    for row in menu_rows:
        item_id = str(row.get("menuItemId") or "").strip()
        if not item_id:
            continue
        text_value = str(row.get("text") or "").strip()
        if not text_value:
            text_value = str(row.get("name") or "").strip()
        if not text_value:
            continue

        text_by_item_id[item_id] = text_value
        meta_by_item_id[item_id] = {
            "restaurantId": str(row.get("restaurantId") or ""),
            "category": str(row.get("category") or ""),
            "cuisineType": str(row.get("cuisineType") or ""),
            "isAvailable": bool(row.get("isAvailable", True)),
        }
    return text_by_item_id, meta_by_item_id


def _build_positive_rows(
    pair_rows: list[dict[str, Any]],
    text_by_item_id: dict[str, str],
    max_replication_factor: int,
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    positives: list[dict[str, Any]] = []
    missing_text = 0
    self_pairs = 0

    for row in pair_rows:
        anchor_id = str(row.get("anchorId") or row.get("anchor_id") or "").strip()
        positive_id = str(row.get("positiveId") or row.get("positive_id") or "").strip()
        if not anchor_id or not positive_id:
            continue
        if anchor_id == positive_id:
            self_pairs += 1
            continue

        anchor_text = str(row.get("anchorText") or "").strip() or text_by_item_id.get(anchor_id, "")
        positive_text = str(row.get("positiveText") or "").strip() or text_by_item_id.get(positive_id, "")
        if not anchor_text or not positive_text:
            missing_text += 1
            continue

        damped_weight = int(row.get("dampedWeight") or row.get("weight") or 1)
        replication = max(1, min(max_replication_factor, max(1, damped_weight // 100)))

        positives.append(
            {
                "anchorId": anchor_id,
                "positiveId": positive_id,
                "anchorText": anchor_text,
                "positiveText": positive_text,
                "weight": int(row.get("weight") or 1),
                "dampedWeight": damped_weight,
                "replication": replication,
            }
        )

    return positives, {
        "missingTextRows": missing_text,
        "selfPairs": self_pairs,
    }


def _build_training_examples(positive_rows: list[dict[str, Any]]) -> list[InputExample]:
    examples: list[InputExample] = []
    for row in positive_rows:
        for _ in range(int(row["replication"])):
            examples.append(InputExample(texts=[row["anchorText"], row["positiveText"]], label=1.0))
    if not examples:
        raise RuntimeError("Geçerli training example üretilemedi.")
    return examples


def _split_train_eval_rows(
    positive_rows: list[dict[str, Any]],
    eval_size: int,
    seed: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    by_anchor: dict[str, list[dict[str, Any]]] = {}
    for row in positive_rows:
        by_anchor.setdefault(row["anchorId"], []).append(row)

    anchors = list(by_anchor.keys())
    rnd = random.Random(seed)
    rnd.shuffle(anchors)

    target_eval = max(500, min(eval_size, len(positive_rows) // 5))
    eval_rows: list[dict[str, Any]] = []
    train_rows: list[dict[str, Any]] = []
    eval_count = 0

    for anchor_id in anchors:
        rows = by_anchor[anchor_id]
        if eval_count < target_eval:
            eval_rows.extend(rows)
            eval_count += len(rows)
        else:
            train_rows.extend(rows)

    if not train_rows or not eval_rows:
        raise RuntimeError("Train/Eval split başarısız. Veri hacmi yetersiz olabilir.")
    return train_rows, eval_rows


def _build_evaluator(
    eval_rows: list[dict[str, Any]],
    text_by_item_id: dict[str, str],
    eval_negative_ratio: int,
    seed: int,
) -> EmbeddingSimilarityEvaluator:
    rnd = random.Random(seed)
    all_item_ids = list(text_by_item_id.keys())

    sentence1: list[str] = []
    sentence2: list[str] = []
    scores: list[float] = []

    for row in eval_rows:
        anchor_text = row["anchorText"]
        positive_text = row["positiveText"]
        sentence1.append(anchor_text)
        sentence2.append(positive_text)
        scores.append(1.0)

        anchor_id = row["anchorId"]
        positive_id = row["positiveId"]

        neg_needed = max(1, eval_negative_ratio)
        neg_created = 0
        while neg_created < neg_needed and all_item_ids:
            neg_id = rnd.choice(all_item_ids)
            if neg_id in (anchor_id, positive_id):
                continue
            neg_text = text_by_item_id.get(neg_id, "")
            if not neg_text:
                continue
            sentence1.append(anchor_text)
            sentence2.append(neg_text)
            scores.append(0.0)
            neg_created += 1

    return EmbeddingSimilarityEvaluator(sentence1, sentence2, scores, name="menu-embedding-eval")


def _append_jsonl(path: Path, payload: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as file:
        file.write(json.dumps(payload, ensure_ascii=False) + "\n")


def _mean_pool(vectors: np.ndarray, weights: np.ndarray) -> np.ndarray:
    weights_sum = float(weights.sum())
    if weights_sum <= 0:
        return vectors.mean(axis=0)
    weighted = vectors * weights[:, None]
    return weighted.sum(axis=0) / weights_sum


def _build_user_profiles(
    model: SentenceTransformer,
    user_rows: list[dict[str, Any]],
    text_by_item_id: dict[str, str],
    output_dir: Path,
    max_items: int,
    decay: float,
    batch_size: int,
) -> dict[str, Any]:
    ordered_user_ids: list[str] = []
    profile_vectors: list[np.ndarray] = []
    profile_logs: list[dict[str, Any]] = []

    for user_row in user_rows:
        user_id = str(user_row.get("userId") or "").strip()
        if not user_id:
            continue

        score_map: dict[str, float] = {}

        top_items = user_row.get("topItems") or []
        for item in top_items:
            item_id = str(item.get("menuItemId") or "").strip()
            if item_id not in text_by_item_id:
                continue
            count_value = float(item.get("count") or 0)
            if count_value <= 0:
                continue
            score_map[item_id] = score_map.get(item_id, 0.0) + math.log1p(count_value)

        events = user_row.get("events") or []
        total_events = len(events)
        for index, event in enumerate(events):
            recency_weight = decay ** max(0, total_events - index - 1)
            item_ids = event.get("itemIds") or []
            if not item_ids:
                continue
            per_item_weight = recency_weight / max(1, len(item_ids))
            for item_id in item_ids:
                key = str(item_id)
                if key not in text_by_item_id:
                    continue
                score_map[key] = score_map.get(key, 0.0) + per_item_weight

        if not score_map:
            continue

        ranked = sorted(score_map.items(), key=lambda x: x[1], reverse=True)[:max_items]
        item_ids = [item_id for item_id, _ in ranked]
        weights = np.array([score for _, score in ranked], dtype=np.float32)
        texts = [text_by_item_id[item_id] for item_id in item_ids]

        embeddings = model.encode(
            texts,
            batch_size=batch_size,
            normalize_embeddings=True,
            convert_to_numpy=True,
            show_progress_bar=False,
        ).astype(np.float32)

        profile = _mean_pool(embeddings, weights)
        norm = float(np.linalg.norm(profile))
        if norm > 0:
            profile = profile / norm

        ordered_user_ids.append(user_id)
        profile_vectors.append(profile)
        profile_logs.append(
            {
                "userId": user_id,
                "itemsUsed": len(item_ids),
                "maxItemScore": float(weights.max()) if len(weights) else 0.0,
            }
        )

    if not profile_vectors:
        raise RuntimeError("User profile embedding üretilemedi. user_histories içeriğini kontrol edin.")

    user_matrix = np.vstack(profile_vectors).astype(np.float32)
    np.save(output_dir / "user_embeddings.npy", user_matrix)
    (output_dir / "user_ids.json").write_text(json.dumps(ordered_user_ids, ensure_ascii=False), encoding="utf-8")
    (output_dir / "user_profile_stats.json").write_text(
        json.dumps(
            {
                "users": len(ordered_user_ids),
                "embeddingDim": int(user_matrix.shape[1]),
                "avgItemsUsed": round(float(np.mean([r["itemsUsed"] for r in profile_logs])), 3),
                "p90ItemsUsed": int(np.percentile([r["itemsUsed"] for r in profile_logs], 90)),
                "maxItemsUsed": int(max(r["itemsUsed"] for r in profile_logs)),
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    return {
        "users": len(ordered_user_ids),
        "embeddingDim": int(user_matrix.shape[1]),
    }


def _export_menu_embeddings(
    model: SentenceTransformer,
    text_by_item_id: dict[str, str],
    output_dir: Path,
    batch_size: int,
) -> dict[str, Any]:
    menu_item_ids = list(text_by_item_id.keys())
    menu_texts = [text_by_item_id[item_id] for item_id in menu_item_ids]
    menu_embeddings = model.encode(
        menu_texts,
        batch_size=batch_size,
        normalize_embeddings=True,
        convert_to_numpy=True,
        show_progress_bar=True,
    ).astype(np.float32)
    np.save(output_dir / "menu_embeddings.npy", menu_embeddings)
    (output_dir / "menu_item_ids.json").write_text(json.dumps(menu_item_ids, ensure_ascii=False), encoding="utf-8")
    return {
        "menuItems": len(menu_item_ids),
        "embeddingDim": int(menu_embeddings.shape[1]),
    }


def train(cfg: TrainConfig) -> dict:
    set_seed(cfg.seed)
    compatibility = _patch_trainer_compatibility()

    dataset_dir = _find_dataset_dir(cfg.dataset_dir_candidates)
    output_dir = Path(cfg.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    run_log_path = output_dir / "run_log.jsonl"
    run_log_path.write_text("", encoding="utf-8")
    _append_jsonl(
        run_log_path,
        {
            "type": "run_start",
            "datasetDir": str(dataset_dir),
            "config": asdict(cfg),
            "compatibility": compatibility,
        },
    )

    summary_path = dataset_dir / "summary.json"
    dataset_summary = json.loads(summary_path.read_text(encoding="utf-8")) if summary_path.exists() else {}

    menu_rows = _load_jsonl(dataset_dir / "menu_items.jsonl")
    pair_rows = _load_jsonl(dataset_dir / "train_pairs.jsonl")
    user_rows = _load_jsonl(dataset_dir / "user_histories.jsonl")

    if not menu_rows or not pair_rows or not user_rows:
        raise RuntimeError("Dataset dosyalarından en az biri boş. menu_items/train_pairs/user_histories kontrol edin.")

    text_by_item_id, meta_by_item_id = _build_menu_maps(menu_rows)
    positive_rows, quality_counters = _build_positive_rows(pair_rows, text_by_item_id, cfg.max_replication_factor)

    if not positive_rows:
        raise RuntimeError("Geçerli positive pair kalmadı. Dataset temizliği çok agresif olabilir.")

    train_rows, eval_rows = _split_train_eval_rows(positive_rows, cfg.eval_size, cfg.seed)
    train_examples = _build_training_examples(train_rows)

    evaluator = _build_evaluator(
        eval_rows=eval_rows,
        text_by_item_id=text_by_item_id,
        eval_negative_ratio=cfg.eval_negative_ratio,
        seed=cfg.seed,
    )

    dataset_stats = {
        "summary": dataset_summary,
        "menuRows": len(menu_rows),
        "menuRowsUsable": len(text_by_item_id),
        "pairRowsRaw": len(pair_rows),
        "pairRowsUsable": len(positive_rows),
        "trainRows": len(train_rows),
        "evalRows": len(eval_rows),
        "trainExamplesAfterReplication": len(train_examples),
        "userRows": len(user_rows),
        "quality": quality_counters,
        "availableMenuRatio": round(
            sum(1 for x in meta_by_item_id.values() if x["isAvailable"]) / max(1, len(meta_by_item_id)),
            6,
        ),
    }
    (output_dir / "dataset_stats.json").write_text(json.dumps(dataset_stats, ensure_ascii=False, indent=2), encoding="utf-8")
    _append_jsonl(run_log_path, {"type": "dataset_stats", **dataset_stats})

    model = SentenceTransformer(cfg.base_model, device="cuda" if torch.cuda.is_available() else "cpu")
    model.max_seq_length = cfg.max_seq_length

    train_loader = DataLoader(train_examples, shuffle=True, batch_size=cfg.batch_size, drop_last=True)
    train_loss = LoggedMultipleNegativesRankingLoss(
        model=model,
        output_dir=output_dir,
        log_every_steps=cfg.log_every_steps,
        log_file_name=cfg.loss_log_file,
    )

    warmup_steps = math.ceil(len(train_loader) * cfg.epochs * cfg.warmup_ratio)
    _append_jsonl(
        run_log_path,
        {
            "type": "fit_start",
            "device": "cuda" if torch.cuda.is_available() else "cpu",
            "warmupSteps": warmup_steps,
            "epochs": cfg.epochs,
            "batchSize": cfg.batch_size,
            "trainBatchesPerEpoch": len(train_loader),
        },
    )

    def eval_callback(score: float, epoch: int, steps: int) -> None:
        payload = {
            "type": "eval",
            "epoch": int(epoch),
            "steps": int(steps),
            "score": float(score),
        }
        train_loss._append_log(payload)
        _append_jsonl(run_log_path, payload)
        print(f"[EVAL] epoch={epoch} steps={steps} score={score:.6f}")

    model.fit(
        train_objectives=[(train_loader, train_loss)],
        evaluator=evaluator,
        epochs=cfg.epochs,
        warmup_steps=warmup_steps,
        optimizer_params={"lr": cfg.lr},
        output_path=str(output_dir),
        show_progress_bar=True,
        save_best_model=True,
        callback=eval_callback,
    )

    # Her durumda nihai modeli de ayrı klasöre yaz (best checkpoint'e ek güvence).
    final_dir = output_dir / "final"
    final_dir.mkdir(parents=True, exist_ok=True)
    model.save(str(final_dir))

    menu_export_meta = _export_menu_embeddings(
        model=model,
        text_by_item_id=text_by_item_id,
        output_dir=output_dir,
        batch_size=cfg.encoding_batch_size,
    )
    user_export_meta = _build_user_profiles(
        model=model,
        user_rows=user_rows,
        text_by_item_id=text_by_item_id,
        output_dir=output_dir,
        max_items=cfg.user_profile_max_items,
        decay=cfg.user_profile_decay,
        batch_size=cfg.encoding_batch_size,
    )

    best_artifacts = sorted([p.name for p in output_dir.iterdir()])
    final_artifacts = sorted([p.name for p in final_dir.iterdir()])

    meta = {
        "datasetDir": str(dataset_dir),
        "compatibility": compatibility,
        "trainExamples": len(train_examples),
        "evalRows": len(eval_rows),
        "allPositiveRows": len(positive_rows),
        "device": "cuda" if torch.cuda.is_available() else "cpu",
        "bestModelPath": str(output_dir),
        "finalModelPath": str(final_dir),
        "bestArtifacts": best_artifacts,
        "finalArtifacts": final_artifacts,
        "lossLogPath": str(train_loss.log_path),
        "runLogPath": str(run_log_path),
        "rawPairRows": len(pair_rows),
        "menuEmbeddings": menu_export_meta,
        "userEmbeddings": user_export_meta,
        "config": asdict(cfg),
    }
    (output_dir / "training_meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    _append_jsonl(run_log_path, {"type": "run_end", "result": meta})
    return meta


def main() -> None:
    cfg = KAGGLE_CONFIG
    result = train(cfg)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
