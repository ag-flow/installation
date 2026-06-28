# Bloc 1/3 — rag (installation prod)

Installation prod **reproductible** de `ag-flow.rag`, avec **toutes les
dépendances versionnées dans ce dépôt** (mode de travail : voir `../../CLAUDE.md`).

## Contenu (dépendances vendorisées)

| Fichier | Origine | Rôle |
|---|---|---|
| `deploy.sh` | adapté de `ag-flow/rag:deploy/prod/deploy.sh` | installe le bloc |
| `docker-compose.yml` | `ag-flow/rag:deploy/prod` (verbatim) | stack (images ghcr) |
| `Caddyfile` | idem | reverse-proxy HTTP |
| `pricing.yml` | idem | tarifs embeddings (lecture seule) |
| `.env.example` | idem | gabarit de configuration |

Mode de livraison : **PULL** — images pré-buildées `ghcr.io/ag-flow/rag-backend`
et `rag-frontend` (publiques). Aucun build local, aucun téléchargement depuis
`ag-flow/rag` à l'exécution.

## Installation (sur la machine cible)

```bash
git clone https://github.com/ag-flow/installation.git
cd installation
deploy/docker-compose/deploy.sh
```

Le script : vérifie les prérequis → copie les dépendances dans `/opt/rag` →
génère `/opt/rag/.env` avec des secrets aléatoires (non-interactif, idempotent :
un `.env` existant est conservé) → `docker compose pull && up -d` → health check.

Le mot de passe admin bootstrap généré est affiché en fin d'exécution.

### Variables optionnelles

| Variable | Défaut | Rôle |
|---|---|---|
| `DEPLOY_DIR` | `/opt/rag` | répertoire d'installation |
| `RAG_PUBLIC_URL` | `http://<ip-hôte>` | URL publique (callbacks OIDC, navigateur) |
| `IMAGE_TAG` | `latest` | épingler une version (`<sha>`) |
| `GHCR_TOKEN` | *(vide)* | token `read:packages` si les images deviennent privées |
