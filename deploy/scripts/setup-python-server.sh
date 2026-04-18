#!/usr/bin/env bash
# =============================================================================
# setup-python-server.sh — Provision the Python Server
# (FastAPI + Celery + Redis + MinIO)
# Run ON the Python Server as root or with sudo. Idempotent.
#
# MULTI-PLATFORM SAFE:
# - Redis: uses dedicated DB indices (configurable) to avoid collisions
# - MinIO: configurable MINIO_MANAGED mode; when false, uses existing MinIO
# - MinIO: uses app-specific service name and data dir to avoid conflicts
# - mc alias uses project-specific name, not "local"
# - All systemd units are prefixed with project name
# - Does NOT touch other services running on this server
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"
load_config
require_vars PYTHON_HOST PY_DEPLOY_DIR PY_VENV_DIR PY_LOG_DIR PY_SERVICE_USER PY_SERVICE_GROUP \
             MINIO_ACCESS_KEY MINIO_SECRET_KEY API_KEY FASTAPI_PORT REDIS_PORT MINIO_PORT \
             REDIS_DB_BROKER REDIS_DB_RESULT REDIS_DB_CACHE

[ "$(id -u)" -eq 0 ] || die "This script must be run as root."
require_repo

TS=$(timestamp)
MINIO_MANAGED="${MINIO_MANAGED:-true}"
MINIO_DATA_DIR="${MINIO_DATA_DIR:-/data/comparison-minio}"
MINIO_SERVICE="${MINIO_SERVICE_NAME:-comparison-minio}"
MC_ALIAS="${PROJECT_NAME:-comparison}-minio"

# =========================================================================
log_step "1/9 — Install system packages (additive)"
# =========================================================================
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip redis-server \
  git curl wget tesseract-ocr > /dev/null
log_info "System packages installed"

# =========================================================================
log_step "2/9 — Install MinIO (if managed and not present)"
# =========================================================================
if [ "$MINIO_MANAGED" = "true" ]; then
  if ! command -v minio &>/dev/null; then
    ARCH=$(dpkg --print-architecture 2>/dev/null || echo amd64)
    wget -q "https://dl.min.io/server/minio/release/linux-${ARCH}/minio" -O /usr/local/bin/minio
    chmod +x /usr/local/bin/minio
    log_info "MinIO binary installed"
  else
    log_info "MinIO already installed"
  fi
else
  log_info "MinIO not managed by this script (MINIO_MANAGED=false)"
fi

if ! command -v mc &>/dev/null; then
  ARCH=$(dpkg --print-architecture 2>/dev/null || echo amd64)
  wget -q "https://dl.min.io/client/mc/release/linux-${ARCH}/mc" -O /usr/local/bin/mc
  chmod +x /usr/local/bin/mc
  log_info "MinIO client (mc) installed"
else
  log_info "mc already installed"
fi

# =========================================================================
log_step "3/9 — Create service user"
# =========================================================================
ensure_user "$PY_SERVICE_USER"

# =========================================================================
log_step "4/9 — Create directory structure"
# =========================================================================
ensure_dir "$PY_DEPLOY_DIR" "${PY_SERVICE_USER}:${PY_SERVICE_GROUP}"
ensure_dir "$PY_LOG_DIR" "${PY_SERVICE_USER}:${PY_SERVICE_GROUP}"
ensure_dir "/tmp/comparison_processing" "${PY_SERVICE_USER}:${PY_SERVICE_GROUP}" 1777

if [ "$MINIO_MANAGED" = "true" ]; then
  ensure_dir "$MINIO_DATA_DIR" "${PY_SERVICE_USER}:${PY_SERVICE_GROUP}"
fi

# =========================================================================
log_step "5/9 — Deploy Python backend code"
# =========================================================================
REPO_PY="${REPO_ROOT}/python-backend"

if [ -d "$REPO_PY" ]; then
  rsync -a --delete --exclude='.env' --exclude='__pycache__/' --exclude='.pytest_cache/' \
    "${REPO_PY}/" "${PY_DEPLOY_DIR}/python-backend/"
  log_info "Python backend synced"
fi

if [ -f "${REPO_ROOT}/unified_compare_app.py" ]; then
  cp "${REPO_ROOT}/unified_compare_app.py" "${PY_DEPLOY_DIR}/"
  log_info "unified_compare_app.py copied"
fi

# =========================================================================
log_step "6/9 — Create virtualenv and install dependencies"
# =========================================================================
if [ ! -d "$PY_VENV_DIR" ]; then
  python3 -m venv "$PY_VENV_DIR"
  log_info "Virtualenv created"
fi

"${PY_VENV_DIR}/bin/pip" install --upgrade pip -q
"${PY_VENV_DIR}/bin/pip" install -r "${PY_DEPLOY_DIR}/python-backend/requirements.txt" -q 2>&1 | tail -3
log_info "Python dependencies installed"

chown -R "${PY_SERVICE_USER}:${PY_SERVICE_GROUP}" "$PY_DEPLOY_DIR"

# =========================================================================
log_step "7/9 — Write Python .env"
# =========================================================================
PY_ENV="${PY_DEPLOY_DIR}/python-backend/.env"
write_env_file "$PY_ENV" \
  APP_NAME          "comparison-backend" \
  APP_ENV           "production" \
  LOG_LEVEL         "INFO" \
  API_KEY           "$API_KEY" \
  FASTAPI_HOST      "0.0.0.0" \
  FASTAPI_PORT      "$FASTAPI_PORT" \
  FASTAPI_WORKERS   "4" \
  FASTAPI_RELOAD    "false" \
  REDIS_HOST        "localhost" \
  REDIS_PORT        "$REDIS_PORT" \
  REDIS_DB_BROKER   "$REDIS_DB_BROKER" \
  REDIS_DB_RESULT   "$REDIS_DB_RESULT" \
  REDIS_DB_CACHE    "$REDIS_DB_CACHE" \
  MINIO_ENDPOINT    "localhost:${MINIO_PORT}" \
  MINIO_ACCESS_KEY  "$MINIO_ACCESS_KEY" \
  MINIO_SECRET_KEY  "$MINIO_SECRET_KEY" \
  MINIO_SECURE      "false" \
  LOG_FILE          "${PY_LOG_DIR}/app.log" \
  LOG_FORMAT        "json" \
  TEMP_DIR          "/tmp/comparison_processing"

chown "${PY_SERVICE_USER}:${PY_SERVICE_GROUP}" "$PY_ENV"
chmod 600 "$PY_ENV"
log_info "Python .env written"

# =========================================================================
log_step "8/9 — Install systemd services"
# =========================================================================

# --- MinIO (only if managed) ---
if [ "$MINIO_MANAGED" = "true" ]; then
  cat > "/etc/systemd/system/${MINIO_SERVICE}.service" <<UNIT
[Unit]
Description=MinIO Object Storage (${PROJECT_NAME})
After=network.target
[Service]
Type=simple
User=${PY_SERVICE_USER}
Group=${PY_SERVICE_GROUP}
Environment="MINIO_ROOT_USER=${MINIO_ACCESS_KEY}"
Environment="MINIO_ROOT_PASSWORD=${MINIO_SECRET_KEY}"
ExecStart=/usr/local/bin/minio server ${MINIO_DATA_DIR} --address ":${MINIO_PORT}" --console-address ":${MINIO_CONSOLE_PORT:-9001}"
Restart=always
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
UNIT
  log_info "Systemd unit: ${MINIO_SERVICE}.service"
fi

# --- FastAPI ---
cat > /etc/systemd/system/comparison-api.service <<UNIT
[Unit]
Description=File Comparison FastAPI Backend
After=network.target redis.service ${MINIO_SERVICE}.service
Wants=redis.service
[Service]
Type=simple
User=${PY_SERVICE_USER}
Group=${PY_SERVICE_GROUP}
WorkingDirectory=${PY_DEPLOY_DIR}/python-backend
EnvironmentFile=${PY_ENV}
ExecStart=${PY_VENV_DIR}/bin/uvicorn app.main:app --host 0.0.0.0 --port ${FASTAPI_PORT} --workers 4 --log-level info
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=comparison-api
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${PY_DEPLOY_DIR} ${PY_LOG_DIR} /tmp/comparison_processing
[Install]
WantedBy=multi-user.target
UNIT

# --- Celery Worker ---
cat > /etc/systemd/system/comparison-worker.service <<UNIT
[Unit]
Description=File Comparison Celery Worker
After=network.target redis.service ${MINIO_SERVICE}.service comparison-api.service
Wants=redis.service
[Service]
Type=simple
User=${PY_SERVICE_USER}
Group=${PY_SERVICE_GROUP}
WorkingDirectory=${PY_DEPLOY_DIR}/python-backend
EnvironmentFile=${PY_ENV}
ExecStart=${PY_VENV_DIR}/bin/celery -A app.tasks.celery_app worker --loglevel=info --concurrency=4 --max-tasks-per-child=100
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=comparison-worker
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${PY_DEPLOY_DIR} ${PY_LOG_DIR} /tmp/comparison_processing
[Install]
WantedBy=multi-user.target
UNIT

# --- Celery Beat ---
cat > /etc/systemd/system/comparison-beat.service <<UNIT
[Unit]
Description=File Comparison Celery Beat Scheduler
After=network.target redis.service comparison-worker.service
Wants=redis.service
[Service]
Type=simple
User=${PY_SERVICE_USER}
Group=${PY_SERVICE_GROUP}
WorkingDirectory=${PY_DEPLOY_DIR}/python-backend
EnvironmentFile=${PY_ENV}
ExecStart=${PY_VENV_DIR}/bin/celery -A app.tasks.celery_app beat --loglevel=info --schedule=${PY_DEPLOY_DIR}/celerybeat-schedule
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=comparison-beat
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${PY_DEPLOY_DIR} ${PY_LOG_DIR}
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload

# =========================================================================
log_step "9/9 — Start services and create MinIO buckets"
# =========================================================================
SERVICES_TO_ENABLE="comparison-api comparison-worker comparison-beat"

# Redis: ensure running but do NOT restart (other apps may use it)
if ! systemctl is-active redis-server &>/dev/null; then
  systemctl enable redis-server
  systemctl start redis-server
  log_info "Redis started"
else
  log_info "Redis already running (not restarted — shared service)"
fi

if [ "$MINIO_MANAGED" = "true" ]; then
  systemctl enable "$MINIO_SERVICE"
  systemctl restart "$MINIO_SERVICE"
  SERVICES_TO_ENABLE="${SERVICES_TO_ENABLE} ${MINIO_SERVICE}"
  sleep 3
fi

# Create MinIO buckets (using project-specific alias, not 'local')
mc alias set "$MC_ALIAS" "http://localhost:${MINIO_PORT}" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" 2>/dev/null || true
for bucket in uploads results cache; do
  mc mb --ignore-existing "${MC_ALIAS}/${bucket}" 2>/dev/null || true
done
log_info "MinIO buckets ensured via alias '${MC_ALIAS}'"

systemctl enable $SERVICES_TO_ENABLE
systemctl restart comparison-api comparison-worker comparison-beat
sleep 2

# ---- Firewall (additive) ----
if command -v ufw &>/dev/null; then
  ufw allow from "${APP_HOST}" to any port "${FASTAPI_PORT}" proto tcp comment "FastAPI from App (${PROJECT_NAME})" 2>/dev/null || true
  ufw allow 22/tcp comment "SSH" 2>/dev/null || true
  log_info "UFW rules applied (additive)"
fi

log_info "=== Python server setup complete ==="
log_info "Redis DB indices: broker=${REDIS_DB_BROKER}, result=${REDIS_DB_RESULT}, cache=${REDIS_DB_CACHE}"
log_info "MinIO managed: ${MINIO_MANAGED}, service: ${MINIO_SERVICE}, data: ${MINIO_DATA_DIR}"
