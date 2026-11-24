#!/usr/bin/env bash
# After the defence: delete everything and capture proof (penalty -1 if resources remain after 48 h).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.sh"

read -r -p "Delete resource group $RG and everything in it? Type the RG name to confirm: " ans
[[ "$ans" == "$RG" ]] || { echo "Aborted."; exit 1; }

az group delete -n "$RG" --yes
# Budgets live on the RG scope and disappear with it. Free the Cosmos Free Tier slot as well.
echo "== Proof for the cost report (take screenshots of both outputs)"
echo "az group exists -n $RG  ->  $(az group exists -n "$RG")"
az group list -o table
echo "Check above: no DefaultResourceGroup-* nor any rg-projet-$EQ left."
for g in $(az group list --query "[?starts_with(name,'DefaultResourceGroup-')].name" -o tsv); do
  echo "Leftover found: $g  ->  az group delete -n $g --yes"
done
