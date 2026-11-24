# Script de la vidéo (5 min max) et de la démo en direct

| Temps | Écran | Action / commande | Ce qu’on montre |
|---|---|---|---|
| 0:00–0:30 | README | Schéma d’architecture | Flux Blob → Event Grid → file → worker → API → Cosmos → tableau de bord |
| 0:30–1:15 | GitHub Actions | Commit sur `main` → CI verte → Deploy en attente d’approbation → approuver | Lint, tests, image GHCR, OIDC, relecteur obligatoire |
| 1:15–1:35 | Terminal | `curl https://<api>/version` | `git_sha` = commit déployé |
| 1:35–2:20 | Terminal + tableau de bord | `bash infra/demo.sh valid` | Fichier visible dans le tableau de bord en < 1 min, sans action manuelle |
| 2:20–2:50 | Portail (conteneur `rejected/`) | `bash infra/demo.sh invalid` | `bad-*.csv`, `empty-*.txt` + `*.reason.json` |
| 2:50–3:30 | Portail (files d’attente) | `bash infra/demo.sh poison` puis `status` | 5 tentatives → message dans `inference-requests-poison` |
| 3:30–4:15 | Application Insights | Les 3 requêtes KQL de `docs/kql-queries.kql` | Inférences/heure, 5 fichiers les plus lents, codes HTTP |
| 4:15–4:40 | Alertes + boîte mail | Alerte `alert-pipeline-errors` déclenchée par le message poison | E-mail du groupe d’actions |
| 4:40–5:00 | Container Apps > Réplicas | Après ~5 min sans trafic | 0 réplica |

## Préparation

- Déclencher l’alerte **au moins 15 min avant** la soutenance (évaluation toutes les 15 min).
- Réveiller l’API (`curl /health`) juste avant la démo pour éviter le démarrage à froid en direct, puis montrer l’historique des réplicas.
