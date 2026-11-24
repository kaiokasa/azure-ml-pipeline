"""Train the sentiment model served by the API.

Dataset : UCI "Sentiment Labelled Sentences" (Kotzias et al., KDD 2015)
          https://archive.ics.uci.edu/dataset/331  -  licence CC BY 4.0
          3 000 sentences (Amazon, Yelp, IMDb), label 0 = negative, 1 = positive.
Model   : TF-IDF (word 1-2 grams + char 2-5 grams) + logistic regression.
Baseline: DummyClassifier (most frequent class), as asked in "cours 4".

Usage   : python train.py            (downloads the data on first run)
Outputs : model-<VERSION>.joblib, metrics.json
"""

from __future__ import annotations

import io
import json
import platform
import random
import time
import urllib.request
import zipfile
from pathlib import Path

import joblib
import numpy as np
import sklearn
from sklearn.dummy import DummyClassifier
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, f1_score, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import FeatureUnion, Pipeline

MODEL_VERSION = "1.0.0"
SEED = 42
DATA_URL = "https://archive.ics.uci.edu/static/public/331/sentiment+labelled+sentences.zip"
HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
SOURCES = ("amazon_cells_labelled.txt", "yelp_labelled.txt", "imdb_labelled.txt")


def download() -> None:
    if all((DATA_DIR / s).exists() for s in SOURCES):
        return
    DATA_DIR.mkdir(exist_ok=True)
    print(f"Downloading {DATA_URL}")
    with urllib.request.urlopen(DATA_URL, timeout=60) as resp:
        outer = zipfile.ZipFile(io.BytesIO(resp.read()))
    # The UCI archive contains the dataset folder (sometimes nested in a second zip).
    archives = [outer]
    for name in outer.namelist():
        if name.endswith(".zip"):
            archives.append(zipfile.ZipFile(io.BytesIO(outer.read(name))))
    for archive in archives:
        for name in archive.namelist():
            base = name.rsplit("/", 1)[-1]
            if base in SOURCES and "__MACOSX" not in name:
                (DATA_DIR / base).write_bytes(archive.read(name))
    missing = [s for s in SOURCES if not (DATA_DIR / s).exists()]
    if missing:
        raise RuntimeError(f"Files missing from archive: {missing}")


def load() -> tuple[list[str], list[int]]:
    texts, labels = [], []
    for source in SOURCES:
        for line in (DATA_DIR / source).read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line or "\t" not in line:
                continue
            text, label = line.rsplit("\t", 1)
            if label.strip() in {"0", "1"}:
                texts.append(text.strip())
                labels.append(int(label))
    return texts, labels


def build_model() -> Pipeline:
    features = FeatureUnion(
        [
            ("word", TfidfVectorizer(ngram_range=(1, 2), min_df=1, sublinear_tf=True, lowercase=True)),
            ("char", TfidfVectorizer(analyzer="char_wb", ngram_range=(2, 5), min_df=2, sublinear_tf=True)),
        ]
    )
    return Pipeline([("features", features), ("clf", LogisticRegression(C=4.0, max_iter=2000, random_state=SEED))])


def evaluate(model, x_test, y_test) -> dict:
    proba = model.predict_proba(x_test)[:, 1]
    pred = (proba >= 0.5).astype(int)
    return {
        "accuracy": round(float(accuracy_score(y_test, pred)), 4),
        "f1": round(float(f1_score(y_test, pred, zero_division=0)), 4),
        "roc_auc": round(float(roc_auc_score(y_test, proba)), 4),
    }


def main() -> None:
    random.seed(SEED)
    np.random.seed(SEED)
    download()
    texts, labels = load()
    x_train, x_test, y_train, y_test = train_test_split(
        texts, labels, test_size=0.2, random_state=SEED, stratify=labels
    )

    baseline = DummyClassifier(strategy="most_frequent").fit(x_train, y_train)
    model = build_model().fit(x_train, y_train)

    # Inference latency on CPU (a typical uploaded file = up to 500 lines)
    batch = x_test[:500]
    start = time.perf_counter()
    model.predict_proba(batch)
    batch_ms = (time.perf_counter() - start) * 1000

    out_path = HERE / f"model-{MODEL_VERSION}.joblib"
    joblib.dump({"pipeline": model, "version": MODEL_VERSION, "labels": ["negative", "positive"]}, out_path)

    metrics = {
        "model_version": MODEL_VERSION,
        "dataset": "UCI Sentiment Labelled Sentences (CC BY 4.0)",
        "n_train": len(x_train),
        "n_test": len(x_test),
        "seed": SEED,
        "model": evaluate(model, x_test, y_test),
        "baseline_most_frequent": evaluate(baseline, x_test, y_test),
        "inference_ms_for_500_lines": round(batch_ms, 1),
        "model_size_kb": round(out_path.stat().st_size / 1024, 1),
        "python": platform.python_version(),
        "scikit_learn": sklearn.__version__,
    }
    (HERE / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
