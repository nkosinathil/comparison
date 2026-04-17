#!/usr/bin/env bash
# =============================================================================
# setup-app-server.sh — Provision the Application Server (Apache + PHP + PG)
# Run ON the App Server as root or with sudo.
# Idempotent: safe to re-run.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"
load_config
require_vars APP_HOST APP_BASE_URL APP_DEPLOY_DIR DB_NAME DB_USER DB_PASSWORD \
             KEYCLOAK_PUBLIC_URL KEYCLOAK_REALM KEYCLOAK_CLIENT_ID KEYCLOAK_CLIENT_SECRET \
             PYTHON_HOST FASTAPI_PORT API_KEY

[ "$(id -u)" -eq 0 ] || die "This script must be run as root."

TS=$(timestamp)
PHP_V=$(detect_php_version 2>/dev/null || true)

# =========================================================================
log_step "1/8 — Install system packages"
# =========================================================================
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# Install PHP + Apache + PostgreSQL client
if [ -z "$PHP_V" ]; then
  # Install PHP (distro default)
  apt-get install -y -qq apache2 libapache2-mod-fcgid \
    php-fpm php-pgsql php-curl php-mbstring php-xml php-zip \
    postgresql-client unzip git curl > /dev/null
  PHP_V=$(detect_php_version)
else
  apt-get install -y -qq apache2 libapache2-mod-fcgid \
    "php${PHP_V}-fpm" "php${PHP_V}-pgsql" "php${PHP_V}-curl" \
    "php${PHP_V}-mbstring" "php${PHP_V}-xml" "php${PHP_V}-zip" \
    postgresql-client unzip git curl > /dev/null
fi
log_info "PHP version: $PHP_V"

# Install Composer if missing
if ! command -v composer &>/dev/null; then
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  log_info "Composer installed"
fi

# =========================================================================
log_step "2/8 — PostgreSQL: create database and user"
# =========================================================================
# Assumes PG is local or on APP_HOST. If remote, adjust DB_HOST.
DB_HOST_ACTUAL="${DB_HOST:-localhost}"

if sudo -u postgres psql -lqt 2>/dev/null | cut -d\| -f1 | grep -qw "$DB_NAME"; then
  log_info "Database $DB_NAME already exists"
else
  sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};" 2>/dev/null || true
  log_info "Created database $DB_NAME"
fi

sudo -u postgres psql -c "
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
      CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    ELSE
      ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
    END IF;
  END
  \$\$;
  GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
" 2>/dev/null
log_info "DB user $DB_USER configured"

# Grant schema privileges
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO ${DB_USER};" 2>/dev/null

# =========================================================================
log_step "3/8 — PostgreSQL: pg_hba.conf (allow app + python hosts)"
# =========================================================================
PG_HBA=$(sudo -u postgres psql -t -c "SHOW hba_file;" 2>/dev/null | xargs)
if [ -f "$PG_HBA" ]; then
  HBA_MARKER="# comparison-app-deploy"
  if ! grep -q "$HBA_MARKER" "$PG_HBA"; then
    {
      echo "$HBA_MARKER"
      echo "host  ${DB_NAME}  ${DB_USER}  127.0.0.1/32      scram-sha-256"
      echo "host  ${DB_NAME}  ${DB_USER}  ${APP_HOST}/32     scram-sha-256"
      echo "host  ${DB_NAME}  ${DB_USER}  ${PYTHON_HOST}/32  scram-sha-256"
    } >> "$PG_HBA"
    log_info "Added pg_hba entries"
  else
    log_info "pg_hba entries already present"
  fi

  # Ensure listen_addresses includes the app host
  PG_CONF=$(sudo -u postgres psql -t -c "SHOW config_file;" 2>/dev/null | xargs)
  if [ -f "$PG_CONF" ] && ! grep -q "listen_addresses.*'\\*'" "$PG_CONF"; then
    sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" "$PG_CONF" 2>/dev/null || true
  fi

  systemctl reload postgresql 2>/dev/null || true
fi

# =========================================================================
log_step "4/8 — Load database schema"
# =========================================================================
SCHEMA_FILE="${SCRIPT_DIR}/../../database/schema.sql"
if [ -f "$SCHEMA_FILE" ]; then
  # Check if tables already exist
  TABLE_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST_ACTUAL" -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" 2>/dev/null || echo 0)
  if [ "${TABLE_COUNT:-0}" -lt 5 ]; then
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST_ACTUAL" -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE"
    log_info "Schema loaded ($SCHEMA_FILE)"
  else
    log_info "Schema already loaded ($TABLE_COUNT tables found)"
  fi
else
  log_warn "Schema file not found: $SCHEMA_FILE — load manually."
fi

# =========================================================================
log_step "5/8 — Deploy PHP application"
# =========================================================================
ensure_dir "$APP_DEPLOY_DIR" "www-data:www-data"
ensure_dir "${APP_DEPLOY_DIR}/storage/logs" "www-data:www-data"
ensure_dir "${APP_DEPLOY_DIR}/storage/cache" "www-data:www-data"

# Copy application files
REPO_PHP="${SCRIPT_DIR}/../../php-app"
if [ -d "$REPO_PHP" ]; then
  rsync -a --delete --exclude='.env' --exclude='vendor/' \
    "${REPO_PHP}/" "${APP_DEPLOY_DIR}/"
  log_info "PHP app synced to $APP_DEPLOY_DIR"
fi

# Copy unified_compare_app.py (needed by Python backend but keep in repo root for reference)
REPO_ROOT="${SCRIPT_DIR}/../.."
if [ -f "${REPO_ROOT}/unified_compare_app.py" ]; then
  cp "${REPO_ROOT}/unified_compare_app.py" "${APP_DEPLOY_DIR}/" 2>/dev/null || true
fi

# Composer install
cd "$APP_DEPLOY_DIR"
if [ -f composer.json ]; then
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction 2>&1 | tail -5
  log_info "Composer dependencies installed"
fi

# =========================================================================
log_step "6/8 — Write PHP .env"
# =========================================================================
PHP_ENV="${APP_DEPLOY_DIR}/.env"
write_env_file "$PHP_ENV" \
  APP_NAME          "File Comparison System" \
  APP_ENV           "production" \
  APP_DEBUG         "false" \
  APP_URL           "$APP_BASE_URL" \
  APP_TIMEZONE      "UTC" \
  DB_CONNECTION     "pgsql" \
  DB_HOST           "${DB_HOST:-localhost}" \
  DB_PORT           "${PG_PORT:-5432}" \
  DB_DATABASE       "$DB_NAME" \
  DB_USERNAME       "$DB_USER" \
  DB_PASSWORD       "$DB_PASSWORD" \
  DB_SCHEMA         "public" \
  KEYCLOAK_URL          "$KEYCLOAK_PUBLIC_URL" \
  KEYCLOAK_REALM        "$KEYCLOAK_REALM" \
  KEYCLOAK_CLIENT_ID    "$KEYCLOAK_CLIENT_ID" \
  KEYCLOAK_CLIENT_SECRET "$KEYCLOAK_CLIENT_SECRET" \
  KEYCLOAK_REDIRECT_URI  "${APP_BASE_URL}/auth/callback" \
  KEYCLOAK_LOGOUT_REDIRECT "$APP_BASE_URL" \
  SESSION_DRIVER        "database" \
  SESSION_LIFETIME      "7200" \
  SESSION_COOKIE_NAME   "comparison_session" \
  SESSION_COOKIE_SECURE "false" \
  SESSION_COOKIE_HTTPONLY "true" \
  SESSION_COOKIE_SAMESITE "Lax" \
  PYTHON_API_URL    "http://${PYTHON_HOST}:${FASTAPI_PORT}" \
  PYTHON_API_TIMEOUT "60" \
  PYTHON_API_KEY    "$API_KEY" \
  LOG_FILE          "${APP_DEPLOY_DIR}/storage/logs/app.log" \
  AUDIT_LOG_FILE    "${APP_DEPLOY_DIR}/storage/logs/audit.log"

chown www-data:www-data "$PHP_ENV"
log_info "PHP .env written"

# =========================================================================
log_step "7/8 — Configure Apache"
# =========================================================================
FPM_SOCK="/run/php/php${PHP_V}-fpm.sock"

cat > /etc/apache2/sites-available/comparison-app.conf <<VHOST
<VirtualHost *:80>
    ServerName ${APP_HOST}
    DocumentRoot ${APP_DEPLOY_DIR}/public

    <Directory ${APP_DEPLOY_DIR}/public>
        AllowOverride All
        Require all granted
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^ index.php [QSA,L]
    </Directory>

    <FilesMatch \\.php\$>
        SetHandler "proxy:unix:${FPM_SOCK}|fcgi://localhost"
    </FilesMatch>

    LimitRequestBody 524288000

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"

    ErrorLog \${APACHE_LOG_DIR}/comparison-error.log
    CustomLog \${APACHE_LOG_DIR}/comparison-access.log combined
</VirtualHost>
VHOST

a2enmod rewrite headers proxy_fcgi setenvif 2>/dev/null || true
a2ensite comparison-app 2>/dev/null || true
a2dissite 000-default 2>/dev/null || true

# Fix ownership
chown -R www-data:www-data "$APP_DEPLOY_DIR"

systemctl restart "php${PHP_V}-fpm" apache2
log_info "Apache + PHP-FPM configured and restarted"

# =========================================================================
log_step "8/8 — Firewall (UFW)"
# =========================================================================
if command -v ufw &>/dev/null; then
  ufw allow 80/tcp comment "HTTP" 2>/dev/null || true
  ufw allow 443/tcp comment "HTTPS" 2>/dev/null || true
  ufw allow from "$PYTHON_HOST" to any port "$PG_PORT" proto tcp comment "PG from Python" 2>/dev/null || true
  ufw allow 22/tcp comment "SSH" 2>/dev/null || true
  log_info "UFW rules applied"
fi

log_info "=== App server setup complete ==="
