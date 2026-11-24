# Rapport de coûts – équipe `mlpipe`

> 1 page. À compléter à J15 avec la capture de **Cost Management > Cost analysis** filtrée sur l’étiquette `projet=dscc`.

## 1. Estimation initiale (J0)

| Service | Offre | Hypothèse d’usage sur 15 jours | Estimation |
|---|---|---|---|
| Functions Flex Consumption | 250 000 exécutions + 100 000 Go-s gratuits/mois | ~2 000 exécutions, ~500 Go-s | 0,00 $ |
| Container Apps (API) | 180 000 vCPU-s + 360 000 Gio-s gratuits/mois, 0 réplica au repos | ~2 h actives à 0,25 vCPU = 1 800 vCPU-s | 0,00 $ |
| Event Grid | 100 000 opérations gratuites/mois | ~1 000 événements | 0,00 $ |
| Stockage (Blob, files, `$web`) | Standard LRS chaud | < 50 Mo, ~20 000 transactions | 0,10 $ |
| Cosmos DB Free Tier | 1 000 RU/s + 25 Go gratuits | 1 base à 400 RU/s partagés | 0,00 $ |
| Log Analytics / App Insights | 5 Go gratuits/mois, plafond 0,2 Go/jour | < 0,5 Go | 0,00 $ |
| Alerte de journal (15 min) | ~0,50 $/règle/mois | 1 règle, 0,5 mois | 0,25 $ |
| GitHub Actions + GHCR | gratuit (dépôt public) | – | 0,00 $ |
| **Total estimé** | | | **≈ 0,35 $** (enveloppe : 25 $) |

## 2. Coût réel

**J0 (24/11/2026, jour du déploiement)** : la plateforme a été créée et testée le 24/11. Le coût réel n’était pas encore consultable ce jour-là (API Cost Management limitée, et les données de coût apparaissent avec 8 à 24 h de retard) ; il sera relevé à J15. Capture J0 : *Cost analysis* du groupe « No cost reported during this period », budget `budget-mlpipe` à **0,00 $ / 25,00 $ (0 %)**.

![Cost analysis J0](screenshots/cost-analysis-j0.jpg)
![Budget 25 $](screenshots/budget-25usd.jpg) Ressources actives : 11 (voir `az resource list -g rg-projet-mlpipe`), API à 0 réplica au repos.

**J15** (à relever dans *Cost Management > Cost analysis*, filtre `projet=dscc`, puis capture) :

| Service | Coût réel |
|---|---|
| Storage | … $ |
| Azure Monitor (Log Analytics, alerte) | … $ |
| Container Apps | … $ |
| Functions | … $ |
| Azure Cosmos DB | … $ |
| **Total** | **… $** |

Capture : `docs/screenshots/cost-analysis-j15.png`

## 3. Écart expliqué

- … à compléter à J15. Postes susceptibles d’écart : transactions de stockage (interrogation des files par le *worker* Flex, déploiements du paquet Functions), règle d’alerte de journal facturée au prorata. ACR non utilisé (GHCR) → 0 $.

## 4. Garde-fous en place

- Étiquettes `projet=dscc`, `equipe=mlpipe` sur le groupe de ressources (vérifié).
- Budget `budget-mlpipe` de 25 $ sur le groupe, alertes e-mail à 20 %, 50 % et 80 %.
- Plafond journalier Log Analytics : 0,2 Go/jour.
- API à `min-replicas 0`, pas d’ACR (GHCR gratuit), aucune VM.

## 5. Preuve de suppression (après la soutenance)

```
$ bash infra/99-cleanup.sh
az group exists -n rg-projet-mlpipe  ->  false
```
Captures : `docs/screenshots/group-exists-false.png`, `docs/screenshots/group-list-empty.png`
(aucun `DefaultResourceGroup-*` restant).
