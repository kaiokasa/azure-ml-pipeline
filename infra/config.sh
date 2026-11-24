#!/usr/bin/env bash
# Shared configuration - edit the 4 values marked <> then `source infra/config.sh`.
# Storage and Cosmos names must be globally unique (storage: lowercase, no dash, <= 24 chars).

EQ="${EQ:-mlpipe}"                     # team name, lowercase letters/digits only, e.g. iaml3
LOC="${LOC:-<region-choisie>}"           # e.g. francecentral - must pass infra/00-check-region.sh
GH_REPO="${GH_REPO:-kaiokasa/azure-ml-pipeline}"   # GitHub owner/repo, e.g. jdupont/azure-ml-pipeline
ALERT_EMAIL="${ALERT_EMAIL:-<email>}"    # receives budget + alert e-mails

RG="rg-projet-$EQ"
ST="st${EQ}pipe"
COSMOS="cosmos-$EQ"
ENV="cae-$EQ"
API="api-$EQ"
FUNC="func-$EQ"
ID="id-github-$EQ"
LAW="log-$EQ"
AI="appi-$EQ"
AG="ag-$EQ"
QUEUE="inference-requests"
IMAGE="ghcr.io/$(echo "$GH_REPO" | tr '[:upper:]' '[:lower:]')/api"

if [[ "$EQ" == *"<"* || "$LOC" == *"<"* || "$GH_REPO" == *"<"* || "$ALERT_EMAIL" == *"<"* ]]; then
  echo "Edit infra/config.sh (or export EQ, LOC, GH_REPO, ALERT_EMAIL) first." >&2
  return 1 2>/dev/null || exit 1
fi
