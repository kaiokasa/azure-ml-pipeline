#!/usr/bin/env bash
# Load test of the event-driven pipeline (bonus "Test de charge"): N files uploaded in one burst.
#   bash loadtest/burst.sh 100
# Each file holds 50 reviews taken from the UCI dataset (model/data must exist: python model/train.py).
# Afterwards, analyse with the KQL queries in loadtest/analysis.kql (filter: fileName startswith "burst-<RUN>").
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../infra/config.sh"
N="${1:-100}"
RUN="burst-$(date +%H%M%S)"
TMP="$(mktemp -d)"
SRC="$HERE/../model/data/yelp_labelled.txt"

for i in $(seq -w 1 "$N"); do
  # 50 different lines per file (rotating window over the dataset)
  start=$(( (10#$i * 7) % 900 + 1 ))
  sed -n "${start},$((start + 49))p" "$SRC" | cut -f1 > "$TMP/$RUN-$i.txt"
done

echo "Run id      : $RUN"
echo "Upload start: $(date -u +%FT%TZ)"
az storage blob upload-batch --account-name "$ST" --auth-mode login -d input -s "$(winpath "$TMP")" \
  --max-connections 16 -o none 2>&1 | grep -v -E "WARNING|Alive|Finished" || true
echo "Upload end  : $(date -u +%FT%TZ)"
rm -rf "$TMP"
echo "$RUN"
