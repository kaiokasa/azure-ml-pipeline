from __future__ import annotations

from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

Text = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=5000)]


class PredictRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    texts: list[Text] = Field(..., min_length=1, max_length=500, description="One review per item")


class Prediction(BaseModel):
    label: str
    score: float = Field(..., description="Probability of the predicted label")
    positive_proba: float


class PredictResponse(BaseModel):
    model_version: str
    count: int
    latency_ms: float
    predictions: list[Prediction]


class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    model_load_seconds: float | None


class VersionResponse(BaseModel):
    api_version: str
    model_version: str
    git_sha: str


class MetricsResponse(BaseModel):
    calls: int
    texts_scored: int
    errors: int
    mean_latency_ms: float
