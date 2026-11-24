// Paramètres de l'environnement de l'équipe mlpipe (rg-projet-mlpipe, germanywestcentral).
// Aucun secret ici : l'e-mail et l'image viennent de variables d'environnement (voir deploy.sh).
using 'main.bicep'

param eq = 'mlpipe'
param location = 'germanywestcentral'
param ghRepo = 'kaiokasa/azure-ml-pipeline'
param ghOwnerId = '146456810'
param ghRepoId = '1469889693'
param apiImage = readEnvironmentVariable('API_IMAGE', 'ghcr.io/kaiokasa/azure-ml-pipeline/api:1.0.0')
param alertEmail = readEnvironmentVariable('ALERT_EMAIL', '')
param budgetStartDate = '2026-11-01'
param budgetEndDate = '2027-11-01'

// Noms générés par la CLI lors de la première création (01-setup.sh) : on les reprend tels quels
param planName = 'ASP-rgprojetmlpipe-ea9d'
param deploymentContainerName = 'app-package-funcmlpipe-7636324'

// Les attributions de rôles existent déjà (créées par 02-roles.sh sous d'autres noms) :
// les recréer échouerait avec RoleAssignmentExists. Mettre true pour un groupe de ressources neuf.
param assignRoles = bool(readEnvironmentVariable('ASSIGN_ROLES', 'false'))

// L'abonnement Event Grid exige que la fonction dispatcher soit déployée (false au tout premier déploiement).
param deployEventGrid = bool(readEnvironmentVariable('DEPLOY_EVENT_GRID', 'true'))
