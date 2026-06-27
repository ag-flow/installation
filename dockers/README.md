# Stack ag-flow — déploiement unifié

Lancement des trois produits ag-flow sur un seul hôte, derrière **un seul
reverse-proxy Caddy**, via `docker-compose.all.yml`.

| Produit | Dépôt | Provenance image | Sous-domaine |
|---|---|---|---|
| **portal** | [gaelgael5/devpod-ui](https://github.com/gaelgael5/devpod-ui) | **buildé** depuis les sources (pas d'image ghcr publiée) | `{BASE_DOMAIN}` + `ws-*.{BASE_DOMAIN}` |
| **doc** | [ag-flow/doc](https://github.com/ag-flow/doc) | `ghcr.io/ag-flow/doc` (public) | `doc.{BASE_DOMAIN}` |
| **rag** | ag-flow/rag *(privé)* | `ghcr.io/ag-flow/rag-backend` + `rag-frontend` | `rag.{BASE_DOMAIN}` |

```
                    ┌──────────── caddy (80/443) ────────────┐
   {BASE_DOMAIN} ───┤  srv0  ws-*.{BASE_DOMAIN} (dynamiques)  │
 doc.{BASE_DOMAIN} ─┤                                         │
 rag.{BASE_DOMAIN} ─┘                                         │
                    └────┬──────────┬───────────┬────────────┘
                       portal       doc      rag-frontend / rag-backend
                         │           │              │
                    portal-pg     doc-pg        rag-pg (pgvector)
```

## Installation rapide

```bash
# dépôt privé rag → se connecter à ghcr au préalable
docker login ghcr.io

sudo BASE_DOMAIN=dev.yoops.org ./install.sh
```

`install.sh` :
1. vérifie les prérequis (docker, compose v2, git, openssl, python3 + `bcrypt` + `cryptography`) ;
2. clone `devpod-ui` dans `vendor/` (nécessaire au build du portal et de Caddy) ;
3. génère les secrets et les fichiers `/data/{portal,doc,rag}.env` + `/data/pg_password.txt` (idempotent : un fichier déjà présent est conservé) ;
4. build le portal + Caddy, pull doc + rag, démarre la stack.

Les identifiants admin générés sont affichés en fin d'exécution et stockés dans `/data/*.env` (chmod 600).

## Démarrage manuel

```bash
docker compose -f dockers/docker-compose.all.yml up -d --build
docker compose -f dockers/docker-compose.all.yml ps
docker compose -f dockers/docker-compose.all.yml logs -f portal
```

## TLS

Par défaut le `Caddyfile` est en **HTTP simple** (préfixe `http://`) — adapté au
dev et au déploiement derrière un **Cloudflare Tunnel** qui termine le TLS.
Pour du **TLS direct** (wildcard DNS-01 Cloudflare), retirer le préfixe `http://`
de chaque site dans `dockers/Caddyfile` et y ajouter :

```caddy
tls {$ACME_EMAIL} {
    dns cloudflare {$CF_API_TOKEN}
}
```

(L'image Caddy embarque déjà le plugin `caddy-dns/cloudflare` — voir
`vendor/devpod-ui/deploy/Dockerfile.caddy`.) Renseigner `CF_API_TOKEN` et
`ACME_EMAIL` dans `/data/portal.env`.

## Hypothèses & points à vérifier

- **Routes workspace `ws-*`** : injectées dynamiquement par le portail dans le
  serveur Caddy `srv0`. Le `Caddyfile` évite tout catch-all `*.{BASE_DOMAIN}`
  qui les intercepterait (cf. commentaires du fichier).
- **rag** : le dépôt étant privé, le découpage des chemins de
  `rag.{BASE_DOMAIN}` (bloc `@api` du `Caddyfile`) et la liste des variables de
  `rag.env` sont **dérivés de `install.md`**. À reconcilier avec le `Caddyfile`
  et le `.env.prod.example` réels du dépôt rag si un service refuse de démarrer.
- **Bases de données** : chaque produit a sa propre Postgres, sans port publié
  (accès réseau interne `agflow` uniquement).

## Fichiers

| Fichier | Rôle |
|---|---|
| `docker-compose.all.yml` | stack unifiée (à utiliser) |
| `Caddyfile` | reverse-proxy unifié |
| `env/*.env.example` | templates d'environnement par produit |
| `docker-compose.{ui,doc,rag}.yml` | composes par produit (référence/standalone) |
