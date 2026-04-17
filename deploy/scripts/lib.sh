#!/usr/bin/env bash
# =============================================================================
# lib.sh — Shared functions for all deployment scripts
# Source this file: . "$(dirname "$0")/lib.sh"
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Colors (safe for non-tty) ----
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

die() { log_error "$@"; exit 1; }

# ---- Load config ----
load_config() {
  local conf="${1:-${SCRIPT_DIR}/deploy.conf}"
  [ -f "$conf" ] || die "Config not found: $conf — copy deploy.conf.example to deploy.conf and fill in values."
  # shellcheck disable=SC1090
  . "$conf"
}

# ---- Validate required vars ----
require_vars() {
  local missing=0
  for var in "$@"; do
    if [ -z "${!var:-}" ]; then
      log_error "Required variable $var is empty or unset in deploy.conf"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || die "Fix the missing variables above and re-run."
}

# ---- Safe .env writer (handles special chars) ----
write_env_var() {
  local file="$1" key="$2" value="$3"
  # Remove existing line for this key, then append with proper quoting
  if [ -f "$file" ]; then
    sed -i "/^${key}=/d" "$file"
  fi
  printf '%s="%s"\n' "$key" "$value" >> "$file"
}

write_env_file() {
  local file="$1"; shift
  : > "$file"  # truncate
  while [ $# -ge 2 ]; do
    write_env_var "$file" "$1" "$2"
    shift 2
  done
  chmod 600 "$file"
}

# ---- Remote execution helpers ----
ssh_cmd() {
  local user="$1" host="$2"; shift 2
  ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "${user}@${host}" "$@"
}

ssh_sudo() {
  local user="$1" host="$2"; shift 2
  ssh -tt -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "${user}@${host}" "sudo bash -c '$*'"
}

scp_to() {
  local user="$1" host="$2" src="$3" dst="$4"
  scp -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$src" "${user}@${host}:${dst}"
}

# ---- Idempotent helpers ----
ensure_user() {
  local user="$1"
  if ! id "$user" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin "$user"
    log_info "Created system user: $user"
  else
    log_info "User already exists: $user"
  fi
}

ensure_dir() {
  local dir="$1" owner="${2:-}" mode="${3:-755}"
  mkdir -p "$dir"
  chmod "$mode" "$dir"
  [ -n "$owner" ] && chown "$owner" "$dir"
  return 0
}

# ---- PHP version detection ----
detect_php_version() {
  if [ -n "${PHP_VERSION:-}" ]; then
    echo "$PHP_VERSION"
    return
  fi
  local v
  v=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null) || v=""
  if [ -z "$v" ]; then
    for candidate in 8.3 8.2 8.1; do
      if command -v "php${candidate}" &>/dev/null; then
        v="$candidate"; break
      fi
    done
  fi
  [ -n "$v" ] || die "Cannot detect PHP version. Install PHP 8.1+ or set PHP_VERSION in deploy.conf."
  echo "$v"
}

# ---- Timestamp for backups ----
timestamp() { date +%Y%m%d_%H%M%S; }
