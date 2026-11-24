from __future__ import annotations

import os
import threading
import time
from pathlib import Path

import joblib

DEFAULT_PATH = Path(__file__).resolve().parents[2] / "model" / "model-1.0.0.joblib"


class SentimentModel:
    def __init__(self, path: str | os.PathLike | None = None) -> None:
        self.path = Path(path or os.getenv("MODEL_PATH") or DEFAULT_PATH)
        self.pipeline = None
        self.version = "unknown"
        self.labels = ["negative", "positive"]
        self.load_seconds: float | None = None

    def load(self) -> None:
        start = time.perf_counter()
        bundle = joblib.load(self.path)
        self.pipeline = bundle["pipeline"]
        self.version = bundle["version"]
        self.labels = bundle.get("labels", self.labels)
        self.load_seconds = round(time.perf_counter() - start, 3)

    @property
    def loaded(self) -> bool:
        return self.pipeline is not None

    def predict(self, texts: list[str]) -> list[dict]:
        proba = self.pipeline.predict_proba(texts)[:, 1]
        out = []
        for p in proba:
            p = float(p)
            positive = p >= 0.5
            out.append(
                {
                    "label": self.labels[1] if positive else self.labels[0],
                    "score": round(p if positive else 1 - p, 4),
                    "positive_proba": round(p, 4),
                }
            )
        return out


class Stats:
    """In-memory counters exposed by GET /metrics (per replica)."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.calls = 0
        self.texts = 0
        self.errors = 0
        self.total_ms = 0.0

    def record(self, n_texts: int, ms: float) -> None:
        with self._lock:
            self.calls += 1
            self.texts += n_texts
            self.total_ms += ms

    def record_error(self) -> None:
        with self._lock:
            self.errors += 1

    def snapshot(self) -> dict:
        with self._lock:
            mean = self.total_ms / self.calls if self.calls else 0.0
            return {
                "calls": self.calls,
                "texts_scored": self.texts,
                "errors": self.errors,
                "mean_latency_ms": round(mean, 2),
            }
