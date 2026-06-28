#!/usr/bin/env bash
# ============================================================================
# deploy/docker-compose/deploy.sh — Installation PROD mutualisée ag-flow
#                                    (portal + rag + doc)
#
# Toutes les dépendances viennent de CE dépôt (ag-flow/installation) — rien
# n'est tiré des dépôts sources à l'exécution.
#
# Mutualisation : 1 Postgres (rôles rag + docflow + portal), 1 réseau,
#                 1 Caddy (API admin :2019 pour les routes ws-* du portal).
# Mode de livraison UNIQUE = PULL : images pré-buildées ghcr.io/ag-flow.
#
# Usage (sur la machine cible) :
#   deploy/docker-compose/deploy.sh
#
# Variables d'environnement (optionnelles) :
#   DEPLOY_DIR      Répertoire d'installation     (défaut : /opt/agflow)
#   BASE_DOMAIN     Domaine de base (doc.<dom>)   (défaut : agflow.local)
#   RAG_PUBLIC_URL  URL publique rag              (défaut : http://<ip-hôte>)
#   IMAGE_TAG       Tag images rag               (défaut : latest)
#   DOC_IMAGE_TAG   Tag image doc                (défaut : latest)
#   GHCR_TOKEN      Token read:packages si privé (défaut : vide = images publiques)
#   GHCR_USER       Login GitHub associé au token (auto-détecté si absent)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/agflow}"
BASE_DOMAIN="${BASE_DOMAIN:-agflow.local}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DOC_IMAGE_TAG="${DOC_IMAGE_TAG:-latest}"
GHCR_TOKEN="${GHCR_TOKEN:-}"
GHCR_USER="${GHCR_USER:-}"

# Dépendances vendorisées dans ce dépôt (source = ce dossier).
CONFIG_FILES=(docker-compose.yml Caddyfile pricing.yml .env.example)

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
section() { echo -e "\n${BOLD}$*${RESET}"; }

# ─── Prérequis ────────────────────────────────────────────────────────────────
section "Vérification des prérequis..."
for cmd in docker curl python3 openssl; do
    command -v "$cmd" &>/dev/null || { error "$cmd n'est pas installé."; exit 1; }
    info "$cmd : OK"
done
docker compose version &>/dev/null || { error "Plugin docker compose v2 requis."; exit 1; }
info "docker compose : OK"
python3 -c "import bcrypt" 2>/dev/null \
    || { error "module python 'bcrypt' requis (pip install bcrypt / apt-get install python3-bcrypt)."; exit 1; }
info "python bcrypt : OK"

# ─── Répertoire cible + copie des dépendances (depuis CE dépôt) ───────────────
section "Installation dans $DEPLOY_DIR (dépendances depuis le repo)..."
mkdir -p "$DEPLOY_DIR"
for f in "${CONFIG_FILES[@]}"; do
    [ -f "${SCRIPT_DIR}/${f}" ] || { error "Dépendance manquante dans le repo : ${f}"; exit 1; }
    cp "${SCRIPT_DIR}/${f}" "${DEPLOY_DIR}/${f}"
    info "Copié : $f"
done
# Scripts d'init Postgres (création des rôles/bases docflow + portal)
[ -d "${SCRIPT_DIR}/initdb" ] || { error "Dossier initdb/ manquant dans le repo."; exit 1; }
rm -rf "${DEPLOY_DIR}/initdb"; cp -r "${SCRIPT_DIR}/initdb" "${DEPLOY_DIR}/initdb"
info "Copié : initdb/"
# Config Homepage (landing page)
[ -d "${SCRIPT_DIR}/homepage" ] || { error "Dossier homepage/ manquant dans le repo."; exit 1; }
rm -rf "${DEPLOY_DIR}/homepage"; cp -r "${SCRIPT_DIR}/homepage" "${DEPLOY_DIR}/homepage"
info "Copié : homepage/"

# ─── Génération du .env (non-interactif, idempotent) ──────────────────────────
section "Configuration (.env)..."
ENV_FILE="${DEPLOY_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
    warn ".env existant conservé (non écrasé)."
else
    HOST_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1 || true)"
    PUBLIC_URL="${RAG_PUBLIC_URL:-http://${HOST_IP:-localhost}}"

    # — secrets rag —
    PG_PASS="$(openssl rand -hex 24)"
    MASTER_KEY="$(openssl rand -hex 32)"
    SESSION_SECRET="$(openssl rand -hex 32)"
    HARPO_DEK="$(openssl rand -hex 32)"
    WEBHOOK_SECRET="$(openssl rand -hex 32)"
    RAG_ADMIN_PASS="$(openssl rand -hex 12)"
    # Hash bcrypt avec $ doublés ($$) pour l'interpolation env_file de compose.
    RAG_ADMIN_HASH="$(ADMIN_PASS="$RAG_ADMIN_PASS" python3 -c \
        "import bcrypt,os; print(bcrypt.hashpw(os.environ['ADMIN_PASS'].encode(), bcrypt.gensalt(12)).decode())" \
        | sed 's/\$/$$/g')"

    # — secrets doc —
    DOC_PG_PASS="$(openssl rand -hex 24)"
    DOC_JWT="$(openssl rand -hex 32)"
    DOC_FERNET="$(python3 -c "import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())")"
    DOC_ADMIN_PASS="$(openssl rand -hex 12)"

    # — secret postgres du portal —
    PORTAL_PG_PASS="$(openssl rand -hex 24)"

    sed -e "s|^IMAGE_TAG=.*|IMAGE_TAG=${IMAGE_TAG}|" \
        -e "s|^DOC_IMAGE_TAG=.*|DOC_IMAGE_TAG=${DOC_IMAGE_TAG}|" \
        -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${PG_PASS}|" \
        -e "s|^RAG_MASTER_KEY=.*|RAG_MASTER_KEY=${MASTER_KEY}|" \
        -e "s|^RAG_SESSION_SECRET=.*|RAG_SESSION_SECRET=${SESSION_SECRET}|" \
        -e "s|^HARPOCRATE_DEK=.*|HARPOCRATE_DEK=${HARPO_DEK}|" \
        -e "s|^RAG_WEBHOOK_SECRET=.*|RAG_WEBHOOK_SECRET=${WEBHOOK_SECRET}|" \
        -e "s|^RAG_PUBLIC_URL=.*|RAG_PUBLIC_URL=${PUBLIC_URL}|" \
        -e "s|^RAG_BOOTSTRAP_ADMIN_PASSWORD_HASH=.*|RAG_BOOTSTRAP_ADMIN_PASSWORD_HASH=${RAG_ADMIN_HASH}|" \
        -e "s|^BASE_DOMAIN=.*|BASE_DOMAIN=${BASE_DOMAIN}|" \
        -e "s|^DOC_DB_PASSWORD=.*|DOC_DB_PASSWORD=${DOC_PG_PASS}|" \
        -e "s|^JWT_SECRET=.*|JWT_SECRET=${DOC_JWT}|" \
        -e "s|^ENCRYPTION_KEY=.*|ENCRYPTION_KEY=${DOC_FERNET}|" \
        -e "s|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=${DOC_ADMIN_PASS}|" \
        -e "s|^PORTAL_DB_PASSWORD=.*|PORTAL_DB_PASSWORD=${PORTAL_PG_PASS}|" \
        "${DEPLOY_DIR}/.env.example" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    info ".env créé (chmod 600) — domaine : ${BASE_DOMAIN} — URL rag : ${PUBLIC_URL}"
    echo -e "  ${BOLD}rag admin${RESET} : user=admin  password=${RAG_ADMIN_PASS}"
    echo -e "  ${BOLD}doc admin${RESET} : email=admin@example.com  password=${DOC_ADMIN_PASS}"
fi

# ─── Initialisation /data du portal (CA, certs, config.yaml, .env) ─────────────
section "Initialisation du portal (/data)..."
PORTAL_DB_PASSWORD="$(grep -E '^PORTAL_DB_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)"
# Vendorisé depuis devpod-ui:scripts/install.sh — crée /data si absent (idempotent).
env PORTAL_BASE_DOMAIN="${BASE_DOMAIN}" \
    PORTAL_EXTERNAL_URL="https://${BASE_DOMAIN}" \
    bash "${SCRIPT_DIR}/portal/install.sh" \
        --data-root /data \
        --compose-file "${DEPLOY_DIR}/docker-compose.yml"

# Compléter /data/.env (clés non gérées par install.sh) — jamais réécrites.
PORTAL_ENV="/data/.env"
_pset() { # idempotent : ne réécrit pas une valeur déjà présente et non vide
    local k="$1" v="$2"
    if grep -qE "^$k=.+" "$PORTAL_ENV" 2>/dev/null; then return 0; fi
    if grep -qE "^$k=" "$PORTAL_ENV" 2>/dev/null; then
        sed -i "s|^$k=.*|$k=$v|" "$PORTAL_ENV"
    else
        echo "$k=$v" >> "$PORTAL_ENV"
    fi
}
_pset DATABASE_URL "postgresql+asyncpg://portal:${PORTAL_DB_PASSWORD}@postgres/portal"
_pset PORTAL_VAULT_KEK "$(openssl rand -hex 32)"
_pset DEV_MODE "false"
chmod 600 "$PORTAL_ENV"
PORTAL_LOCAL_PASS="$(grep -E '^LOCAL_PASSWORD=' "$PORTAL_ENV" | cut -d= -f2-)"
info "/data initialisé — portal admin : user=admin  password=${PORTAL_LOCAL_PASS:-<voir /data/.env>}"

# ─── Authentification GHCR (seulement si images privées) ──────────────────────
if [ -n "$GHCR_TOKEN" ]; then
    section "Authentification GHCR..."
    if [ -z "$GHCR_USER" ]; then
        GHCR_USER=$(curl -fsSL -H "Authorization: Bearer $GHCR_TOKEN" https://api.github.com/user \
            | python3 -c "import sys,json; print(json.load(sys.stdin)['login'])" 2>/dev/null || echo "")
        [ -n "$GHCR_USER" ] || { error "GHCR_USER introuvable — le passer explicitement."; exit 1; }
    fi
    echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
    info "Connecté à ghcr.io en tant que $GHCR_USER"
fi

# ─── Pull + démarrage ─────────────────────────────────────────────────────────
section "Téléchargement des images et démarrage..."
cd "$DEPLOY_DIR"
docker compose pull
docker compose up -d

# Le Caddyfile est bind-monté : un changement de routes n'est pas pris en compte
# si le conteneur caddy n'est pas recréé. On recharge explicitement la config à
# chaque déploiement (idempotent, sans downtime via l'API admin).
# NB : un reload réinitialise les routes ws-* injectées dynamiquement par le
# portal ; celui-ci les ré-applique. Acceptable lors d'une (ré)installation.
section "Rechargement de la configuration Caddy..."
if docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile 2>/dev/null; then
    info "Caddy rechargé (config à jour)."
else
    warn "Reload via API admin KO — redémarrage du conteneur caddy."
    docker compose restart caddy
fi

# ─── Migrations Alembic du portal (idempotent ; le portal migre aussi au boot) ─
section "Migrations Alembic (portal)..."
mig_ok=0
for i in $(seq 1 20); do
    if docker compose exec -T portal uv run alembic upgrade head >/dev/null 2>&1; then
        mig_ok=1; break
    fi
    sleep 5
done
[ "$mig_ok" -eq 1 ] && info "Migrations portal appliquées." \
    || warn "alembic non confirmé (le portal applique aussi les migrations au démarrage)."

# ─── Vérification (rag + doc + portal) ─────────────────────────────────────────
section "Vérification du démarrage..."
HTTP_PORT="$(grep -E '^HTTP_PORT=' "$ENV_FILE" | cut -d= -f2)"; HTTP_PORT="${HTTP_PORT:-80}"
DOMAIN="$(grep -E '^BASE_DOMAIN=' "$ENV_FILE" | cut -d= -f2)"; DOMAIN="${DOMAIN:-$BASE_DOMAIN}"

check() { # $1=label  $2=curl host header (vide=défaut)
    local host_opt=(); [ -n "$2" ] && host_opt=(-H "Host: $2")
    for i in $(seq 1 30); do
        if curl -fsS "${host_opt[@]}" "http://localhost:${HTTP_PORT}/health" >/dev/null 2>&1; then
            info "$1 : santé OK"; return 0
        fi; sleep 3
    done
    error "$1 : health KO après 90s."; return 1
}

# Homepage : pas d'endpoint /health → on vérifie que la VRAIE landing page est
# servie (marqueur de contenu), pas un 200 vide par défaut de Caddy.
check_home() {
    for i in $(seq 1 30); do
        body="$(curl -fsS -H "Host: home.${DOMAIN}" "http://localhost:${HTTP_PORT}/" 2>/dev/null || true)"
        if printf '%s' "$body" | grep -qiE 'Portail des ressources|homepage'; then
            info "homepage : OK (landing page servie)"; return 0
        fi; sleep 3
    done
    error "homepage : KO après 90s (contenu non servi)."; return 1
}

docker compose ps
rc=0
check "portal" "${DOMAIN}"      || rc=1
check "rag"    "rag.${DOMAIN}"  || rc=1
check "doc"    "doc.${DOMAIN}"  || rc=1
check_home                      || rc=1
if [ "$rc" -ne 0 ]; then
    error "Au moins un service ne répond pas. Logs :"
    docker compose logs portal backend doc homepage --tail=40 || true
    exit 1
fi

section "Déploiement ag-flow (portal + rag + doc + homepage) terminé."
echo "  Répertoire : ${DEPLOY_DIR}"
echo "  homepage   : http://home.${DOMAIN}/        (landing page)"
echo "  portal     : http://${DOMAIN}/             (hôte de base)"
echo "  rag        : http://rag.${DOMAIN}/ui"
echo "  doc        : http://doc.${DOMAIN}/"
echo "  Logs       : (cd ${DEPLOY_DIR} && docker compose logs -f)"
