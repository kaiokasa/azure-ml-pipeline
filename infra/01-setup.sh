#!/usr/bin/env bash
# Step 1 - create the whole platform in the integration subscription (run ONCE by its owner).
# Idempotent enough to be re-run after a transient failure (429 throttling, capacity...).
#   source infra/config.sh && bash infra/01-setup.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.sh"

echo "== Resource group (tags projet=dscc, equipe=$EQ)"
az group create -n "$RG" -l "$LOC" --tags projet=dscc equipe="$EQ" -o none

echo "== Cosmos DB Free Tier FIRST (most often refused for capacity -> validates the region early)"
if ! az cosmosdb show -n "$COSMOS" -g "$RG" -o none 2>/dev/null; then
  az cosmosdb create -n "$COSMOS" -g "$RG" --enable-free-tier true \
    --locations regionName="$LOC" failoverPriority=0 isZoneRedundant=False \
    --default-consistency-level Session -o none
fi
az cosmosdb sql database create -a "$COSMOS" -g "$RG" -n pipeline --throughput 400 -o none 2>/dev/null || true
az cosmosdb sql container create -a "$COSMOS" -g "$RG" -d pipeline -n inferences \
  --partition-key-path /fileName -o none 2>/dev/null || true

echo "== Storage: containers, queues, versioning, static website"
az storage account create -n "$ST" -g "$RG" -l "$LOC" --sku Standard_LRS --kind StorageV2 \
  --access-tier Hot --min-tls-version TLS1_2 --allow-blob-public-access false -o none
az storage account blob-service-properties update -n "$ST" -g "$RG" --enable-versioning true -o none
# The owner needs data-plane rights to create containers with --auth-mode login
ME=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
ST_ID=$(az storage account show -n "$ST" -g "$RG" --query id -o tsv)
if [[ -n "$ME" ]]; then
  az role assignment create --role "Storage Blob Data Contributor" --assignee-object-id "$ME" \
    --assignee-principal-type User --scope "$ST_ID" -o none 2>/dev/null || true
  az role assignment create --role "Storage Queue Data Contributor" --assignee-object-id "$ME" \
    --assignee-principal-type User --scope "$ST_ID" -o none 2>/dev/null || true
fi
for c in input output rejected models; do
  az storage container create --account-name "$ST" -n "$c" --auth-mode key -o none
done
for q in "$QUEUE" "$QUEUE-poison"; do
  az storage queue create --account-name "$ST" -n "$q" --auth-mode key -o none
done
az storage blob service-properties update --account-name "$ST" --auth-mode key \
  --static-website --index-document index.html -o none
WEB_URL=$(az storage account show -n "$ST" -g "$RG" --query primaryEndpoints.web -o tsv)
WEB_ORIGIN="${WEB_URL%/}"

echo "== Monitoring FIRST: Log Analytics capped at 0.2 GB/day + workspace-based Application Insights"
az monitor log-analytics workspace create -g "$RG" -n "$LAW" -l "$LOC" --quota 0.2 --retention-time 30 -o none
LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)
az monitor app-insights component create --app "$AI" -g "$RG" -l "$LOC" --workspace "$LAW_ID" \
  --kind web --application-type web -o none
AI_CS=$(az monitor app-insights component show --app "$AI" -g "$RG" --query connectionString -o tsv)

echo "== Container Apps: ONE environment, API at 0 replicas when idle, probes on /health"
if ! az containerapp env show -n "$ENV" -g "$RG" -o none 2>/dev/null; then
  az containerapp env create -n "$ENV" -g "$RG" -l "$LOC" \
    --logs-workspace-id "$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query customerId -o tsv)" \
    --logs-workspace-key "$(az monitor log-analytics workspace get-shared-keys -g "$RG" -n "$LAW" --query primarySharedKey -o tsv)" \
    -o none
fi
ENV_ID=$(az containerapp env show -n "$ENV" -g "$RG" --query id -o tsv)
TMP_YAML="$(mktemp)"
cat > "$TMP_YAML" <<YAML
location: $LOC
properties:
  managedEnvironmentId: $ENV_ID
  configuration:
    activeRevisionsMode: Single
    ingress:
      external: true
      targetPort: 8000
      transport: auto
      allowInsecure: false
    secrets:
      - name: appi-cs
        value: "$AI_CS"
  template:
    containers:
      - name: api
        image: $IMAGE:1.0.0
        resources: { cpu: 0.25, memory: 0.5Gi }
        env:
          - { name: APPLICATIONINSIGHTS_CONNECTION_STRING, secretRef: appi-cs }
          - { name: OTEL_SERVICE_NAME, value: sentiment-api }
        probes:
          - type: Liveness
            httpGet: { path: /health, port: 8000 }
            initialDelaySeconds: 5
            periodSeconds: 30
            failureThreshold: 3
          - type: Readiness
            httpGet: { path: /health, port: 8000 }
            initialDelaySeconds: 3
            periodSeconds: 10
            failureThreshold: 3
    scale:
      minReplicas: 0
      maxReplicas: 2
      rules:
        - name: http
          http: { metadata: { concurrentRequests: "20" } }
YAML
if az containerapp show -n "$API" -g "$RG" -o none 2>/dev/null; then
  az containerapp update -n "$API" -g "$RG" --yaml "$TMP_YAML" -o none
else
  az containerapp create -n "$API" -g "$RG" --yaml "$TMP_YAML" -o none
fi
rm -f "$TMP_YAML"
API_URL="https://$(az containerapp show -n "$API" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv)"

echo "== Function App Flex Consumption (Python 3.12, 512 MB) - if 429/quota: wait, retry, then another region"
if ! az functionapp show -n "$FUNC" -g "$RG" -o none 2>/dev/null; then
  az functionapp create -n "$FUNC" -g "$RG" --storage-account "$ST" --app-insights "$AI" \
    --flexconsumption-location "$LOC" --runtime python --runtime-version 3.12 --instance-memory 512 -o none
fi
az functionapp identity assign -n "$FUNC" -g "$RG" -o none
COSMOS_EP=$(az cosmosdb show -n "$COSMOS" -g "$RG" --query documentEndpoint -o tsv)
# Identity-based connections: STORAGE__* (no key) + Cosmos endpoint (no key)
az functionapp config appsettings set -n "$FUNC" -g "$RG" -o none --settings \
  "STORAGE__blobServiceUri=https://$ST.blob.core.windows.net" \
  "STORAGE__queueServiceUri=https://$ST.queue.core.windows.net" \
  "STORAGE__credential=managedidentity" \
  "COSMOS_ENDPOINT=$COSMOS_EP" "COSMOS_DATABASE=pipeline" "COSMOS_CONTAINER=inferences" \
  "API_URL=$API_URL" "API_TIMEOUT_SECONDS=45" "MAX_FILE_BYTES=1000000"
az functionapp cors add -n "$FUNC" -g "$RG" --allowed-origins "$WEB_ORIGIN" -o none

echo "== Managed identity for GitHub Actions (OIDC, no Entra ID admin rights needed)"
az identity create -n "$ID" -g "$RG" -o none
az identity federated-credential create -n github-production --identity-name "$ID" -g "$RG" \
  --issuer https://token.actions.githubusercontent.com \
  --subject "repo:$GH_REPO:environment:production" \
  --audiences api://AzureADTokenExchange -o none 2>/dev/null || true
# Private-repo alternative (section 4.6): uncomment and use workflow_dispatch
# az identity federated-credential create -n github-main --identity-name "$ID" -g "$RG" \
#   --issuer https://token.actions.githubusercontent.com --subject "repo:$GH_REPO:ref:refs/heads/main" \
#   --audiences api://AzureADTokenExchange -o none

echo "== Alerting: action group (e-mail) + log alert on worker errors, evaluated every 15 min"
az monitor action-group create -g "$RG" -n "$AG" --short-name pipealert \
  --action email admin "$ALERT_EMAIL" -o none
AI_ID=$(az monitor app-insights component show --app "$AI" -g "$RG" --query id -o tsv)
AG_ID=$(az monitor action-group show -g "$RG" -n "$AG" --query id -o tsv)
az monitor scheduled-query create -g "$RG" -n "alert-pipeline-errors" --scopes "$AI_ID" \
  --description "Worker errors > 0 in the last 15 min (poison messages, API down...)" \
  --condition "count 'ErrQ' > 0" \
  --condition-query ErrQ="customMetrics | where name == 'pipeline.errors' and valueSum > 0" \
  --evaluation-frequency 15m --window-size 15m --severity 2 \
  --action-groups "$AG_ID" -o none

echo "== Budget 25 USD on the resource group, e-mail at 20/50/80 %"
START="$(date -u +%Y-%m-01)T00:00:00Z"
END="$(date -u -d "+12 months" +%Y-%m-01 2>/dev/null || date -u -v+12m +%Y-%m-01)T00:00:00Z"
notif() { echo "\"Actual_$1\": {\"enabled\": true, \"operator\": \"GreaterThan\", \"threshold\": $1, \"thresholdType\": \"Actual\", \"contactEmails\": [\"$ALERT_EMAIL\"]}"; }
az rest --method put \
  --url "https://management.azure.com$(az group show -n "$RG" --query id -o tsv)/providers/Microsoft.Consumption/budgets/budget-$EQ?api-version=2023-05-01" \
  --body "{\"properties\": {\"category\": \"Cost\", \"amount\": 25, \"timeGrain\": \"Monthly\",
           \"timePeriod\": {\"startDate\": \"$START\", \"endDate\": \"$END\"},
           \"notifications\": {$(notif 20), $(notif 50), $(notif 80)}}}" -o none

echo
echo "Platform created. Next: bash infra/02-roles.sh (owner), then push to main (deploy.yml),"
echo "then bash infra/03-eventgrid.sh once the dispatcher function exists."
echo "API       : $API_URL"
echo "Dashboard : $WEB_URL"
