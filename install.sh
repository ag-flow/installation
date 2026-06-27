#!/usr/bin/env bash
# ============================================================================
# install.sh — Installe et démarre la stack ag-flow unifiée (portal + doc + rag)
#
#   1. Vérifie les prérequis (docker, compose, git, openssl, python3+bcrypt)
#   2. Clone/maj les sources nécessaires au build (vendor/devpod-ui)
#   3. Génère les secrets et les fichiers /data/*.env (idempotent : ne réécrit
#      pas un fichier déjà présent)
#   4. Build le portal + caddy, pull doc + rag, démarre la stack
#
# Usage :
#   sudo BASE_DOMAIN=dev.yoops.org ./install.sh
#   # variables optionnelles : DATA_ROOT (défaut /data), DEVPOD_UI_REF (branche)
#
# Le dépôt ag-flow/rag étant privé, exécuter au préalable sur l'hôte :
#   docker login ghcr.io
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="${DATA_ROOT:-/data}"
VENDOR_DIR="${REPO_ROOT}/vendor"
COMPOSE_FILE="${REPO_ROOT}/dockers/docker-compose.all.yml"
ENV_TPL_DIR="${REPO_ROOT}/dockers/env"
DEVPOD_UI_URL="https://github.com/gaelgael5/devpod-ui.git"
DEVPOD_UI_REF="${DEVPOD_UI_REF:-main}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ─── 1. Prérequis ────────────────────────────────────────────────────────────
log "Vérification des prérequis…"
command -v docker  >/dev/null || die "docker introuvable."
docker compose version >/dev/null 2>&1 || die "plugin 'docker compose' v2 requis."
command -v git     >/dev/null || die "git introuvable."
command -v openssl >/dev/null || die "openssl introuvable."
command -v python3 >/dev/null || die "python3 introuvable."
python3 -c "import bcrypt" 2>/dev/null \
    || die "module python 'bcrypt' requis (pip install bcrypt ou apt-get install python3-bcrypt)."
python3 -c "import cryptography.fernet" 2>/dev/null \
    || die "module python 'cryptography' requis (pip install cryptography)."

if [[ ! -f "${REPO_ROOT}/embedding_providers_pricing.yml" ]]; then
    die "embedding_providers_pricing.yml absent à la racine du dépôt (requis par rag-backend)."
fi

# ─── helpers de génération ──────────────────────────────────────────────────
gen_hex()   { openssl rand -hex "${1:-32}"; }
gen_pass()  { openssl rand -hex 16; }
fernet_key(){ python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"; }
# Hash bcrypt avec $ échappés ($→$$) pour survivre à l'interpolation env_file de compose.
bcrypt_escaped() {
    PASS="$1" python3 -c \
        "import bcrypt,os; print(bcrypt.hashpw(os.environ['PASS'].encode(), bcrypt.gensalt(12)).decode())" \
        | sed 's/\$/$$/g'
}

# ─── 2. Sources de build (devpod-ui) ─────────────────────────────────────────
mkdir -p "$VENDOR_DIR"
if [[ -d "${VENDOR_DIR}/devpod-ui/.git" ]]; then
    log "Mise à jour de vendor/devpod-ui (${DEVPOD_UI_REF})…"
    git -C "${VENDOR_DIR}/devpod-ui" fetch --depth 1 origin "$DEVPOD_UI_REF"
    git -C "${VENDOR_DIR}/devpod-ui" checkout -q FETCH_HEAD
else
    log "Clone de devpod-ui dans vendor/devpod-ui…"
    git clone --depth 1 --branch "$DEVPOD_UI_REF" "$DEVPOD_UI_URL" "${VENDOR_DIR}/devpod-ui"
fi

# ─── 3. Secrets & fichiers d'environnement ───────────────────────────────────
mkdir -p "$DATA_ROOT" "${DATA_ROOT}/.devpod"
chmod 700 "$DATA_ROOT"

if [[ -z "${BASE_DOMAIN:-}" ]]; then
    if [[ -t 0 ]]; then
        read -rp "Domaine de base (ex: dev.yoops.org) : " BASE_DOMAIN
    fi
    BASE_DOMAIN="${BASE_DOMAIN:-CHANGEME.example.com}"
fi
[[ "$BASE_DOMAIN" == CHANGEME* ]] && warn "BASE_DOMAIN non défini — éditez /data/*.env avant la prod."

# secret postgres partagé doc (fichier + DATABASE_URL doivent concorder)
if [[ ! -f "${DATA_ROOT}/pg_password.txt" ]]; then
    gen_pass > "${DATA_ROOT}/pg_password.txt"
    chmod 600 "${DATA_ROOT}/pg_password.txt"
fi
DOC_PG_PASSWORD="$(cat "${DATA_ROOT}/pg_password.txt")"

# ── portal.env ──
if [[ -f "${DATA_ROOT}/portal.env" ]]; then
    log "portal.env déjà présent — conservé."
else
    log "Génération de portal.env…"
    PORTAL_PG_PASS="$(gen_pass)"
    PORTAL_LOCAL_PASS="$(gen_pass)"
    PORTAL_LOCAL_HASH="$(bcrypt_escaped "$PORTAL_LOCAL_PASS")"
    sed -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${PORTAL_PG_PASS}|" \
        -e "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://portal:${PORTAL_PG_PASS}@portal-postgres:5432/portal|" \
        -e "s|^PORTAL_VAULT_KEK=.*|PORTAL_VAULT_KEK=$(gen_hex 32)|" \
        -e "s|^SESSION_SECRET_KEY=.*|SESSION_SECRET_KEY=$(gen_hex 32)|" \
        -e "s|^LOCAL_PASSWORD=.*|LOCAL_PASSWORD=${PORTAL_LOCAL_PASS}|" \
        -e "s|^LOCAL_PASSWORD_HASH=.*|LOCAL_PASSWORD_HASH=${PORTAL_LOCAL_HASH}|" \
        -e "s|^BASE_DOMAIN=.*|BASE_DOMAIN=${BASE_DOMAIN}|" \
        "${ENV_TPL_DIR}/portal.env.example" > "${DATA_ROOT}/portal.env"
    chmod 600 "${DATA_ROOT}/portal.env"
    printf '    portal : user=admin  password=%s\n' "$PORTAL_LOCAL_PASS"
fi

# ── doc.env ──
if [[ -f "${DATA_ROOT}/doc.env" ]]; then
    log "doc.env déjà présent — conservé."
else
    log "Génération de doc.env…"
    DOC_ADMIN_PASS="$(gen_pass)"
    sed -e "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://docflow:${DOC_PG_PASSWORD}@doc-postgres:5432/docflow|" \
        -e "s|^JWT_SECRET=.*|JWT_SECRET=$(gen_hex 32)|" \
        -e "s|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=${DOC_ADMIN_PASS}|" \
        -e "s|^ENCRYPTION_KEY=.*|ENCRYPTION_KEY=$(fernet_key)|" \
        "${ENV_TPL_DIR}/doc.env.example" > "${DATA_ROOT}/doc.env"
    chmod 600 "${DATA_ROOT}/doc.env"
    printf '    doc    : email=admin@example.com  password=%s\n' "$DOC_ADMIN_PASS"
fi

# ── rag.env ──
if [[ -f "${DATA_ROOT}/rag.env" ]]; then
    log "rag.env déjà présent — conservé."
else
    log "Génération de rag.env…"
    RAG_PG_PASS="$(gen_pass)"
    RAG_ADMIN_PASS="$(gen_pass)"
    RAG_ADMIN_HASH="$(bcrypt_escaped "$RAG_ADMIN_PASS")"
    sed -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${RAG_PG_PASS}|" \
        -e "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://rag:${RAG_PG_PASS}@rag-postgres:5432/rag_config|" \
        -e "s|^RAG_POSTGRES_ADMIN_URL=.*|RAG_POSTGRES_ADMIN_URL=postgresql://rag:${RAG_PG_PASS}@rag-postgres:5432/postgres|" \
        -e "s|^RAG_MASTER_KEY=.*|RAG_MASTER_KEY=$(gen_hex 32)|" \
        -e "s|^RAG_SESSION_SECRET=.*|RAG_SESSION_SECRET=$(gen_hex 32)|" \
        -e "s|^HARPOCRATE_DEK=.*|HARPOCRATE_DEK=$(gen_hex 32)|" \
        -e "s|^RAG_WEBHOOK_SECRET=.*|RAG_WEBHOOK_SECRET=$(gen_hex 32)|" \
        -e "s|^RAG_PUBLIC_URL=.*|RAG_PUBLIC_URL=https://rag.${BASE_DOMAIN}|" \
        -e "s|^RAG_BOOTSTRAP_ADMIN_PASSWORD_HASH=.*|RAG_BOOTSTRAP_ADMIN_PASSWORD_HASH=${RAG_ADMIN_HASH}|" \
        "${ENV_TPL_DIR}/rag.env.example" > "${DATA_ROOT}/rag.env"
    chmod 600 "${DATA_ROOT}/rag.env"
    printf '    rag    : user=admin  password=%s\n' "$RAG_ADMIN_PASS"
fi

# ─── 4. Build & démarrage ────────────────────────────────────────────────────
log "Build des images locales (portal + caddy)…"
docker compose -f "$COMPOSE_FILE" build portal caddy

log "Pull des images publiées (doc + rag)…"
docker compose -f "$COMPOSE_FILE" pull doc rag-backend rag-frontend \
    || warn "Pull partiel — vérifiez 'docker login ghcr.io' (images rag privées)."

log "Démarrage de la stack…"
docker compose -f "$COMPOSE_FILE" up -d

log "Stack démarrée. État :"
docker compose -f "$COMPOSE_FILE" ps

cat <<EOF

────────────────────────────────────────────────────────────────────
  Stack ag-flow démarrée. Accès (via le domaine de base ${BASE_DOMAIN}) :
    portal :  http://${BASE_DOMAIN}
    doc    :  http://doc.${BASE_DOMAIN}
    rag    :  http://rag.${BASE_DOMAIN}

  Secrets et identifiants : ${DATA_ROOT}/{portal,doc,rag}.env (chmod 600)
  Logs :  docker compose -f ${COMPOSE_FILE} logs -f <service>
────────────────────────────────────────────────────────────────────
EOF
