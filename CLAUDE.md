# Mode de travail — livraison prod ag-flow

Ce dépôt (`admin-install-portal`) porte l'**installation prod** des trois produits
ag-flow. Chaque bloc a sa propre procédure de livraison prod, fonctionnelle et
**reproductible**.

## Blocs (livrés individuellement)

| Bloc | Produit | Dépôt source | Procédure de référence |
|---|---|---|---|
| 1/3 | **rag** | https://github.com/ag-flow/rag | `deploy/prod/deploy.md` + `deploy/prod/deploy.sh` |
| 2/3 | **doc** | https://github.com/ag-flow/doc | *(à récupérer)* |
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

- [x] **Bloc 1/3 — rag** : `docker-compose/rag/` (mode PULL). Validé sur `test1`
  (192.168.10.168) — stack `healthy`, `/health` + `/ui/` OK, install idempotente.
- [ ] Bloc 2/3 — doc.
- [ ] Bloc 3/3 — portal.
