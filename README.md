# installation — système ag-flow

Installation prod **mutualisée** des produits ag-flow (portal + rag + doc + homepage)
dans une stack `docker compose` unique (un Postgres, un Caddy, un réseau), en
mode PULL reproductible.

## Documentation

- **Architecture & frontières** : [`documentation/fr/ARCHITECTURE.md`](documentation/fr/ARCHITECTURE.md)
  — le *pourquoi* (rôles des 3 produits, séparation docflow/rag, module workflow à venir).
- **Déploiement** (le *comment*) : [`deploy/docker-compose/README.md`](deploy/docker-compose/README.md).
- **Mode de travail / objectifs** : [`CLAUDE.md`](CLAUDE.md).

## Installation rapide

```bash
git clone https://github.com/ag-flow/installation.git
cd installation
deploy/docker-compose/deploy.sh
```

## Produits

| Produit | Dépôt | Accès |
|---|---|---|
| portal | https://github.com/gaelgael5/devpod-ui | `{BASE_DOMAIN}` (+ `ws-*`) |
| rag | https://github.com/ag-flow/rag | `rag.{BASE_DOMAIN}` |
| doc | https://github.com/ag-flow/doc | `doc.{BASE_DOMAIN}` |
| homepage | landing page (liens vers les ressources) | `home.{BASE_DOMAIN}` |

Secrets / Harpocrate : https://vault.yoops.org/ · SSO : https://security.yoops.org/
