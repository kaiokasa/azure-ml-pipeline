import json

import pytest

from pipeline.validation import (
    BlobRef,
    ValidationError,
    blob_from_event,
    check_metadata,
    inference_id,
    make_message,
    parse_lines,
    parse_message,
    summarize,
)

SUBJECT = "/blobServices/default/containers/input/blobs/batch/reviews-01.txt"


def test_blob_from_event():
    b = blob_from_event(SUBJECT, {"eTag": "0x8DC1", "contentLength": 42})
    assert b == BlobRef(name="batch/reviews-01.txt", etag="0x8DC1", size=42)


def test_event_outside_input_is_ignored():
    with pytest.raises(ValidationError):
        blob_from_event("/blobServices/default/containers/output/blobs/x.txt", {})


@pytest.mark.parametrize(
    ("name", "size", "reason"),
    [("a.csv", 10, "extension"), ("a.txt", 0, "empty"), ("a.txt", 2_000_000, "too large")],
)
def test_check_metadata_rejects(name, size, reason):
    with pytest.raises(ValidationError, match=reason):
        check_metadata(BlobRef(name, "e", size))


def test_check_metadata_accepts_uppercase_extension():
    check_metadata(BlobRef("A.TXT", "e", 10))


def test_parse_lines_ok_strips_blank_lines_and_bom():
    assert parse_lines("﻿Good\n\n  Bad  \r\n".encode()) == ["Good", "Bad"]


@pytest.mark.parametrize(
    ("content", "reason"),
    [
        (b"\xff\xfe\x00bad", "UTF-8"),
        (b"\n  \n", "no non-blank"),
        (("x\n" * 501).encode(), "too many lines"),
        (("y" * 5001).encode(), "longer than"),
    ],
)
def test_parse_lines_rejects(content, reason):
    with pytest.raises(ValidationError, match=reason):
        parse_lines(content)


def test_message_roundtrip_and_idempotency_key():
    blob = BlobRef("f.txt", "0x1", 5)
    assert parse_message(make_message(blob, "2026-11-24T10:00:00Z")) == blob
    assert inference_id(blob) == inference_id(BlobRef("f.txt", "0x1", 999))
    assert inference_id(blob) != inference_id(BlobRef("f.txt", "0x2", 5))


def test_malformed_message_raises():
    with pytest.raises(json.JSONDecodeError):
        parse_message("this is not json")
    with pytest.raises(KeyError):
        parse_message('{"foo": 1}')


def test_summarize():
    preds = [
        {"label": "negative", "score": 0.9},
        {"label": "positive", "score": 0.7},
        {"label": "negative", "score": 0.8},
    ]
    s = summarize(preds)
    assert s["count"] == 3 and s["negativeCount"] == 2
    assert s["prediction"] == "negative" and s["negativeShare"] == pytest.approx(0.6667)
    assert s["confidence"] == pytest.approx(0.8)
