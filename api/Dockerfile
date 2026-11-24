# Build from the repository root:  docker build -f api/Dockerfile -t sentiment-api .
# ---------- stage 1 : build wheels / install deps ----------
FROM python:3.12-slim AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY api/requirements.txt .
RUN pip install --prefix=/install -r requirements.txt \
 && find /install -type d -name "__pycache__" -prune -exec rm -rf {} + \
 && find /install -type d -name "tests" -path "*site-packages/*" -prune -exec rm -rf {} +

# ---------- stage 2 : runtime ----------
FROM python:3.12-slim AS runtime
ARG API_VERSION=1.0.0
ARG GIT_SHA=local
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    MODEL_PATH=/app/model/model-1.0.0.joblib \
    API_VERSION=${API_VERSION} \
    GIT_SHA=${GIT_SHA} \
    PORT=8000
LABEL org.opencontainers.image.title="sentiment-api" \
      org.opencontainers.image.version="${API_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

COPY --from=builder /install /usr/local
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app
COPY --chown=appuser:appuser api/app ./app
COPY --chown=appuser:appuser model/model-1.0.0.joblib ./model/model-1.0.0.joblib

USER appuser
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4).status == 200 else 1)"
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --workers 1 --no-access-log"]
