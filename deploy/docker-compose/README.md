# Stack ag-flow mutualisée (rag + doc)

Installation prod **reproductible** d'une stack `docker compose` **unique**
hébergeant plusieurs produits ag-flow, avec les composants partagés **mutualisés**
(voir objectifs dans `../../CLAUDE.md`).

## Mutualisation

- **1 Postgres** (`pgvector/pgvector:pg16`) partagé :
  - rôle/base `rag` (superuser — crée aussi les bases workspace dynamiques de rag) ;
  - rôle/base `docflow` créés par `initdb/10-docflow.sh` au premier démarrage.
- **1 réseau** Docker (`agflow`).
- **1 reverse-proxy Caddy** : `rag` sur l'hôte par défaut (`:80`), `doc` sur
  `doc.{BASE_DOMAIN}`.

## Produits

| Produit | Image | Accès |
|---|---|---|
| rag | `ghcr.io/ag-flow/rag-backend` + `rag-frontend` | hôte par défaut (`/ui`, `/api/*`…) |
| doc | `ghcr.io/ag-flow/doc` | `doc.{BASE_DOMAIN}` |

Mode de livraison : **PULL** (images publiques ghcr). Aucun build, aucune
dépendance tirée des dépôts sources à l'exécution.

## Installation (sur la machine cible)

```bash
git clone https://github.com/ag-flow/installation.git
cd installation
deploy/docker-compose/deploy.sh
```

Le script copie les dépendances dans `/opt/agflow`, génère `/opt/agflow/.env`
(secrets rag + doc, non-interactif, idempotent), `docker compose pull && up -d`,
puis vérifie la santé de **rag** et de **doc**. Les mots de passe admin générés
sont affichés en fin d'exécution.

### Variables optionnelles

| Variable | Défaut | Rôle |
|---|---|---|
| `DEPLOY_DIR` | `/opt/agflow` | répertoire d'installation |
| `BASE_DOMAIN` | `agflow.local` | doc servi sur `doc.<BASE_DOMAIN>` |
| `RAG_PUBLIC_URL` | `http://<ip-hôte>` | URL publique rag |
| `IMAGE_TAG` / `DOC_IMAGE_TAG` | `latest` | épingler une version |
| `GHCR_TOKEN` | *(vide)* | token `read:packages` si images privées |

## Contenu

| Fichier | Rôle |
|---|---|
| `deploy.sh` | installe la stack |
| `docker-compose.yml` | stack mutualisée (postgres, backend, frontend, doc, caddy) |
| `Caddyfile` | reverse-proxy commun |
| `initdb/10-docflow.sh` | crée le rôle/base `docflow` |
| `pricing.yml` | tarifs embeddings rag (lecture seule) |
| `.env.example` | gabarit de configuration (rag + doc) |
