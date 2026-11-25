# Journal de temps

Une ligne par séance de travail (budget : 12 h par étudiant sur 15 jours). Équipe de deux : Omar BOUCHENTOUF et Mohamed JOURFI. L’abonnement d’intégration Azure for Students est celui de Mohamed JOURFI.

| Date | Membre | Tâche | Durée (h) | Blocage / remarque |
|---|---|---|---|---|
| 2026-11-24 | Omar BOUCHENTOUF | Lecture du sujet, choix du cas d’usage (avis clients), structure du dépôt | 0,25 | – |
| 2026-11-24 | Mohamed JOURFI | Modèle (TF-IDF + régression logistique, 0,86 d’accuracy), API FastAPI + tests, Dockerfile | 0,5 | Démon Docker arrêté : démarrage de Docker Desktop |
| 2026-11-24 | Omar BOUCHENTOUF | Functions (dispatcher, worker, recent), tableau de bord, scripts `infra/`, workflows CI/CD, README | 0,5 | – |
| 2026-11-24 | Mohamed JOURFI | Dépôt GitHub public, environnement `production`, CI verte, image GHCR rendue publique | 0,25 | Paquet GHCR privé par défaut : visibilité changée à la main |
| 2026-11-24 | Mohamed JOURFI | Connexion Azure CLI à son abonnement, choix de la région (`germanywestcentral`) | 0,25 | MFA obligatoire (`AADSTS50076`) : `az login --tenant` |
| 2026-11-24 | Omar BOUCHENTOUF | `01-setup.sh` (Cosmos, stockage, supervision, Container Apps, Functions, alerte, budget), `02-roles.sh` | 0,5 | Git Bash réécrit les chemins `/…` : `MSYS_NO_PATHCONV` |
| 2026-11-24 | Mohamed JOURFI | Premier déploiement GitHub Actions | 0,5 | `AADSTS700213` (sujet OIDC avec identifiants), `ExpressRevisionSuffixNotSupported` |
| 2026-11-24 | Omar BOUCHENTOUF | Event Grid, tests de bout en bout (valide, invalide, poison), alerte, requêtes KQL | 0,75 | Nom d’hôte Function App vide (`properties.defaultHostName`), métriques perdues sur Flex |
| 2026-11-24 | Mohamed JOURFI | Démonstration (dépôt valide, invalide, message empoisonné), captures du portail Azure | 0,5 | Onglet bloqué par « Quitter la page ? » sur une requête non enregistrée |
| 2026-11-24 | Omar BOUCHENTOUF | Bonus test de charge : rafale de 100 fichiers, Locust, analyse KQL | 0,5 | Processeur du poste saturé pendant Locust : mesures côté serveur retenues |
| 2026-11-24 | Mohamed JOURFI | Bonus Infrastructure as Code : Bicep, what-if, redéploiement réel, vérification | 0,75 | Attributions de rôles existantes sous d’autres noms : paramètre `ASSIGN_ROLES` |
| 2026-11-24 | Omar BOUCHENTOUF | Présentation de soutenance (diapositives) | 0,5 | – |
| 2026-11-24 | Mohamed JOURFI | Rapport écrit avec captures | 0,5 | – |
| 2026-11-25 | Omar BOUCHENTOUF | Vérification finale par rapport au sujet, schéma d’architecture dans `docs/` | 0,25 | – |

## Total par membre

| Membre | Total (h) |
|---|---|
| Omar BOUCHENTOUF | 3,25 |
| Mohamed JOURFI | 3,25 |
