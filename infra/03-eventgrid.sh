#!/usr/bin/env bash
# Step 3 - Event Grid subscription: storage system topic -> dispatcher function.
# Run AFTER the first Functions deployment (endpoint validation fails otherwise).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.sh"

az eventgrid event-subscription create -n blob-to-dispatcher \
  --source-resource-id "$(az storage account show -n "$ST" -g "$RG" --query id -o tsv)" \
  --endpoint-type azurefunction \
  --endpoint "$(az functionapp show -n "$FUNC" -g "$RG" --query id -o tsv)/functions/dispatcher" \
  --included-event-types Microsoft.Storage.BlobCreated \
  --subject-begins-with /blobServices/default/containers/input/ \
  --max-delivery-attempts 10 --event-ttl 60 -o none
echo "Event Grid subscription created: BlobCreated on input/ -> dispatcher"
