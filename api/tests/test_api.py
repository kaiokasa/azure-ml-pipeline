import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:  # runs the lifespan -> loads the model
        yield c


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok" and body["model_loaded"] is True
    assert body["model_load_seconds"] is not None


def test_version(client):
    r = client.get("/version")
    assert r.status_code == 200
    assert r.json()["model_version"] == "1.0.0"


def test_predict_success(client):
    r = client.post("/predict", json={"texts": ["Great phone, I love it!", "Terrible service, never again."]})
    assert r.status_code == 200
    body = r.json()
    assert body["count"] == 2
    assert [p["label"] for p in body["predictions"]] == ["positive", "negative"]
    assert all(0.5 <= p["score"] <= 1 for p in body["predictions"])
    assert body["latency_ms"] < 1000  # < 1 s on CPU


@pytest.mark.parametrize(
    "payload",
    [
        {"texts": []},  # empty list
        {"texts": "not a list"},  # wrong type
        {"texts": ["   "]},  # blank text
        {"texts": ["x" * 5001]},  # too long
        {"text": ["ok"]},  # unknown field
    ],
)
def test_predict_invalid_input(client, payload):
    assert client.post("/predict", json=payload).status_code == 422


def test_predict_missing_body(client):
    assert client.post("/predict").status_code == 422


def test_metrics_counts_calls(client):
    before = client.get("/metrics").json()["calls"]
    client.post("/predict", json={"texts": ["ok"]})
    after = client.get("/metrics").json()
    assert after["calls"] == before + 1
    assert after["mean_latency_ms"] >= 0
