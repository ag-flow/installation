# Mode de travail — livraison prod ag-flow

Ce dépôt (`ag-flow/installation`) porte l'**installation prod** des produits ag-flow.

## Objectifs du projet

- **Cible** : UNE stack `docker compose` **unique** dans `deploy/docker-compose/`
  qui héberge **tous** les produits ag-flow (rag, doc, portal), installable par un
  **`deploy.sh` unique**, en **mode PULL** (images ghcr) reproductible.
- **Mutualisation** : tout composant partageable est **mutualisé** entre produits —
  en particulier **UNE seule base PostgreSQL** commune (une base + un rôle par
  produit), **un réseau** Docker commun, et **un reverse-proxy** (Caddy) commun.
- **Intégration incrémentale** : on ajoute les produits **dans la même stack**
  (pas un compose par produit). rag d'abord, puis doc mutualisé avec rag, puis portal.
- **Dépendances chez nous** : tout est versionné dans ce dépôt ; rien n'est tiré
  des dépôts sources à l'exécution. Validation réelle sur `test1`, idempotente.

## Blocs (livrés individuellement)

| Bloc | Produit | Dépôt source | Procédure de référence |
|---|---|---|---|
| 1/3 | **rag** | https://github.com/ag-flow/rag | `deploy/prod/deploy.md` + `deploy/prod/deploy.sh` |
| 2/3 | **doc** | https://github.com/ag-flow/doc | `deploy/prod-deploy.sh` |
| 3/3 | **portal** | https://github.com/gaelgael5/devpod-ui | *(à récupérer)* |

## Mode de livraison UNIQUE — reproductible, sans raccourcis

Pour chaque bloc, et uniquement de cette façon :

1. **Récupérer** la procédure officielle du dépôt source (`deploy/prod/deploy.md`
   et `deploy/prod/deploy.sh`).
2. **Adapter** le script d'installation pour que **TOUTES les dépendances
   viennent de NOTRE repo** (`admin-install-portal`). À l'exécution, rien ne doit
   être tiré du dépôt source ni d'ailleurs — tout est versionné chez nous.
3. **Pousser** le script et ses dépendances sur git (notre repo).
4. **Se connecter à la machine de test `test1`** et lancer le script pour faire
   l'installation réelle.
5. **Si ça bloque** : corriger dans notre repo → pousser → relancer le script sur
   `test1`. **Même cycle**, autant de fois que nécessaire.

### Règles strictes (pas de raccourcis)

- ❌ Pas d'installation manuelle hors script sur `test1`.
- ❌ Pas de dépendance tirée du dépôt source à l'exécution (tout vient de notre repo).
- ❌ Pas de « ça devrait marcher » : on valide en exécutant réellement sur `test1`.
- ✅ Toute correction passe par : modif dans le repo → push → relance du script.

## Définition de « fait » (par bloc)

- Le script, **depuis notre repo**, installe le bloc de bout en bout sur `test1`
  sans aucune intervention manuelle.
- L'installation est **vérifiée en fonctionnement** (health checks / accès).
- **Reproductible** : relancer le cycle redonne le même résultat.

## État d'avancement

- [x] **Bloc 1/3 — rag** : intégré à la stack `deploy/docker-compose/` (mode PULL).
- [x] **Bloc 2/3 — doc** : **mutualisé** avec rag dans la même stack (1 Postgres
  pgvector partagé, 1 Caddy, 1 réseau). Validé sur `test1` (192.168.10.168) —
  5 conteneurs `healthy`, bases `rag_config` + `docflow` dans le même Postgres,
  doc `/health` `db:true`, install idempotente.
  rag = hôte par défaut ; doc = `doc.{BASE_DOMAIN}`.
- [x] **Bloc 3/3 — portal** : **mutualisé** dans la même stack (rôle/base `portal`
  dans le Postgres partagé, Caddy unique avec API admin `:2019` pour les routes
  `ws-*`). Validé sur `test1` — 6 conteneurs `healthy`, 3 bases (`rag_config` +
  `docflow` + `portal`) dans 1 Postgres, portal/rag/doc `/health` OK, srv0 Caddy
  prêt pour l'injection dynamique, install idempotente.
  portal = hôte de base ; rag = `rag.{BASE_DOMAIN}` ; doc = `doc.{BASE_DOMAIN}`.

**Stack complète livrée** : `deploy/docker-compose/deploy.sh` installe les 3
produits mutualisés en une commande, en PULL, validé de bout en bout sur `test1`.
