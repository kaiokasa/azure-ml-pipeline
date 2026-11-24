"""Sentiment inference API (FastAPI).

GET  /health   status + model load time (liveness / readiness probe)
GET  /version  API and model versions
POST /predict  {"texts": ["...", ...]} -> one prediction per text
GET  /metrics  call count and mean latency (this replica)
"""

from __future__ import annotations

import logging
import os
import time
from contextlib import asynccontextmanager

# isort: off
# Telemetry must be configured before FastAPI is imported so it gets instrumented.
from app.telemetry import latency_histogram, predictions_counter
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

# isort: on
from app.model import SentimentModel, Stats
from app.schemas import HealthResponse, MetricsResponse, PredictRequest, PredictResponse, VersionResponse

API_VERSION = os.getenv("API_VERSION", "1.0.0")
GIT_SHA = os.getenv("GIT_SHA", "local")

log = logging.getLogger("api")
model = SentimentModel()
stats = Stats()


@asynccontextmanager
async def lifespan(_: FastAPI):
    model.load()
    log.info("model %s loaded in %ss", model.version, model.load_seconds)
    yield


app = FastAPI(title="Sentiment inference API", version=API_VERSION, lifespan=lifespan)


@app.exception_handler(Exception)
async def unhandled(_: Request, exc: Exception):
    stats.record_error()
    log.exception("unhandled error: %s", exc)
    return JSONResponse(status_code=500, content={"detail": "internal error"})


@app.get("/health", response_model=HealthResponse)
def health():
    if not model.loaded:
        raise HTTPException(status_code=503, detail="model not loaded")
    return HealthResponse(status="ok", model_loaded=True, model_load_seconds=model.load_seconds)


@app.get("/version", response_model=VersionResponse)
def version():
    return VersionResponse(api_version=API_VERSION, model_version=model.version, git_sha=GIT_SHA)


@app.post("/predict", response_model=PredictResponse)
def predict(body: PredictRequest):
    start = time.perf_counter()
    predictions = model.predict(body.texts)
    ms = round((time.perf_counter() - start) * 1000, 2)

    stats.record(len(body.texts), ms)
    attrs = {"model_version": model.version}
    predictions_counter.add(len(body.texts), attrs)
    latency_histogram.record(ms, attrs)
    return PredictResponse(model_version=model.version, count=len(predictions), latency_ms=ms, predictions=predictions)


@app.get("/metrics", response_model=MetricsResponse)
def get_metrics():
    return MetricsResponse(**stats.snapshot())
