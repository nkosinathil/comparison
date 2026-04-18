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
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)

# Local deploy config path:
# - preferred: ./deploy.conf (repo root)
# - fallback: ./deploy/scripts/deploy.conf
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DEPLOY_CONF="${LOCAL_DEPLOY_CONF:-}"

# =========================
# Helpers
# =========================
run_remote() {
  local user="$1"
  local host="$2"
  local cmd="$3"
  echo "==== [${user}@${host}] $cmd"
  printf '%s\n' "$cmd" | ssh "${SSH_OPTS[@]}" "${user}@${host}" "bash -seu"
}

resolve_local_deploy_conf() {
  if [[ -n "${LOCAL_DEPLOY_CONF}" ]]; then
    [[ -f "${LOCAL_DEPLOY_CONF}" ]] || {
      echo "ERROR: LOCAL_DEPLOY_CONF file not found: ${LOCAL_DEPLOY_CONF}" >&2
      exit 1
    }
    return
  fi

  if [[ -f "${SCRIPT_DIR}/deploy.conf" ]]; then
    LOCAL_DEPLOY_CONF="${SCRIPT_DIR}/deploy.conf"
  elif [[ -f "${SCRIPT_DIR}/deploy/scripts/deploy.conf" ]]; then
    LOCAL_DEPLOY_CONF="${SCRIPT_DIR}/deploy/scripts/deploy.conf"
  else
    echo "ERROR: Missing deploy.conf. Create one with:" >&2
    echo "  cp -n '${SCRIPT_DIR}/deploy/scripts/deploy.conf.example' '${SCRIPT_DIR}/deploy.conf'" >&2
    echo "  # then edit '${SCRIPT_DIR}/deploy.conf'" >&2
    exit 1
  fi
}

copy_deploy_conf() {
  local user="$1"
  local host="$2"
  local remote_conf="${CLONE_DIR}/deploy/scripts/deploy.conf"
  echo "==== [${user}@${host}] copy ${LOCAL_DEPLOY_CONF} -> ${remote_conf}"
  scp "${SSH_OPTS[@]}" "${LOCAL_DEPLOY_CONF}" "${user}@${host}:${remote_conf}"
}

sync_repo_cmd="
set -e
if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq git
  else
    echo 'git not found and apt-get unavailable. Install git manually, then re-run this script.' >&2
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
resolve_local_deploy_conf

# =========================
# 1) Sync repo on all servers
# =========================
run_remote "${SSO_USER}" "${SSO_HOST}" "${sync_repo_cmd}"
run_remote "${APP_USER}" "${APP_HOST}" "${sync_repo_cmd}"
run_remote "${PY_USER}" "${PY_HOST}" "${sync_repo_cmd}"

# =========================
# 1.5) Push deploy.conf to all server clones
# =========================
copy_deploy_conf "${SSO_USER}" "${SSO_HOST}"
copy_deploy_conf "${APP_USER}" "${APP_HOST}"
copy_deploy_conf "${PY_USER}" "${PY_HOST}"

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
