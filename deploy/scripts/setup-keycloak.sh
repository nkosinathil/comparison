#!/usr/bin/env bash
# =============================================================================
# setup-keycloak.sh — Configure Keycloak realm and client
# Run from any machine that can reach SSO_HOST. Requires curl + jq.
# Idempotent: re-running updates existing resources.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"
load_config
require_vars KEYCLOAK_PUBLIC_URL KEYCLOAK_REALM KEYCLOAK_CLIENT_ID \
             KEYCLOAK_ADMIN_USER KEYCLOAK_ADMIN_PASSWORD APP_BASE_URL

command -v curl &>/dev/null || die "curl is required"
command -v jq &>/dev/null || die "jq is required"

KC_URL="${KEYCLOAK_PUBLIC_URL}"
REALM="${KEYCLOAK_REALM}"
CLIENT_ID="${KEYCLOAK_CLIENT_ID}"
REDIRECT="${APP_BASE_URL}/auth/callback"
LOGOUT_REDIRECT="${APP_BASE_URL}"

# ---- Get admin token ----
log_step "1/4 — Authenticate with Keycloak admin API"
TOKEN_RESP=$(curl -sf -X POST "${KC_URL}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=${KEYCLOAK_ADMIN_USER}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" 2>&1) || die "Failed to get admin token. Check KEYCLOAK_PUBLIC_URL, KEYCLOAK_ADMIN_USER, KEYCLOAK_ADMIN_PASSWORD."

ADMIN_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token')
[ "$ADMIN_TOKEN" != "null" ] && [ -n "$ADMIN_TOKEN" ] || die "Admin token is null. Response: $TOKEN_RESP"
log_info "Admin token obtained"

AUTH="Authorization: Bearer ${ADMIN_TOKEN}"

# ---- Create realm if not exists ----
log_step "2/4 — Ensure realm '${REALM}' exists"
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "${KC_URL}/admin/realms/${REALM}" -H "$AUTH")
if [ "$HTTP_CODE" = "404" ]; then
  curl -sf -X POST "${KC_URL}/admin/realms" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"realm\": \"${REALM}\", \"enabled\": true}" || die "Failed to create realm"
  log_info "Realm '${REALM}' created"
else
  log_info "Realm '${REALM}' already exists (HTTP $HTTP_CODE)"
fi

# ---- Create/update client ----
log_step "3/4 — Configure client '${CLIENT_ID}'"

CLIENT_JSON=$(cat <<EOF
{
  "clientId": "${CLIENT_ID}",
  "name": "File Comparison Web App",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "clientAuthenticatorType": "client-secret",
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false,
  "serviceAccountsEnabled": false,
  "redirectUris": ["${REDIRECT}"],
  "webOrigins": ["${APP_BASE_URL}"],
  "attributes": {
    "post.logout.redirect.uris": "${LOGOUT_REDIRECT}",
    "pkce.code.challenge.method": "S256"
  }
}
EOF
)

# Check if client exists
EXISTING=$(curl -sf "${KC_URL}/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}" -H "$AUTH" | jq -r '.[0].id // empty')

if [ -n "$EXISTING" ]; then
  curl -sf -X PUT "${KC_URL}/admin/realms/${REALM}/clients/${EXISTING}" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "$CLIENT_JSON" || die "Failed to update client"
  KC_INTERNAL_ID="$EXISTING"
  log_info "Client '${CLIENT_ID}' updated"
else
  curl -sf -X POST "${KC_URL}/admin/realms/${REALM}/clients" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "$CLIENT_JSON" || die "Failed to create client"
  KC_INTERNAL_ID=$(curl -sf "${KC_URL}/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}" -H "$AUTH" | jq -r '.[0].id')
  log_info "Client '${CLIENT_ID}' created"
fi

# Retrieve client secret
SECRET_RESP=$(curl -sf "${KC_URL}/admin/realms/${REALM}/clients/${KC_INTERNAL_ID}/client-secret" -H "$AUTH")
CLIENT_SECRET=$(echo "$SECRET_RESP" | jq -r '.value')
[ -n "$CLIENT_SECRET" ] && [ "$CLIENT_SECRET" != "null" ] || die "Failed to retrieve client secret"

log_info "Client secret: ${CLIENT_SECRET}"

# ---- Create realm roles ----
log_step "4/4 — Ensure realm roles exist"
for ROLE in admin analyst viewer; do
  HTTP=$(curl -so /dev/null -w "%{http_code}" -X POST "${KC_URL}/admin/realms/${REALM}/roles" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"name\": \"${ROLE}\"}" 2>/dev/null)
  if [ "$HTTP" = "201" ]; then
    log_info "Role '${ROLE}' created"
  else
    log_info "Role '${ROLE}' already exists"
  fi
done

# ---- Save secret to deploy.conf ----
CONF="${SCRIPT_DIR}/deploy.conf"
if [ -f "$CONF" ]; then
  sed -i "s|^KEYCLOAK_CLIENT_SECRET=.*|KEYCLOAK_CLIENT_SECRET=\"${CLIENT_SECRET}\"|" "$CONF"
  log_info "Client secret saved to deploy.conf"
fi

echo ""
echo "================================================================="
echo "  Keycloak setup complete."
echo "  Client ID:     ${CLIENT_ID}"
echo "  Client Secret:  ${CLIENT_SECRET}"
echo "  Redirect URI:  ${REDIRECT}"
echo "  Realm:         ${REALM}"
echo ""
echo "  Update KEYCLOAK_CLIENT_SECRET in deploy.conf (and re-run"
echo "  setup-app-server.sh to write the PHP .env with the new secret)"
echo "  if it was not auto-saved above."
echo "================================================================="
