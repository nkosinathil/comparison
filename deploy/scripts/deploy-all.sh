#!/usr/bin/env bash
# =============================================================================
# deploy-all.sh — Master orchestrator for full multi-server deployment
#
# Coordinates: Keycloak -> App Server -> Python Server -> Validation
#
# For each target server, the orchestrator:
#   1. Clones (or updates) the repo on the remote server
#   2. Copies deploy.conf into the clone
#   3. Runs the setup script from within the clone
#
# This means the setup scripts' REPO_ROOT auto-detection works correctly —
# they find php-app/, python-backend/, database/, unified_compare_app.py
# as siblings of deploy/scripts/ inside the clone.
#
# Usage:
#   deploy-all.sh                   # Full deployment (SSH to each server)
#   deploy-all.sh --local-only app  # Run only app server setup locally
#   deploy-all.sh --validate-only   # Run validation only
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"
load_config

MODE="${1:-full}"
TARGET="${2:-}"

require_vars PROJECT_NAME REPO_URL DEPLOY_REF SSO_HOST APP_HOST PYTHON_HOST \
             SSH_USER_SSO SSH_USER_APP SSH_USER_PY \
             APP_BASE_URL KEYCLOAK_PUBLIC_URL DB_PASSWORD API_KEY

REMOTE_CLONE_DIR="/opt/${PROJECT_NAME}-deploy"

# ---- Helper: create backup before deploy ----
backup_on_remote() {
  local host="$1" user="$2" dir="$3" name="$4"
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  log_info "Creating backup on $host..."
  ssh_cmd "$user" "$host" "
    sudo mkdir -p /var/backups/${PROJECT_NAME}-${name} &&
    if [ -d '${dir}' ]; then
      sudo tar -czf '/var/backups/${PROJECT_NAME}-${name}/${name}-${ts}.tar.gz' -C '${dir}' . 2>/dev/null || true
    fi
  " 2>/dev/null || true
}

# ---- Helper: clone/update repo on a remote server and copy deploy.conf ----
prepare_remote() {
  local user="$1" host="$2"
  log_step "Preparing repo on $host..."

  # Ensure git is installed
  ssh_cmd "$user" "$host" "command -v git >/dev/null || (sudo apt-get update -qq && sudo apt-get install -y -qq git)" 2>/dev/null

  # Clone or update the repo
  ssh_cmd "$user" "$host" "
    if [ -d '${REMOTE_CLONE_DIR}/.git' ]; then
      cd '${REMOTE_CLONE_DIR}'
      git fetch origin 2>/dev/null || true
      git checkout '${DEPLOY_REF}' 2>/dev/null || git checkout 'origin/${DEPLOY_REF}' 2>/dev/null || true
      git pull origin '${DEPLOY_REF}' 2>/dev/null || true
    else
      sudo mkdir -p '${REMOTE_CLONE_DIR}'
      sudo chown '${user}:${user}' '${REMOTE_CLONE_DIR}'
      git clone --branch '${DEPLOY_REF}' --single-branch '${REPO_URL}' '${REMOTE_CLONE_DIR}' 2>/dev/null || \
        (git clone '${REPO_URL}' '${REMOTE_CLONE_DIR}' && cd '${REMOTE_CLONE_DIR}' && git checkout '${DEPLOY_REF}')
    fi
  "

  # Copy deploy.conf into the clone (contains secrets — not in the repo)
  local conf="${SCRIPT_DIR}/deploy.conf"
  if [ -f "$conf" ]; then
    scp -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
      "$conf" "${user}@${host}:${REMOTE_CLONE_DIR}/deploy/scripts/deploy.conf"
    log_info "deploy.conf pushed to $host"
  fi
}

# ---- Helper: run a setup script on a remote server ----
run_remote_setup() {
  local user="$1" host="$2" script="$3"
  ssh_sudo "$user" "$host" \
    "cd '${REMOTE_CLONE_DIR}/deploy/scripts' && bash '${script}'"
}

case "$MODE" in
  # ========================================================================
  # Full deployment
  # ========================================================================
  full)
    log_step "========================================="
    log_step "  Full Deployment: ${PROJECT_NAME}"
    log_step "  Repo: ${REPO_URL}"
    log_step "  Ref:  ${DEPLOY_REF}"
    log_step "  $(date)"
    log_step "========================================="
    echo ""

    # Phase 1: Keycloak (runs locally — only needs curl + jq, no repo on SSO)
    log_step "PHASE 1/4 — Keycloak Configuration"
    bash "${SCRIPT_DIR}/setup-keycloak.sh"
    load_config  # reload in case client secret was auto-saved
    echo ""

    # Phase 2: App Server
    log_step "PHASE 2/4 — App Server Deployment"
    backup_on_remote "$APP_HOST" "$SSH_USER_APP" "$APP_DEPLOY_DIR" "app"
    prepare_remote "$SSH_USER_APP" "$APP_HOST"
    run_remote_setup "$SSH_USER_APP" "$APP_HOST" "setup-app-server.sh"
    echo ""

    # Phase 3: Python Server
    log_step "PHASE 3/4 — Python Server Deployment"
    backup_on_remote "$PYTHON_HOST" "$SSH_USER_PY" "${PY_DEPLOY_DIR}/python-backend" "python"
    prepare_remote "$SSH_USER_PY" "$PYTHON_HOST"
    run_remote_setup "$SSH_USER_PY" "$PYTHON_HOST" "setup-python-server.sh"
    echo ""

    # Phase 4: Validation
    log_step "PHASE 4/4 — Validation"
    bash "${SCRIPT_DIR}/validate.sh"
    ;;

  # ========================================================================
  # Local-only mode (run on the target server itself)
  # Assumes you have already cloned the repo or are inside the clone.
  # ========================================================================
  --local-only)
    case "$TARGET" in
      keycloak) bash "${SCRIPT_DIR}/setup-keycloak.sh" ;;
      app)      bash "${SCRIPT_DIR}/setup-app-server.sh" ;;
      python)   bash "${SCRIPT_DIR}/setup-python-server.sh" ;;
      *)        die "Unknown target: $TARGET. Use keycloak, app, or python." ;;
    esac
    ;;

  # ========================================================================
  # Validate only
  # ========================================================================
  --validate-only)
    bash "${SCRIPT_DIR}/validate.sh"
    ;;

  *)
    die "Usage: deploy-all.sh [full|--local-only <target>|--validate-only]"
    ;;
esac
