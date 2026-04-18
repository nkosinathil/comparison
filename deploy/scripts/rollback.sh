#!/usr/bin/env bash
# =============================================================================
# rollback.sh — Rollback deployment on a single server
# Usage: rollback.sh [app|python] [backup_timestamp]
#
# Backups are created by deploy scripts as timestamped tarballs.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"
load_config

TARGET="${1:-}"
BACKUP_TS="${2:-}"

[ -n "$TARGET" ] || die "Usage: rollback.sh [app|python] [backup_timestamp]"

case "$TARGET" in
  app)
    DEPLOY_DIR="$APP_DEPLOY_DIR"
    BACKUP_DIR="/var/backups/comparison-app"
    SERVICES=("apache2")
    ;;
  python)
    DEPLOY_DIR="${PY_DEPLOY_DIR}/python-backend"
    BACKUP_DIR="/var/backups/comparison-python"
    SERVICES=("comparison-api" "comparison-worker" "comparison-beat")
    ;;
  *)
    die "Unknown target: $TARGET. Use 'app' or 'python'."
    ;;
esac

# List available backups if no timestamp given
if [ -z "$BACKUP_TS" ]; then
  echo "Available backups in $BACKUP_DIR:"
  ls -1t "${BACKUP_DIR}/"*.tar.gz 2>/dev/null || echo "  (none found)"
  echo ""
  die "Specify a backup timestamp, e.g.: rollback.sh $TARGET 20260412_153000"
fi

TARBALL="${BACKUP_DIR}/${TARGET}-${BACKUP_TS}.tar.gz"
[ -f "$TARBALL" ] || die "Backup not found: $TARBALL"

log_step "Stopping services..."
for svc in "${SERVICES[@]}"; do
  systemctl stop "$svc" 2>/dev/null || true
done

log_step "Restoring from $TARBALL..."
TEMP_RESTORE=$(mktemp -d)
tar -xzf "$TARBALL" -C "$TEMP_RESTORE"
rsync -a --delete "${TEMP_RESTORE}/" "${DEPLOY_DIR}/"
rm -rf "$TEMP_RESTORE"

log_step "Starting services..."
for svc in "${SERVICES[@]}"; do
  systemctl start "$svc"
done

log_info "Rollback complete for $TARGET from $BACKUP_TS"
