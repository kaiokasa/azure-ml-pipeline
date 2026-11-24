"""Event-driven inference pipeline - one Flex Consumption Function App, 3 functions (Python v2 model).

dispatcher : Event Grid (Microsoft.Storage.BlobCreated on input/) -> validate -> queue | rejected/
worker     : queue inference-requests -> API /predict -> output/ + Cosmos DB (idempotent upsert)
             5 attempts (host.json maxDequeueCount) then inference-requests-poison
recent     : GET /api/recent -> last 20 inferences (CORS restricted to the dashboard origin)
"""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import UTC, datetime

import azure.functions as func
from azure.core import MatchConditions
from azure.core.exceptions import ResourceModifiedError
from opentelemetry import metrics

from pipeline import clients
from pipeline.validation import (
    MAX_FILE_BYTES,
    ValidationError,
    blob_from_event,
    check_metadata,
    inference_id,
    make_message,
    parse_lines,
    parse_message,
    summarize,
)

log = logging.getLogger("pipeline")
log.setLevel(logging.INFO)
if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    from azure.monitor.opentelemetry import configure_azure_monitor

    configure_azure_monitor(logger_name="pipeline")

_meter = metrics.get_meter("pipeline")
m_inferences = _meter.create_counter("pipeline.inferences", unit="1", description="Files successfully scored")
m_texts = _meter.create_counter("pipeline.texts", unit="1", description="Lines scored")
m_errors = _meter.create_counter("pipeline.errors", unit="1", description="Worker failures (each attempt)")
m_rejected = _meter.create_counter("pipeline.rejected", unit="1", description="Files rejected by dispatcher")
m_latency = _meter.create_histogram("pipeline.model_latency_ms", unit="ms", description="API /predict latency")
m_duration = _meter.create_histogram("pipeline.end_to_end_ms", unit="ms", description="Worker processing time")

QUEUE = "inference-requests"
MAX_BYTES = int(os.getenv("MAX_FILE_BYTES", str(MAX_FILE_BYTES)))

app = func.FunctionApp()


def _reject(name: str, reason: str, content: bytes | None) -> None:
    svc = clients.blob_service()
    report = {"fileName": name, "reason": reason, "rejectedAt": datetime.now(UTC).isoformat()}
    if content is not None:
        svc.get_blob_client("rejected", name).upload_blob(content, overwrite=True, metadata={"reason": reason[:200]})
    svc.get_blob_client("rejected", f"{name}.reason.json").upload_blob(json.dumps(report, indent=2), overwrite=True)
    m_rejected.add(1)
    log.warning("file_rejected", extra={"fileName": name, "reason": reason})


# --------------------------------------------------------------------------- dispatcher
@app.function_name("dispatcher")
@app.event_grid_trigger(arg_name="event")
@app.queue_output(arg_name="out", queue_name=QUEUE, connection="STORAGE")
def dispatcher(event: func.EventGridEvent, out: func.Out[str]) -> None:
    data = event.get_json() or {}
    try:
        blob = blob_from_event(event.subject, data)
    except ValidationError:
        log.warning("ignored event %s", event.subject)
        return

    content: bytes | None = None
    try:
        check_metadata(blob, MAX_BYTES)
        content = clients.blob_service().get_blob_client("input", blob.name).download_blob().readall()
        lines = parse_lines(content)
    except ValidationError as exc:
        # Copy the file to rejected/ (unless it is huge: then only the reason file is written).
        if content is None and blob.size <= MAX_BYTES * 5:
            content = clients.blob_service().get_blob_client("input", blob.name).download_blob().readall()
        _reject(blob.name, str(exc), content)
        return

    out.set(make_message(blob, str(event.event_time) if event.event_time else None))
    log.info("file_queued", extra={"fileName": blob.name, "lines": len(lines), "eTag": blob.etag})


# --------------------------------------------------------------------------- worker
@app.function_name("worker")
@app.queue_trigger(arg_name="msg", queue_name=QUEUE, connection="STORAGE")
def worker(msg: func.QueueMessage) -> None:
    start = time.perf_counter()
    try:
        blob = parse_message(msg.get_body().decode("utf-8"))
        doc_id = inference_id(blob)
        container = clients.cosmos_container()

        # Idempotency: same blob+ETag already processed -> nothing to do.
        if container is not None:
            existing = list(
                container.query_items(
                    "SELECT VALUE c.id FROM c WHERE c.id = @id",
                    parameters=[{"name": "@id", "value": doc_id}],
                    partition_key=blob.name,
                )
            )
            if existing:
                log.info("already_processed", extra={"fileName": blob.name, "id": doc_id})
                return

        try:
            content = (
                clients.blob_service()
                .get_blob_client("input", blob.name)
                .download_blob(etag=f'"{blob.etag}"', match_condition=MatchConditions.IfNotModified)
                .readall()
            )
        except ResourceModifiedError:
            # The blob was overwritten after this event: its own BlobCreated event will handle it.
            log.info("superseded", extra={"fileName": blob.name, "eTag": blob.etag})
            return
        lines = parse_lines(content)

        api_start = time.perf_counter()
        resp = clients.http_client().post("/predict", json={"texts": lines})
        api_ms = (time.perf_counter() - api_start) * 1000
        resp.raise_for_status()
        result = resp.json()

        now = datetime.now(UTC)
        summary = summarize(result["predictions"])
        duration_ms = round((time.perf_counter() - start) * 1000, 1)
        output = {
            "id": doc_id,
            "fileName": blob.name,
            "eTag": blob.etag,
            "processedAt": now.isoformat(),
            "modelVersion": result["model_version"],
            "summary": summary,
            "items": [{"text": t, **p} for t, p in zip(lines, result["predictions"], strict=True)],
        }
        out_name = blob.name.rsplit(".", 1)[0] + ".json"
        clients.blob_service().get_blob_client("output", out_name).upload_blob(
            json.dumps(output, ensure_ascii=False, indent=2), overwrite=True
        )

        if container is not None:
            container.upsert_item(
                {
                    "id": doc_id,
                    "fileName": blob.name,
                    "day": now.strftime("%Y-%m-%d"),
                    "timestamp": now.isoformat(),
                    "prediction": summary["prediction"],
                    "confidence": summary["confidence"],
                    "negativeShare": summary["negativeShare"],
                    "count": summary["count"],
                    "modelVersion": result["model_version"],
                    "durationMs": duration_ms,
                    "modelLatencyMs": round(api_ms, 1),
                    "outputBlob": f"output/{out_name}",
                }
            )

        attrs = {"model_version": result["model_version"]}
        m_inferences.add(1, attrs)
        m_texts.add(summary["count"], attrs)
        m_latency.record(api_ms, attrs)
        m_duration.record(duration_ms, attrs)
        log.info(
            "inference_done",
            extra={
                "fileName": blob.name,
                "durationMs": duration_ms,
                "modelLatencyMs": round(api_ms, 1),
                "lines": summary["count"],
                "prediction": summary["prediction"],
                "modelVersion": result["model_version"],
            },
        )
    except Exception as exc:
        m_errors.add(1, {"error": type(exc).__name__})
        log.error(
            "inference_failed",
            extra={"dequeueCount": msg.dequeue_count, "error": f"{type(exc).__name__}: {exc}"[:500]},
        )
        raise  # -> retried; after maxDequeueCount (5) the message goes to inference-requests-poison


# --------------------------------------------------------------------------- recent
@app.function_name("recent")
@app.route(route="recent", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def recent(req: func.HttpRequest) -> func.HttpResponse:
    container = clients.cosmos_container()
    items = []
    if container is not None:
        items = list(
            container.query_items(
                "SELECT TOP 20 c.id, c.fileName, c.timestamp, c.prediction, c.confidence, c.negativeShare, "
                "c['count'], c.modelVersion, c.durationMs, c.modelLatencyMs FROM c ORDER BY c.timestamp DESC",
                enable_cross_partition_query=True,
            )
        )
    return func.HttpResponse(json.dumps(items), mimetype="application/json", headers={"Cache-Control": "no-store"})
