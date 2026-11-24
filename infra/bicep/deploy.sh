#!/usr/bin/env bash
# Redéploie tout le socle en une commande (bonus Infrastructure as Code).
#   ALERT_EMAIL=moi@exemple.fr bash infra/bicep/deploy.sh            # déploiement
#   ALERT_EMAIL=moi@exemple.fr bash infra/bicep/deploy.sh what-if    # aperçu des changements, sans rien modifier
# Groupe neuf : ASSIGN_ROLES=true DEPLOY_EVENT_GRID=false au premier passage, puis déployer le code
# (push sur main) et relancer avec DEPLOY_EVENT_GRID=true.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../config.sh"
[[ -n "${ALERT_EMAIL:-}" && "$ALERT_EMAIL" != *"<"* ]] || { echo "export ALERT_EMAIL=... first" >&2; exit 1; }
MODE="${1:-create}"

# Conserver l'image actuellement déployée par la CI/CD (sinon : version 1.0.0)
if [[ -z "${API_IMAGE:-}" ]]; then
  API_IMAGE=$(az containerapp show -n "$API" -g "$RG" --query "properties.template.containers[0].image" -o tsv 2>/dev/null || true)
  export API_IMAGE="${API_IMAGE:-$IMAGE:1.0.0}"
fi
echo "Image API : $API_IMAGE"

az group create -n "$RG" -l "$LOC" --tags projet=dscc equipe="$EQ" -o none
az deployment group "$MODE" -g "$RG" -n "socle-$(date +%Y%m%d-%H%M%S)" \
  -f "$(winpath "$HERE/main.bicep")" -p "$(winpath "$HERE/main.bicepparam")" \
  $([[ "$MODE" == create ]] && echo "--query properties.outputs -o json")

if [[ "$MODE" == create ]]; then
  # Le site web statique est un paramètre du service Blob (plan de données), pas une propriété ARM.
  az storage blob service-properties update --account-name "$ST" --auth-mode key \
    --static-website --index-document index.html -o none
  echo "Site web statique activé : $(az storage account show -n "$ST" -g "$RG" --query primaryEndpoints.web -o tsv)"
fi
