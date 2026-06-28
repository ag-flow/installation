# Architecture des produits ag-flow & frontières

> Doc d'orientation du système ag-flow. Décrit **comment les trois produits se relient** et **où passent les frontières** — en particulier ce que le socle documentaire (`doc`/docflow) s'interdit, pour que le futur module de workflow ait une assise stable. Complète la mécanique de déploiement (`deploy/docker-compose/`), ne la remplace pas.

## Objectif central : le cadrage fluide

L'étoile polaire n'est pas « un outil de plus », c'est **l'interaction fluide pendant les sessions de cadrage**. Dans une session avec Claude (Web), via le connecteur → portail, on veut pouvoir, sans friction : **lire** la base documentaire, **interroger** le moteur de recherche, **écrire des choses à faire**, **déclencher des agents** pour les traiter, le tout adossé à des **règles communes** partagées entre projets. Cette conversation de cadrage *est* le cas d'usage que le système sert.

## Les trois produits

| Produit | Dépôt | Rôle | Ne fait pas |
|---|---|---|---|
| **docflow** (`doc`) | `ag-flow/doc` | **Socle documentaire structuré** : documents markdown arborescents, types fonctionnels, propriétés typées, statuts (= propriété), relations, vues, exposé en **MCP**. | Ne cherche pas le contenu ; ne porte aucune règle de workflow. |
| **agflow-rag** (`rag`) | `ag-flow/rag` | **Recherche** : indexe le contenu et répond aux requêtes (lexical *et* sémantique, embeddings/pgvector). | Ne stocke pas la structure documentaire ; consomme docflow en client. |
| **devpod-ui** (`portal`) | `gaelgael5/devpod-ui` | **(a)** pilote des **sessions d'agents** (Claude Code en conteneur, via SSH/mTLS) ; **(b)** **portail / gateway MCP** qui fédère docflow + rag. | N'est pas la base de données ni le moteur de recherche. |

## Comment ils se relient

```
        Claude (Web) — session de cadrage
                │   connecteur MCP
                ▼
   ┌───────────────────────────────────────────┐
   │  devpod-ui — PORTAL / gateway MCP          │
   │  (fédère les outils, namespace par produit)│
   └───────────────┬───────────────┬────────────┘
                   │               │
        MCP (M10)  ▼               ▼  API / MCP
            ┌────────────┐   ┌────────────┐
            │  docflow   │   │ agflow-rag │
            │  (le store)│   │ (recherche)│
            └─────┬──────┘   └────────────┘
                  │ pilote
                  ▼
        sessions d'agents (Claude Code)
        → traitent un sujet, puis écrivent
          le résultat / le statut dans docflow via MCP
```

Le portail est le **point d'entrée unique** depuis Claude Web : il référence docflow et rag et expose leurs outils sous un namespace par produit. Un agent lancé par le portail reboucle sur docflow (écriture via MCP) — la session de cadrage et les agents partagent la même base.

## La séparation docflow / rag est intentionnelle

docflow **ne cherche pas le contenu** — ni en sémantique, ni en lexical. Toute la recherche est le métier d'**agflow-rag**. La seule exception est le **trigram sur les titres** pour le picker de liens (référencement intra-document) : un confort d'édition, pas un moteur de recherche.

Cette coupure est **un choix d'architecture**, pas une dépendance subie : on ne réimplémente aucune brique de recherche dans le socle, et les deux produits restent découplés (le RAG est un **client** de l'API/MCP de docflow). Une future fonction « chercher dans le RAG depuis le portail » viendra côté portail — elle reste **non essentielle** et hors socle.

## docflow : points d'extension pour les workflows

docflow est conçu pour être **consommé** (MCP-first) et **étendu** par-dessus. Il expose les briques neutres avec lesquelles n'importe quelle méthodologie se construit :

| Brique | Mécanisme | Spec |
|---|---|---|
| **État** | statut = `restricted_list` ordonnée (slug stable, label, position, couleur) | socle |
| **Événement d'état** | journal de changements + automates configurables | `30_MCHG`, `32_MAUTO` |
| **Relations** | lien de contenu + requête inverse (backlinks) + référence typée | `31_MREF`, `33_MBLK`, `38_MREL` |
| **Classification** | propriétés typées (`text/int/date/bool/url/float`), restricted_list, multi-valeur | `34_MPTS`, `39_MMV` |
| **Vues** | boards/tables filtrés sauvegardés | `37_MVIEW` |
| **Programmatique** | surface MCP (lire/écrire docs, statuts, relations) | `M10` |

## La frontière : ce que docflow s'interdit

**docflow stocke des états et émet des événements ; il n'encode aucune règle de transition.** Tout ce qui relève de la *méthodologie* appartient au **module de workflow** (à venir), pas au socle :

- ❌ transitions autorisées/interdites, gardes, machine à états ;
- ❌ « tel statut déclenche tel agent » **câblé** (un automate `32` que l'utilisateur branche est de la *configuration*, pas une règle du socle) ;
- ❌ cadencement et enchaînements inter-documents (« story `done` → la feature avance ») ;
- ❌ type `task` câblé : « tâche » est déjà une notion de méthodologie. Le socle fournit types + statut + relations ; *chaque* workflow définit *sa* notion de travail.

Le test de dosage : dès qu'une fonctionnalité dirait « **si** tel statut **alors** telle transition est permise/automatique », c'est du workflow — hors socle.

## Le module workflow (à venir) — multi-méthodologies

Plusieurs méthodologies cohabiteront sur **le même corpus** docflow, sans point commun entre elles :

- le **dev** cadencé en **agile/SAFe** (epic ⊃ feature ⊃ story/atdd, pipelines de statut par type) ;
- la **stratégie métier**, dont la cadence n'a rien d'agile — sinon qu'elle **attend les produits** livrés par le dev.

Le **point de couplage** entre les deux (le métier « attend » un produit du dev) est une **simple relation typée `38`** entre deux documents de types différents (ex. `produit-attendu ⟶ epic`). docflow stocke *que* ça pointe, **jamais** *ce que ça veut dire* — l'interprétation appartient à chaque workflow.

Conséquence : les templates sont des **pairs**. `agile-basic.yaml` et un futur `strategie-metier.yaml` sont au même rang ; **docflow n'en privilégie aucun**. Un statut, des types, des relations — le dénominateur commun neutre.

## Non-objectifs assumés

Hérités des outils PKM (Logseq/Obsidian) mais **délibérément hors périmètre**, pour ne pas diluer le socle :

| Non-objectif | Pourquoi | Où le besoin est couvert |
|---|---|---|
| Journal / daily notes | docflow n'est pas un outil de prise de notes perso | — |
| Canvas / vue spatiale | hors mission (store structuré, pas tableau blanc) | — |
| Collaboration temps réel | le multi-utilisateur async + lock optimiste (409) suffit | `21_RW` |
| Système de plugins UI | l'extensibilité passe par MCP + automates | `M10`, `32` |
| Recherche de contenu (lexical/sémantique) | métier exclusif du RAG | agflow-rag |
| Transclusion au niveau bloc | borderline basse priorité ; le besoin de « retrouver une section » est couvert par le RAG | agflow-rag |

## Déploiement

Les trois produits s'installent en une stack `docker compose` **unique** et mutualisée (un Postgres, un Caddy, un réseau), en mode PULL reproductible. Voir `deploy/docker-compose/` (`deploy.sh`, `README.md`). Cette doc-ci couvre le **pourquoi** ; le **comment** vit dans `deploy/`.
