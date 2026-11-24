#!/usr/bin/env bash
# Step 0 - pick the project region (run in Cloud Shell or with Azure CLI >= 2.60).
# The region must appear in BOTH lists below, and Cosmos DB must be creatable there.
set -euo pipefail

echo "== 1. Allowed regions (policy 'Allowed resource deployment regions')"
az policy assignment list --disable-scope-strict-match \
  --query "[?contains(displayName,'region') || contains(displayName,'location')].parameters" -o json

echo "== 2. Regions offering Functions Flex Consumption"
az functionapp list-flexconsumption-locations -o table

echo "== 3. Registering resource providers (once per subscription)"
for p in Microsoft.Web Microsoft.App Microsoft.EventGrid Microsoft.DocumentDB \
         Microsoft.OperationalInsights Microsoft.Insights Microsoft.ManagedIdentity \
         Microsoft.Storage Microsoft.AlertsManagement Microsoft.Consumption; do
  az provider register --namespace "$p" -o none
done
echo "Done. Put the chosen region in infra/config.sh (LOC=...)."
