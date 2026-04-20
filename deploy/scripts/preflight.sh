#!/usr/bin/env bash
# =============================================================================
# preflight.sh — Pre-deployment readiness checks for file.gismartanalytics.com
#
# Verifies that all required conditions are met before running a deployment.
# Fails fast with clear messages. Safe to run repeatedly.
#
# Usage:
#   bash deploy/scripts/preflight.sh              # uses deploy.conf in script dir or repo root
#   DEPLOY_CONF=/path/to/deploy.conf bash ...     # explicit config path
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

ERRORS=0
WARNINGS=0

fail()    { log_error "$@"; ERRORS=$((ERRORS + 1)); }
warn()    { log_warn  "$@"; WARNINGS=$((WARNINGS + 1)); }
ok()      { log_info  "$@"; }
section() { log_step  "$@"; }

# ---- Load config ----
CONF="${DEPLOY_CONF:-}"
if [ -z "$CONF" ]; then
  if [ -f "${SCRIPT_DIR}/deploy.conf" ]; then
    CONF="${SCRIPT_DIR}/deploy.conf"
  elif [ -f "${SCRIPT_DIR}/../../deploy.conf" ]; then
    CONF="$(cd "${SCRIPT_DIR}/../.." && pwd)/deploy.conf"
  else
    fail "deploy.conf not found. Copy deploy.conf.example to deploy.conf and fill in values."
    echo ""; echo "Preflight FAILED with ${ERRORS} error(s)."
    exit 1
  fi
fi

# shellcheck disable=SC1090
. "$CONF"

echo ""
echo "================================================================="
echo "  Preflight checks — file.gismartanalytics.com deployment"
echo "  Config: ${CONF}"
echo "================================================================="
echo ""

# =========================================================================
section "1 — DEPLOY_REF (branch targeting)"
# =========================================================================
if [ -z "${DEPLOY_REF:-}" ] || [ "${DEPLOY_REF}" = "__CHANGE_ME__" ]; then
  fail "DEPLOY_REF is not set. Set it to the branch/tag you want to deploy (e.g. copilot/update-deploy-windows-cmd)."
elif [ "${DEPLOY_REF}" = "main" ]; then
  warn "DEPLOY_REF='main' — ensure you intend to deploy from the main branch, not a feature branch."
else
  ok "DEPLOY_REF='${DEPLOY_REF}'"
fi

# =========================================================================
section "2 — Required secret fields"
# =========================================================================
REQUIRED_SECRETS=(
  KEYCLOAK_ADMIN_USER
  KEYCLOAK_ADMIN_PASSWORD
  DB_PASSWORD
  MINIO_ACCESS_KEY
  MINIO_SECRET_KEY
  API_KEY
)
for VAR in "${REQUIRED_SECRETS[@]}"; do
  VAL="${!VAR:-}"
  if [ -z "$VAL" ] || [ "$VAL" = "__CHANGE_ME__" ]; then
    fail "${VAR} is not set or still has placeholder value in deploy.conf."
  else
    ok "${VAR} is set"
  fi
done

# =========================================================================
section "3 — Keycloak callback alignment"
# =========================================================================
EXPECTED_CALLBACK="${APP_BASE_URL}/auth/callback"
if [ -z "${APP_BASE_URL:-}" ] || [ "${APP_BASE_URL}" = "__CHANGE_ME__" ]; then
  fail "APP_BASE_URL is not set."
else
  ok "Keycloak redirect URI will be: ${EXPECTED_CALLBACK}"
  # Check if .env.example uses callback.php (mismatch indicator)
  PHP_ENV_EXAMPLE="$(cd "${SCRIPT_DIR}/../.." && pwd)/php-app/.env.example"
  if [ -f "${PHP_ENV_EXAMPLE}" ]; then
    if grep -q "callback\.php" "${PHP_ENV_EXAMPLE}"; then
      fail "php-app/.env.example still contains 'callback.php'. It must use '/auth/callback'."
    else
      ok "php-app/.env.example uses correct callback path"
    fi
  fi
fi

# =========================================================================
section "4 — Required binaries on this machine"
# =========================================================================
for BIN in ssh scp git; do
  if command -v "$BIN" &>/dev/null; then
    ok "${BIN} found: $(command -v "${BIN}")"
  else
    fail "${BIN} is not installed or not in PATH."
  fi
done

# =========================================================================
section "5 — SSH connectivity to deployment servers"
# =========================================================================
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

for PAIR in "${SSH_USER_SSO}@${SSO_HOST}" "${SSH_USER_APP}@${APP_HOST}" "${SSH_USER_PY}@${PYTHON_HOST}"; do
  if [ -z "$(echo "$PAIR" | cut -d@ -f1)" ] || echo "$PAIR" | grep -q "__CHANGE_ME__"; then
    fail "SSH target not configured: ${PAIR}"
    continue
  fi
  if ssh "${SSH_OPTS[@]}" "$PAIR" "echo ok" &>/dev/null; then
    ok "SSH OK: ${PAIR}"
  else
    fail "Cannot SSH to ${PAIR}. Verify key-based auth is configured (see setup-ssh-keys.sh)."
  fi
done

# =========================================================================
section "6 — Repo URL accessibility"
# =========================================================================
if [ -z "${REPO_URL:-}" ] || [ "${REPO_URL}" = "__CHANGE_ME__" ]; then
  fail "REPO_URL is not set."
else
  if command -v git &>/dev/null && git ls-remote --exit-code "${REPO_URL}" HEAD &>/dev/null; then
    ok "REPO_URL is reachable: ${REPO_URL}"
  else
    warn "Cannot reach REPO_URL='${REPO_URL}'. Check network connectivity and repo access."
  fi
fi

# =========================================================================
section "7 — Keycloak realm and client values"
# =========================================================================
[ "${KEYCLOAK_REALM:-}" = "forensics" ] && ok "KEYCLOAK_REALM=forensics" \
  || warn "KEYCLOAK_REALM='${KEYCLOAK_REALM:-}' — expected 'forensics'. Verify this is correct."

[ "${KEYCLOAK_CLIENT_ID:-}" = "file.gismartanalytics.com" ] && ok "KEYCLOAK_CLIENT_ID=file.gismartanalytics.com" \
  || warn "KEYCLOAK_CLIENT_ID='${KEYCLOAK_CLIENT_ID:-}' — expected 'file.gismartanalytics.com'. Verify."

# =========================================================================
section "8 — APP_DEPLOY_DIR value"
# =========================================================================
EXPECTED_DIR="/var/www/file.gismartanalytics"
[ "${APP_DEPLOY_DIR:-}" = "${EXPECTED_DIR}" ] && ok "APP_DEPLOY_DIR=${APP_DEPLOY_DIR}" \
  || warn "APP_DEPLOY_DIR='${APP_DEPLOY_DIR:-}' — expected '${EXPECTED_DIR}'. Verify."

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "================================================================="
if [ "$ERRORS" -gt 0 ]; then
  log_error "Preflight FAILED — ${ERRORS} error(s), ${WARNINGS} warning(s)."
  echo "  Fix the errors above before deploying."
  echo "================================================================="
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  log_warn "Preflight PASSED with ${WARNINGS} warning(s). Review warnings before deploying."
  echo "================================================================="
  exit 0
else
  log_info "Preflight PASSED — all checks OK. Ready to deploy."
  echo "================================================================="
  exit 0
fi
