# Installation du système ag-flow

Déploiement unifié des trois produits ag-flow sur un seul hôte, derrière un
unique reverse-proxy Caddy.

## Produits

| Produit | Dépôt |
|---|---|
| portal | https://github.com/gaelgael5/devpod-ui.git |
| doc    | https://github.com/ag-flow/doc.git |
| rag    | https://github.com/ag-flow/rag.git *(privé)* |

Secrets / Harpocrate : https://vault.yoops.org/

## Démarrage

```bash
docker login ghcr.io                       # images rag privées
sudo BASE_DOMAIN=dev.yoops.org ./install.sh
```

Voir **[dockers/README.md](dockers/README.md)** pour l'architecture, le TLS,
le démarrage manuel et les points à vérifier.

> `install.md` est l'ancien guide d'installation **rag seul** (référence).
