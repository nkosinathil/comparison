#!/usr/bin/env bash
# =============================================================================
# deploy-all.sh — Master orchestrator for full multi-server deployment
#
# Coordinates: Keycloak -> App Server -> Python Server -> Validation
#
# Can be run from an operator workstation with SSH access to all servers,
# or directly on each server when run with --local-only <target>.
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

# ---- Helper: create backup before deploy ----
backup_app() {
  local host="$1" user="$2" dir="$3" name="$4"
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  log_info "Creating backup on $host..."
  ssh_cmd "$user" "$host" "
    sudo mkdir -p /var/backups/comparison-${name} &&
    if [ -d '${dir}' ]; then
      sudo tar -czf '/var/backups/comparison-${name}/${name}-${ts}.tar.gz' -C '${dir}' . 2>/dev/null || true
    fi
  " 2>/dev/null || true
}

# ---- Helper: copy deploy scripts to remote ----
push_scripts() {
  local user="$1" host="$2"
  log_info "Pushing deploy scripts to $host..."
  ssh_cmd "$user" "$host" "mkdir -p /tmp/comparison-deploy"
  scp -r -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    "${SCRIPT_DIR}/"*.sh "${SCRIPT_DIR}/deploy.conf" \
    "${user}@${host}:/tmp/comparison-deploy/" 2>/dev/null

  # Also push repo files needed by setup scripts
  local repo_root="${SCRIPT_DIR}/../.."
  ssh_cmd "$user" "$host" "mkdir -p /tmp/comparison-deploy/repo/{database,php-app,python-backend}"
  scp -r -o StrictHostKeyChecking=accept-new \
    "${repo_root}/database" "${repo_root}/php-app" "${repo_root}/python-backend" \
    "${repo_root}/unified_compare_app.py" \
    "${user}@${host}:/tmp/comparison-deploy/repo/" 2>/dev/null
}

case "$MODE" in
  # ========================================================================
  # Full deployment
  # ========================================================================
  full)
    log_step "========================================="
    log_step "  Full Deployment: ${PROJECT_NAME}"
    log_step "  Ref: ${DEPLOY_REF}"
    log_step "  $(date)"
    log_step "========================================="
    echo ""

    # Phase 1: Keycloak
    log_step "PHASE 1/4 — Keycloak Configuration"
    bash "${SCRIPT_DIR}/setup-keycloak.sh"
    # Reload config in case client secret was updated
    load_config
    echo ""

    # Phase 2: App Server
    log_step "PHASE 2/4 — App Server Deployment"
    backup_app "$APP_HOST" "$SSH_USER_APP" "$APP_DEPLOY_DIR" "app"
    push_scripts "$SSH_USER_APP" "$APP_HOST"
    ssh_sudo "$SSH_USER_APP" "$APP_HOST" \
      "cd /tmp/comparison-deploy && ln -sf repo/database database 2>/dev/null; ln -sf repo/php-app php-app 2>/dev/null; bash setup-app-server.sh"
    echo ""

    # Phase 3: Python Server
    log_step "PHASE 3/4 — Python Server Deployment"
    backup_app "$PYTHON_HOST" "$SSH_USER_PY" "${PY_DEPLOY_DIR}/python-backend" "python"
    push_scripts "$SSH_USER_PY" "$PYTHON_HOST"
    ssh_sudo "$SSH_USER_PY" "$PYTHON_HOST" \
      "cd /tmp/comparison-deploy && ln -sf repo/python-backend python-backend 2>/dev/null; ln -sf repo/unified_compare_app.py unified_compare_app.py 2>/dev/null; bash setup-python-server.sh"
    echo ""

    # Phase 4: Validation
    log_step "PHASE 4/4 — Validation"
    bash "${SCRIPT_DIR}/validate.sh"
    ;;

  # ========================================================================
  # Local-only mode (run on the target server itself)
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
