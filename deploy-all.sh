#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Required config (edit me)
# =========================
SSO_USER="${SSO_USER:-__SET_ME__}"
APP_USER="${APP_USER:-__SET_ME__}"
PY_USER="${PY_USER:-__SET_ME__}"

SSO_HOST="${SSO_HOST:-__SET_ME__}"
APP_HOST="${APP_HOST:-__SET_ME__}"
PY_HOST="${PY_HOST:-__SET_ME__}"

REPO_URL="${REPO_URL:-__SET_ME__}"
DEPLOY_REF="${DEPLOY_REF:-main}"

# Absolute path on remote servers
CLONE_DIR="${CLONE_DIR:-/opt/comparison-deploy}"

# App deploy dir from repo convention
APP_DEPLOY_DIR="${APP_DEPLOY_DIR:-/var/www/comparison.gismartanalytics}"

# NOTE: accept-new auto-trusts first-seen host keys for bootstrap automation.
# For stricter security, pre-seed known_hosts and change this to StrictHostKeyChecking=yes.
SSH_OPTS="${SSH_OPTS:--o BatchMode=yes -o StrictHostKeyChecking=accept-new}"

# =========================
# Helpers
# =========================
run_remote() {
  local user="$1"
  local host="$2"
  local cmd="$3"
  echo "==== [${user}@${host}] $cmd"
  ssh ${SSH_OPTS} "${user}@${host}" "bash -lc '$cmd'"
}

sync_repo_cmd="
set -e
if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq git
  else
    echo 'git not found and apt-get unavailable. Install git manually.' >&2
    exit 1
  fi
fi

if [ -d '${CLONE_DIR}/.git' ]; then
  cd '${CLONE_DIR}'
  git fetch origin
  (git checkout '${DEPLOY_REF}' 2>/dev/null || git checkout 'origin/${DEPLOY_REF}' 2>/dev/null)
  git pull origin '${DEPLOY_REF}' || true
else
  sudo mkdir -p '${CLONE_DIR}'
  sudo chown \"\$USER\":\"\$USER\" '${CLONE_DIR}'
  (git clone --branch '${DEPLOY_REF}' --single-branch '${REPO_URL}' '${CLONE_DIR}' \
    || (git clone '${REPO_URL}' '${CLONE_DIR}' && cd '${CLONE_DIR}' && git checkout '${DEPLOY_REF}'))
fi
"

require_set() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == "__SET_ME__" ]]; then
    echo "ERROR: Set ${name} before running." >&2
    exit 1
  fi
}

require_set "SSO_USER" "${SSO_USER}"
require_set "APP_USER" "${APP_USER}"
require_set "PY_USER" "${PY_USER}"
require_set "SSO_HOST" "${SSO_HOST}"
require_set "APP_HOST" "${APP_HOST}"
require_set "PY_HOST" "${PY_HOST}"
require_set "REPO_URL" "${REPO_URL}"

# =========================
# 1) Sync repo on all servers
# =========================
run_remote "${SSO_USER}" "${SSO_HOST}" "${sync_repo_cmd}"
run_remote "${APP_USER}" "${APP_HOST}" "${sync_repo_cmd}"
run_remote "${PY_USER}" "${PY_HOST}" "${sync_repo_cmd}"

# =========================
# 2) Run setup scripts
# =========================
run_remote "${SSO_USER}" "${SSO_HOST}" "cd '${CLONE_DIR}/deploy/scripts' && bash setup-keycloak.sh"
run_remote "${APP_USER}" "${APP_HOST}" "cd '${CLONE_DIR}/deploy/scripts' && sudo APP_DEPLOY_DIR='${APP_DEPLOY_DIR}' bash setup-app-server.sh"
run_remote "${PY_USER}" "${PY_HOST}" "cd '${CLONE_DIR}/deploy/scripts' && sudo bash setup-python-server.sh"

# =========================
# 3) Validate
# =========================
run_remote "${APP_USER}" "${APP_HOST}" "cd '${CLONE_DIR}/deploy/scripts' && bash validate.sh"

echo "✅ Deployment completed on SSO, APP, and PY servers."
