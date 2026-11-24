#!/usr/bin/env bash
# Demo helpers for the video / defence.
#   bash infra/demo.sh valid     -> upload a valid file (result in < 1 min on the dashboard)
#   bash infra/demo.sh invalid   -> upload invalid files (-> rejected/)
#   bash infra/demo.sh poison    -> push a malformed message (-> 5 attempts -> inference-requests-poison)
#   bash infra/demo.sh status    -> queue lengths, last outputs/rejections, API replicas
#   bash infra/demo.sh burst N   -> upload N copies (load test / scale-out)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
source "$HERE/config.sh"
AUTH=(--account-name "$ST" --auth-mode login)
TS=$(date +%Y%m%d-%H%M%S)

case "${1:-status}" in
  valid)
    az storage blob upload "${AUTH[@]}" -c input -f "$ROOT/samples/reviews-mixed.txt" -n "reviews-$TS.txt" -o none
    echo "Uploaded input/reviews-$TS.txt" ;;
  invalid)
    az storage blob upload "${AUTH[@]}" -c input -f "$ROOT/samples/invalid-extension.csv" -n "bad-$TS.csv" -o none
    az storage blob upload "${AUTH[@]}" -c input -f "$ROOT/samples/invalid-empty.txt" -n "empty-$TS.txt" -o none
    echo "Uploaded 2 invalid files -> expect rejected/bad-$TS.csv and rejected/empty-$TS.txt" ;;
  poison)
    # Queue messages are base64-encoded by the Functions queue extension.
    MSG=$(printf '{"this is": "not a valid inference request"}' | base64 | tr -d '\n')
    az storage message put "${AUTH[@]}" -q "$QUEUE" --content "$MSG" -o none
    echo "Malformed message sent. After 5 attempts (~1 min) it lands in $QUEUE-poison." ;;
  burst)
    N="${2:-100}"; TMP=$(mktemp -d)
    for i in $(seq -w 1 "$N"); do cp "$ROOT/samples/reviews-mixed.txt" "$TMP/burst-$TS-$i.txt"; done
    az storage blob upload-batch "${AUTH[@]}" -d input -s "$TMP" -o none; rm -rf "$TMP"
    echo "Uploaded $N files" ;;
  status)
    for q in "$QUEUE" "$QUEUE-poison"; do
      printf "%-28s %s messages\n" "$q" "$(az storage message peek "${AUTH[@]}" -q "$q" --num-messages 32 --query 'length(@)' -o tsv)"
    done
    echo "-- last outputs";  az storage blob list "${AUTH[@]}" -c output   --query "sort_by(@,&properties.lastModified)[-5:].name" -o tsv
    echo "-- last rejected"; az storage blob list "${AUTH[@]}" -c rejected --query "sort_by(@,&properties.lastModified)[-5:].name" -o tsv
    echo "-- API replicas";  az containerapp replica list -n "$API" -g "$RG" --query "length(@)" -o tsv ;;
  *) echo "usage: $0 valid|invalid|poison|burst N|status"; exit 1 ;;
esac
