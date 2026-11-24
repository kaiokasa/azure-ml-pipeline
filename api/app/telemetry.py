"""OpenTelemetry setup (Azure Monitor distro) + custom metrics.

Telemetry is only exported when APPLICATIONINSIGHTS_CONNECTION_STRING is set,
so local runs and tests need no Azure resource.
"""

from __future__ import annotations

import logging
import os

from opentelemetry import metrics

log = logging.getLogger("api")

if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    from azure.monitor.opentelemetry import configure_azure_monitor

    configure_azure_monitor(logger_name="api")
    log.setLevel(logging.INFO)
    log.info("Azure Monitor OpenTelemetry configured")

_meter = metrics.get_meter("api")
predictions_counter = _meter.create_counter(
    "api.predictions", unit="1", description="Number of texts scored by the model"
)
latency_histogram = _meter.create_histogram(
    "api.model_latency_ms", unit="ms", description="Model inference latency per /predict call"
)
