# Bonus – Infrastructure as Code (Bicep)

Tout le socle est décrit dans [`main.bicep`](main.bicep) et redéployable en **une commande** :

```bash
export ALERT_EMAIL=moi@exemple.fr          # jamais écrit dans le dépôt
bash infra/bicep/deploy.sh what-if         # aperçu des changements (aucune modification)
bash infra/bicep/deploy.sh                 # déploiement
```

`deploy.sh` exécute `az deployment group create -f main.bicep -p main.bicepparam`. Il active ensuite le site web statique, qui est un paramètre du service Blob et non une propriété ARM.

## Ressources décrites (29)

| Domaine | Ressources |
|---|---|
| Stockage | compte StorageV2 LRS (TLS 1.2, accès public interdit, versionnage) ; conteneurs `input`, `output`, `rejected`, `models`, paquet de déploiement ; files `inference-requests` et `-poison` |
| Données | Cosmos DB **Free Tier** ; base `pipeline` à 400 RU/s ; conteneur `inferences` (clé `/fileName`) |
| Supervision | Log Analytics (plafond **0,2 Go/jour**) ; Application Insights basé sur l’espace de travail |
| API | environnement Container Apps (profil Consumption) ; application `api-<eq>` (0,25 vCPU / 0,5 Gio, **0 à 2 réplicas**, sondes *liveness* / *readiness*, secret App Insights) |
| Serverless | plan **Flex Consumption** FC1 ; Function App Python 3.12, 512 Mo, identité système, **connexions par identité uniquement** (aucune chaîne de connexion), CORS limité au site |
| Événements | abonnement Event Grid `BlobCreated` sur `input/` vers `dispatcher` |
| CI/CD | identité managée GitHub et ses 2 informations d’identification fédérées (sujet classique et sujet à identifiants immuables) |
| Sécurité | attributions de rôles : Function App vers Storage (Blob Data Owner, Queue Data Contributor) et Cosmos DB (Data Contributor) ; identité GitHub vers groupe de ressources (Contributor) et `$web` (Blob Data Contributor) |
| FinOps | groupe d’actions e-mail ; alerte de journal toutes les 15 min ; budget **25 $** avec alertes à 20, 50 et 80 % ; étiquettes `projet=dscc` et `equipe` sur toutes les ressources |

## Paramètres

[`main.bicepparam`](main.bicepparam) contient les valeurs de l’équipe `mlpipe`. L’e-mail, l’image de l’API et deux interrupteurs viennent de variables d’environnement :

| Variable | Défaut | Rôle |
|---|---|---|
| `ALERT_EMAIL` | (obligatoire) | destinataire des alertes et du budget |
| `API_IMAGE` | image actuellement déployée | évite de revenir en arrière sur la version publiée par la CI/CD |
| `ASSIGN_ROLES` | `false` | créer les attributions de rôles (exige le rôle Owner). Les attributions existantes ont été créées par `02-roles.sh` sous d’autres noms, et les recréer échouerait (`RoleAssignmentExists`). |
| `DEPLOY_EVENT_GRID` | `true` | l’abonnement exige que la fonction `dispatcher` soit déjà déployée |

**Groupe de ressources neuf :**

1. `ASSIGN_ROLES=true DEPLOY_EVENT_GRID=false bash infra/bicep/deploy.sh`
2. Push sur `main` : la CI/CD publie le code.
3. `bash infra/bicep/deploy.sh`

## Validation sur l’environnement réel (24/11/2026)

1. **What-if** sur `rg-projet-mlpipe`, créé à l’origine par les scripts CLI : **0 création, 0 suppression**. Les 29 ressources sont reconnues par leur nom ([`docs/bicep/what-if.txt`](../../docs/bicep/what-if.txt)). Les « modifications » restantes sont soit des propriétés en lecture seule ou par défaut, soit les améliorations voulues : étiquettes sur chaque ressource, HTTPS uniquement, paquet de déploiement lu par identité.
2. **Déploiement réel** en une commande, en 2 min ([`docs/bicep/deploy-output.txt`](../../docs/bicep/deploy-output.txt)).
3. **Vérification de bout en bout** après le déploiement : les paramètres `AzureWebJobsStorage` et `DEPLOYMENT_STORAGE_CONNECTION_STRING` (chaînes de connexion créées par la CLI) ont disparu au profit de `AzureWebJobsStorage__accountName` et de l’identité managée. Le fichier `bicep-verif.txt`, déposé à 15:53:18, a été traité à 15:53:45 (positif, 3 avis), et le tableau de bord répond.
