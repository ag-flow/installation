# Stack ag-flow mutualisée (portal + rag + doc)

Installation prod **reproductible** d'une stack `docker compose` **unique**
hébergeant les produits ag-flow, avec les composants partagés **mutualisés**
(voir objectifs dans `../../CLAUDE.md`).

## Mutualisation

- **1 Postgres** (`pgvector/pgvector:pg16`) partagé :
  - rôle/base `rag` (superuser — crée aussi les bases workspace dynamiques de rag) ;
  - rôle/base `docflow` (`initdb/10-docflow.sh`) ;
  - rôle/base `portal` (`initdb/20-portal.sh`).
- **1 réseau** Docker (`agflow`).
- **1 reverse-proxy Caddy** (API admin `:2019` pour les routes `ws-*` du portal) :
  - `portal` → hôte de base `{BASE_DOMAIN}` (+ `ws-*.{BASE_DOMAIN}` dynamiques) ;
  - `rag` → `rag.{BASE_DOMAIN}` ;
  - `doc` → `doc.{BASE_DOMAIN}`.

## Produits

| Produit | Image | Accès |
|---|---|---|
| portal | `ghcr.io/gaelgael5/workspace-portal` | `{BASE_DOMAIN}` (+ `ws-*`) |
| rag | `ghcr.io/ag-flow/rag-backend` + `rag-frontend` | `rag.{BASE_DOMAIN}` |
| doc | `ghcr.io/ag-flow/doc` | `doc.{BASE_DOMAIN}` |

Mode de livraison : **PULL** (images publiques ghcr). Aucun build, aucune
dépendance tirée des dépôts sources à l'exécution. TLS terminé en amont par
Cloudflare Tunnel — Caddy tourne en HTTP simple (`auto_https off`).

## Installation (sur la machine cible)

```bash
git clone https://github.com/ag-flow/installation.git
cd installation
deploy/docker-compose/deploy.sh
```

Le script :
1. copie les dépendances dans `/opt/agflow` et génère `/opt/agflow/.env`
   (secrets rag + doc + mot de passe Postgres portal, non-interactif, idempotent) ;
2. initialise `/data` du portal (CA, certs, `config.yaml`, `.env`) via le
   `portal/install.sh` vendorisé, puis y complète `DATABASE_URL` + `PORTAL_VAULT_KEK` ;
3. `docker compose pull && up -d`, applique les migrations Alembic du portal ;
4. vérifie la santé de **portal**, **rag** et **doc**.

Les mots de passe admin générés sont affichés en fin d'exécution.

### Variables optionnelles

| Variable | Défaut | Rôle |
|---|---|---|
| `DEPLOY_DIR` | `/opt/agflow` | répertoire d'installation (rag/doc) |
| `BASE_DOMAIN` | `agflow.local` | portal = base ; rag/doc en sous-domaines |
| `RAG_PUBLIC_URL` | `http://<ip-hôte>` | URL publique rag |
| `IMAGE_TAG` / `DOC_IMAGE_TAG` / `PORTAL_IMAGE_TAG` | `latest`/`latest`/`main` | versions |
| `GHCR_TOKEN` | *(vide)* | token `read:packages` si images privées |

> Le portal stocke sa config et ses secrets dans `/data` (CA, certs,
> `config.yaml`, `.env`) — distinct de `/opt/agflow`.

## Contenu

| Fichier | Rôle |
|---|---|
| `deploy.sh` | installe la stack complète |
| `docker-compose.yml` | stack mutualisée (postgres, backend, frontend, doc, portal, caddy) |
| `Caddyfile` | reverse-proxy commun (admin API + routage par hôte) |
| `initdb/10-docflow.sh`, `initdb/20-portal.sh` | création des rôles/bases doc & portal |
| `portal/install.sh` | init `/data` du portal (vendorisé depuis devpod-ui) |
| `pricing.yml` | tarifs embeddings rag (lecture seule) |
| `.env.example` | gabarit de configuration (rag + doc + portal) |
