#!/usr/bin/env bash
# Step 2 - role assignments, created ONCE by the subscription OWNER.
# (The GitHub identity is only Contributor on the RG: it cannot write role assignments.)
# --assignee-object-id avoids any Entra ID directory read (often forbidden for students).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.sh"

ST_ID=$(az storage account show -n "$ST" -g "$RG" --query id -o tsv)
RG_ID=$(az group show -n "$RG" --query id -o tsv)
FUNC_PID=$(az functionapp identity show -n "$FUNC" -g "$RG" --query principalId -o tsv)
GH_PID=$(az identity show -n "$ID" -g "$RG" --query principalId -o tsv)

assign() { # role principal scope
  az role assignment create --role "$1" --assignee-object-id "$2" \
    --assignee-principal-type ServicePrincipal --scope "$3" -o none 2>/dev/null \
    && echo "  + $1" || echo "  = $1 (already assigned)"
}

echo "== Function App system identity -> Storage (blob + queue data plane)"
assign "Storage Blob Data Owner" "$FUNC_PID" "$ST_ID"
assign "Storage Queue Data Contributor" "$FUNC_PID" "$ST_ID"

echo "== Function App system identity -> Cosmos DB Built-in Data Contributor (data-plane RBAC, not Azure RBAC)"
az cosmosdb sql role assignment create -a "$COSMOS" -g "$RG" --scope / \
  --principal-id "$FUNC_PID" --role-definition-id 00000000-0000-0000-0000-000000000002 -o none 2>/dev/null \
  || echo "  = already assigned"

echo "== GitHub identity -> Contributor on the resource group only (least privilege)"
assign "Contributor" "$GH_PID" "$RG_ID"
echo "== GitHub identity -> Storage Blob Data Contributor on the storage account (upload of \$web)"
assign "Storage Blob Data Contributor" "$GH_PID" "$ST_ID"

echo
echo "GitHub repository secrets to create (identifiers only, nothing sensitive):"
echo "  AZURE_CLIENT_ID       = $(az identity show -n "$ID" -g "$RG" --query clientId -o tsv)"
echo "  AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)"
echo "  AZURE_SUBSCRIPTION_ID = $(az account show --query id -o tsv)"
echo "GitHub repository variables:"
echo "  AZURE_RG=$RG  CONTAINERAPP_NAME=$API  FUNCAPP_NAME=$FUNC  STORAGE_ACCOUNT=$ST"
