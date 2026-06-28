#!/usr/bin/env bash
# ============================================================================
# deploy/docker-compose/rag/deploy.sh — Installation PROD du bloc rag (ag-flow.rag)
#
# Adapté de ag-flow/rag:deploy/prod/deploy.sh pour que TOUTES les dépendances
# viennent de CE dépôt (ag-flow/installation) : les fichiers de config sont
# vendorisés à côté de ce script — aucun téléchargement depuis ag-flow/rag.
#
# Mode de livraison UNIQUE = PULL : images pré-buildées depuis ghcr.io/ag-flow
# (reproductible, épinglable via IMAGE_TAG). Pas de build depuis les sources.
#
# Usage (sur la machine cible) :
#   deploy/docker-compose/rag/deploy.sh
#
# Variables d'environnement (optionnelles) :
#   DEPLOY_DIR   Répertoire d'installation        (défaut : /opt/rag)
#   RAG_PUBLIC_URL  URL publique du service        (défaut : http://<ip-hôte>)
#   IMAGE_TAG    Tag des images ghcr               (défaut : latest)
#   GHCR_TOKEN   Token read:packages si privé      (défaut : vide = images publiques)
#   GHCR_USER    Login GitHub associé au token     (auto-détecté si absent)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/rag}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
GHCR_TOKEN="${GHCR_TOKEN:-}"
GHCR_USER="${GHCR_USER:-}"

# Fichiers de config vendorisés dans ce dépôt (source = ce dossier).
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

# ─── Génération du .env (non-interactif, idempotent) ──────────────────────────
section "Configuration (.env)..."
ENV_FILE="${DEPLOY_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
    warn ".env existant conservé (non écrasé)."
else
    # IP hôte pour une URL publique par défaut exploitable en test.
    HOST_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1 || true)"
    PUBLIC_URL="${RAG_PUBLIC_URL:-http://${HOST_IP:-localhost}}"

    PG_PASS="$(openssl rand -hex 24)"
    MASTER_KEY="$(openssl rand -hex 32)"
    SESSION_SECRET="$(openssl rand -hex 32)"
    HARPO_DEK="$(openssl rand -hex 32)"
    WEBHOOK_SECRET="$(openssl rand -hex 32)"
    ADMIN_PASS="$(openssl rand -hex 12)"
    # Hash bcrypt avec $ doublés ($$) pour l'interpolation env_file de compose.
    ADMIN_HASH="$(ADMIN_PASS="$ADMIN_PASS" python3 -c \
        "import bcrypt,os; print(bcrypt.hashpw(os.environ['ADMIN_PASS'].encode(), bcrypt.gensalt(12)).decode())" \
        | sed 's/\$/$$/g')"

    sed -e "s|^IMAGE_TAG=.*|IMAGE_TAG=${IMAGE_TAG}|" \
        -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${PG_PASS}|" \
        -e "s|^RAG_MASTER_KEY=.*|RAG_MASTER_KEY=${MASTER_KEY}|" \
        -e "s|^RAG_SESSION_SECRET=.*|RAG_SESSION_SECRET=${SESSION_SECRET}|" \
        -e "s|^HARPOCRATE_DEK=.*|HARPOCRATE_DEK=${HARPO_DEK}|" \
        -e "s|^RAG_WEBHOOK_SECRET=.*|RAG_WEBHOOK_SECRET=${WEBHOOK_SECRET}|" \
        -e "s|^RAG_PUBLIC_URL=.*|RAG_PUBLIC_URL=${PUBLIC_URL}|" \
        -e "s|^RAG_BOOTSTRAP_ADMIN_PASSWORD_HASH=.*|RAG_BOOTSTRAP_ADMIN_PASSWORD_HASH=${ADMIN_HASH}|" \
        "${DEPLOY_DIR}/.env.example" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    info ".env créé (chmod 600) — URL publique : ${PUBLIC_URL}"
    echo -e "  ${BOLD}Admin bootstrap${RESET} : user=admin  password=${ADMIN_PASS}"
fi

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

# ─── Vérification ─────────────────────────────────────────────────────────────
section "Vérification du démarrage..."
HTTP_PORT="$(grep -E '^HTTP_PORT=' "$ENV_FILE" | cut -d= -f2)"; HTTP_PORT="${HTTP_PORT:-80}"
ok=0
for i in $(seq 1 30); do
    if curl -fsS "http://localhost:${HTTP_PORT}/health" >/dev/null 2>&1; then ok=1; break; fi
    sleep 3
done
docker compose ps
if [ "$ok" -eq 1 ]; then
    info "Santé OK : http://localhost:${HTTP_PORT}/health"
else
    error "Le health check n'a pas répondu après 90s. Logs :"
    docker compose logs backend --tail=50 || true
    exit 1
fi

section "Déploiement rag terminé."
echo "  Répertoire : ${DEPLOY_DIR}"
echo "  IHM        : http://localhost:${HTTP_PORT}/ui"
echo "  Logs       : (cd ${DEPLOY_DIR} && docker compose logs -f backend)"
