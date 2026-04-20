#!/usr/bin/env bash
# =============================================================================
# cleanup-app-server.sh — Clean THIS app's deployment directory on the app server.
#
# SCOPE: Only removes files belonging to file.gismartanalytics.com (this project).
# SAFE:  Does NOT touch other apps, shared vhosts, other databases, or shared services.
# IDEMPOTENT: Safe to run multiple times — skips absent paths cleanly.
#
# Run as root or with sudo on the APP server (192.168.1.66) before a fresh deploy:
#   sudo bash deploy/scripts/cleanup-app-server.sh
#
# See docs/APP_SERVER_CLEANUP.md for the full list of what is and is not removed.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"
load_config

[ "$(id -u)" -eq 0 ] || die "This script must be run as root (or with sudo)."

APP_DIR="${APP_DEPLOY_DIR:-/var/www/file.gismartanalytics}"
APACHE_CONF="/etc/apache2/sites-available/comparison-app.conf"
APACHE_ENABLED="/etc/apache2/sites-enabled/comparison-app.conf"

log_step "App-server cleanup for: ${APP_DIR}"
log_warn "This will DELETE the contents of ${APP_DIR} and related artifacts for this app ONLY."
log_warn "Other apps, vhosts, databases, and shared services are NOT affected."

# Safety guard: refuse to operate on root or known shared directories
for FORBIDDEN in / /var/www /etc /opt /usr; do
  if [ "${APP_DIR}" = "${FORBIDDEN}" ]; then
    die "APP_DEPLOY_DIR='${APP_DIR}' is a protected path. Aborting."
  fi
done

# Confirm the directory is plausibly this app's (contains public/ or composer.json)
if [ -d "${APP_DIR}" ]; then
  if [ ! -f "${APP_DIR}/composer.json" ] && [ ! -d "${APP_DIR}/public" ]; then
    log_warn "${APP_DIR} exists but does not look like the PHP app (no composer.json or public/)."
    log_warn "If you are sure, delete it manually: rm -rf '${APP_DIR}'"
    die "Aborting to avoid accidental deletion of unrelated directory."
  fi
fi

# =========================================================================
log_step "1/5 — Disable Apache vhost for this app (if enabled)"
# =========================================================================
if [ -L "${APACHE_ENABLED}" ]; then
  a2dissite comparison-app 2>/dev/null || true
  systemctl reload apache2 2>/dev/null || true
  log_info "Apache vhost 'comparison-app' disabled"
else
  log_info "Apache vhost 'comparison-app' was not enabled — skipping"
fi

# =========================================================================
log_step "2/5 — Remove Apache vhost config for this app"
# =========================================================================
if [ -f "${APACHE_CONF}" ]; then
  rm -f "${APACHE_CONF}"
  log_info "Removed ${APACHE_CONF}"
else
  log_info "${APACHE_CONF} not present — skipping"
fi

# =========================================================================
log_step "3/5 — Remove app deployment directory"
# =========================================================================
if [ -d "${APP_DIR}" ]; then
  rm -rf "${APP_DIR}"
  log_info "Removed ${APP_DIR}"
else
  log_info "${APP_DIR} not present — skipping"
fi

# =========================================================================
log_step "4/5 — Remove app-specific upload temp directory"
# =========================================================================
UPLOAD_TMP="/tmp/comparison_uploads"
if [ -d "${UPLOAD_TMP}" ]; then
  rm -rf "${UPLOAD_TMP}"
  log_info "Removed ${UPLOAD_TMP}"
else
  log_info "${UPLOAD_TMP} not present — skipping"
fi

# =========================================================================
log_step "5/5 — Remove app-specific Apache log files (this app only)"
# =========================================================================
for LOGFILE in /var/log/apache2/comparison-error.log /var/log/apache2/comparison-access.log; do
  if [ -f "${LOGFILE}" ]; then
    rm -f "${LOGFILE}"
    log_info "Removed ${LOGFILE}"
  fi
done

# Reload Apache so it picks up the removed vhost cleanly
systemctl reload apache2 2>/dev/null || true

echo ""
log_info "============================================================="
log_info "  Cleanup complete. This app's files have been removed."
log_info "  Other apps, shared services, and databases are untouched."
log_info ""
log_info "  Next step: run the fresh deployment:"
log_info "    sudo bash deploy/scripts/setup-app-server.sh"
log_info "============================================================="
