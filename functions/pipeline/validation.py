"""Pure validation / parsing helpers (no Azure dependency -> unit-testable)."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import UTC, datetime

ALLOWED_EXTENSIONS = (".txt",)
MAX_FILE_BYTES = 1_000_000  # 1 MB
MAX_LINES = 500
MAX_LINE_CHARS = 5000
INPUT_PREFIX = "/blobServices/default/containers/input/blobs/"


class ValidationError(Exception):
    """File rejected: the message is the reason written to rejected/."""


@dataclass(frozen=True)
class BlobRef:
    name: str
    etag: str
    size: int


def blob_from_event(subject: str, data: dict) -> BlobRef:
    if not subject.startswith(INPUT_PREFIX):
        raise ValidationError(f"unexpected subject {subject}")
    name = subject[len(INPUT_PREFIX) :]
    etag = str(data.get("eTag", "")).strip('"')
    size = int(data.get("contentLength", 0))
    return BlobRef(name=name, etag=etag, size=size)


def check_metadata(blob: BlobRef, max_bytes: int = MAX_FILE_BYTES) -> None:
    if not blob.name.lower().endswith(ALLOWED_EXTENSIONS):
        raise ValidationError(f"extension not allowed (expected {', '.join(ALLOWED_EXTENSIONS)})")
    if blob.size <= 0:
        raise ValidationError("empty file")
    if blob.size > max_bytes:
        raise ValidationError(f"file too large: {blob.size} bytes > {max_bytes}")


def parse_lines(content: bytes) -> list[str]:
    """Schema: UTF-8 text, one review per line, 1..MAX_LINES non-blank lines of <= MAX_LINE_CHARS."""
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValidationError("file is not valid UTF-8 text") from exc
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        raise ValidationError("no non-blank line")
    if len(lines) > MAX_LINES:
        raise ValidationError(f"too many lines: {len(lines)} > {MAX_LINES}")
    too_long = [i + 1 for i, line in enumerate(lines) if len(line) > MAX_LINE_CHARS]
    if too_long:
        raise ValidationError(f"line(s) longer than {MAX_LINE_CHARS} chars: {too_long[:5]}")
    return lines


def make_message(blob: BlobRef, event_time: str | None = None) -> str:
    return json.dumps(
        {
            "blobName": blob.name,
            "eTag": blob.etag,
            "size": blob.size,
            "eventTime": event_time or datetime.now(UTC).isoformat(),
        }
    )


def parse_message(raw: str) -> BlobRef:
    """Raises ValueError/KeyError on a malformed message -> retried then sent to -poison."""
    msg = json.loads(raw)
    return BlobRef(name=str(msg["blobName"]), etag=str(msg["eTag"]), size=int(msg.get("size", 0)))


def inference_id(blob: BlobRef) -> str:
    """Idempotency key: same blob + same ETag => same document id (upsert)."""
    return hashlib.sha256(f"{blob.name}|{blob.etag}".encode()).hexdigest()[:32]


def summarize(predictions: list[dict]) -> dict:
    n = len(predictions)
    negatives = sum(1 for p in predictions if p["label"] == "negative")
    mean_conf = sum(p["score"] for p in predictions) / n if n else 0.0
    return {
        "count": n,
        "negativeCount": negatives,
        "negativeShare": round(negatives / n, 4) if n else 0.0,
        "prediction": "negative" if negatives * 2 > n else "positive",
        "confidence": round(mean_conf, 4),
    }
