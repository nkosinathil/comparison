#!/usr/bin/env bash
# =============================================================================
# validate.sh — Post-deployment validation and health checks
# Can be run from any machine that can reach all three servers.
# Does NOT exit on first failure; reports full PASS/FAIL summary.
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"
load_config
require_vars APP_HOST PYTHON_HOST SSO_HOST APP_BASE_URL KEYCLOAK_PUBLIC_URL \
             KEYCLOAK_REALM FASTAPI_PORT MINIO_PORT REDIS_PORT PG_PORT DB_NAME DB_USER

PASS=0; FAIL=0; TOTAL=0

check() {
  local name="$1" result="$2"
  TOTAL=$((TOTAL + 1))
  if [ "$result" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}  $name"
  else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}  $name"
  fi
}

http_check() {
  local name="$1" url="$2" expected="${3:-200}"
  local code
  code=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")
  if [ "$code" = "$expected" ]; then
    check "$name (HTTP $code)" 0
  else
    check "$name (HTTP $code, expected $expected)" 1
  fi
}

tcp_check() {
  local name="$1" host="$2" port="$3"
  if timeout 5 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
    check "$name ($host:$port)" 0
  else
    check "$name ($host:$port)" 1
  fi
}

echo ""
echo "============================================"
echo "  Deployment Validation"
echo "  $(date)"
echo "============================================"

# ---- Network connectivity ----
echo ""
log_step "Network Connectivity"
tcp_check "App Server SSH"      "$APP_HOST"    22
tcp_check "Python Server SSH"   "$PYTHON_HOST" 22
tcp_check "SSO Server SSH"      "$SSO_HOST"    22

# ---- Keycloak / SSO ----
echo ""
log_step "Keycloak / SSO"
http_check "Keycloak realm" "${KEYCLOAK_PUBLIC_URL}/realms/${KEYCLOAK_REALM}" 200
http_check "Keycloak OIDC discovery" "${KEYCLOAK_PUBLIC_URL}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration" 200

# ---- PostgreSQL ----
echo ""
log_step "PostgreSQL"
tcp_check "PostgreSQL port" "$APP_HOST" "$PG_PORT"

if command -v psql &>/dev/null; then
  PGPASSWORD="$DB_PASSWORD" psql -h "$APP_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null
  check "PostgreSQL auth + query" $?
  TABLE_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$APP_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" 2>/dev/null || echo 0)
  [ "${TABLE_COUNT:-0}" -ge 5 ]
  check "Schema loaded (${TABLE_COUNT} tables)" $?
else
  check "PostgreSQL client (psql not installed locally — skip)" 0
fi

# ---- Python Backend ----
echo ""
log_step "Python Backend Services"
tcp_check "FastAPI port"   "$PYTHON_HOST" "$FASTAPI_PORT"
tcp_check "Redis port"     "$PYTHON_HOST" "$REDIS_PORT"
tcp_check "MinIO port"     "$PYTHON_HOST" "$MINIO_PORT"

http_check "FastAPI health"    "http://${PYTHON_HOST}:${FASTAPI_PORT}/health" 200
http_check "FastAPI liveness"  "http://${PYTHON_HOST}:${FASTAPI_PORT}/health/live" 200
http_check "FastAPI root"      "http://${PYTHON_HOST}:${FASTAPI_PORT}/" 200

# Check API key enforcement
if [ -n "${API_KEY:-}" ]; then
  code=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 \
    -X POST "http://${PYTHON_HOST}:${FASTAPI_PORT}/api/process" \
    -H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "000")
  [ "$code" = "401" ]
  check "API key enforcement (expected 401, got $code)" $?
fi

# MinIO health
http_check "MinIO health" "http://${PYTHON_HOST}:${MINIO_PORT}/minio/health/live" 200

# ---- PHP Application ----
echo ""
log_step "PHP Application"
tcp_check "Apache HTTP" "$APP_HOST" 80

http_check "App base URL" "${APP_BASE_URL}/" "302"
http_check "App login redirect" "${APP_BASE_URL}/login" "302"

# Static assets
http_check "CSS asset" "${APP_BASE_URL}/css/app.css" 200
http_check "JS asset"  "${APP_BASE_URL}/js/app.js" 200

# ---- Auth flow (partial — redirects to Keycloak) ----
echo ""
log_step "Auth Flow"
LOGIN_RESP=$(curl -sI --connect-timeout 5 --max-time 10 "${APP_BASE_URL}/login" 2>/dev/null || true)
if echo "$LOGIN_RESP" | grep -qi "location.*${KEYCLOAK_PUBLIC_URL}"; then
  check "Login redirects to Keycloak" 0
else
  check "Login redirects to Keycloak (location header not found)" 1
fi

# ---- Summary ----
echo ""
echo "============================================"
echo "  Results: ${PASS} passed, ${FAIL} failed (${TOTAL} total)"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo -e "  ${RED}DEPLOYMENT HAS FAILURES — review above${NC}"
  exit 1
else
  echo -e "  ${GREEN}ALL CHECKS PASSED${NC}"
  exit 0
fi
