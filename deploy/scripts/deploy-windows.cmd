@echo off
REM =============================================================================
REM deploy-windows.cmd — Windows CMD deployment driver
REM
REM Runs from a Windows machine with OpenSSH (ssh.exe) access to all 3 servers.
REM No bash, curl, jq, or Git required locally — everything runs on the servers.
REM
REM How it works:
REM   1. SSHes to App Server   -> clones repo, runs setup-keycloak.sh + setup-app-server.sh
REM   2. SSHes to Python Server -> clones repo, runs setup-python-server.sh
REM   3. SSHes to App Server   -> runs validate.sh
REM
REM The Keycloak setup runs FROM the App Server (which has curl + jq after setup).
REM This avoids needing any tools on your Windows machine beyond ssh.exe.
REM
REM Usage:
REM   1. Edit the variables below
REM   2. Run: deploy-windows.cmd
REM =============================================================================

REM ---- EDIT THESE VALUES ----
set REPO_URL=https://github.com/nkosinathil/comparison.git
set DEPLOY_REF=cursor/continue-migration-85c4
set CLONE_DIR=/opt/comparison-deploy

set SSO_HOST=192.168.1.59
set APP_HOST=192.168.1.66
set PYTHON_HOST=192.168.1.90

set SSH_USER_SSO=deploy
set SSH_USER_APP=deploy
set SSH_USER_PY=deploy

set APP_BASE_URL=http://192.168.1.66
set KEYCLOAK_PUBLIC_URL=http://192.168.1.59:8080
set KEYCLOAK_REALM=forensic
set KEYCLOAK_CLIENT_ID=comparison-web-app
set KEYCLOAK_ADMIN_USER=admin
set KEYCLOAK_ADMIN_PASSWORD=CHANGE_ME

set DB_NAME=comparison_app
set DB_USER=comparison_user
set DB_PASSWORD=CHANGE_ME_DB_PASSWORD

set MINIO_MANAGED=true
set MINIO_ACCESS_KEY=minioadmin
set MINIO_SECRET_KEY=CHANGE_ME_MINIO_SECRET

set API_KEY=CHANGE_ME_SHARED_API_KEY

set REDIS_DB_BROKER=8
set REDIS_DB_RESULT=9
set REDIS_DB_CACHE=10

REM ---- DO NOT EDIT BELOW THIS LINE ----

set SSH_OPTS=-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15

echo.
echo =========================================================
echo   File Comparison — Multi-Server Deployment (Windows)
echo   App:    %APP_HOST%
echo   Python: %PYTHON_HOST%
echo   SSO:    %SSO_HOST%
echo =========================================================
echo.

REM ---- Helper: write deploy.conf on a remote server ----
REM We echo the config line by line over SSH to avoid needing scp or local files.

echo [PHASE 0/4] Writing deploy.conf on servers...

REM Build the deploy.conf content as a heredoc-style SSH command
set CONF_BODY=PROJECT_NAME="comparison"^

REPO_URL="%REPO_URL%"^

DEPLOY_REF="%DEPLOY_REF%"^

REPO_ROOT=""^

SSO_HOST="%SSO_HOST%"^

APP_HOST="%APP_HOST%"^

PYTHON_HOST="%PYTHON_HOST%"^

SSH_USER_SSO="%SSH_USER_SSO%"^

SSH_USER_APP="%SSH_USER_APP%"^

SSH_USER_PY="%SSH_USER_PY%"^

APP_BASE_URL="%APP_BASE_URL%"^

KEYCLOAK_PUBLIC_URL="%KEYCLOAK_PUBLIC_URL%"^

KEYCLOAK_REALM="%KEYCLOAK_REALM%"^

KEYCLOAK_CLIENT_ID="%KEYCLOAK_CLIENT_ID%"^

KEYCLOAK_ADMIN_USER="%KEYCLOAK_ADMIN_USER%"^

KEYCLOAK_ADMIN_PASSWORD="%KEYCLOAK_ADMIN_PASSWORD%"^

KEYCLOAK_CLIENT_SECRET=""^

KEYCLOAK_CREATE_REALM="false"^

DB_NAME="%DB_NAME%"^

DB_USER="%DB_USER%"^

DB_PASSWORD="%DB_PASSWORD%"^

REDIS_DB_BROKER="%REDIS_DB_BROKER%"^

REDIS_DB_RESULT="%REDIS_DB_RESULT%"^

REDIS_DB_CACHE="%REDIS_DB_CACHE%"^

MINIO_MANAGED="%MINIO_MANAGED%"^

MINIO_ACCESS_KEY="%MINIO_ACCESS_KEY%"^

MINIO_SECRET_KEY="%MINIO_SECRET_KEY%"^

MINIO_DATA_DIR="/data/comparison-minio"^

MINIO_SERVICE_NAME="comparison-minio"^

API_KEY="%API_KEY%"^

APP_DEPLOY_DIR="/var/www/gismartanalytics"^

PY_DEPLOY_DIR="/opt/comparison"^

PY_VENV_DIR="/opt/comparison/venv"^

PY_LOG_DIR="/var/log/comparison-backend"^

PY_SERVICE_USER="comparison"^

PY_SERVICE_GROUP="comparison"^

PHP_VERSION=""^

FASTAPI_PORT="8000"^

REDIS_PORT="6379"^

MINIO_PORT="9000"^

MINIO_CONSOLE_PORT="9001"^

PG_PORT="5432"

REM =========================================================
echo.
echo [PHASE 1/4] App Server — clone repo + Keycloak setup + app setup
echo.

ssh %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "sudo apt-get update -qq && sudo apt-get install -y -qq git curl jq > /dev/null 2>&1; if [ -d '%CLONE_DIR%/.git' ]; then cd '%CLONE_DIR%' && git fetch origin && git checkout '%DEPLOY_REF%' 2>/dev/null; git checkout 'origin/%DEPLOY_REF%' 2>/dev/null; git pull origin '%DEPLOY_REF%' 2>/dev/null || true; else sudo mkdir -p '%CLONE_DIR%' && sudo chown %SSH_USER_APP%:%SSH_USER_APP% '%CLONE_DIR%' && git clone --branch '%DEPLOY_REF%' --single-branch '%REPO_URL%' '%CLONE_DIR%' 2>/dev/null || (git clone '%REPO_URL%' '%CLONE_DIR%' && cd '%CLONE_DIR%' && git checkout '%DEPLOY_REF%'); fi"

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to clone repo on App Server
    exit /b 1
)

REM Write deploy.conf on App Server
ssh %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "cat > %CLONE_DIR%/deploy/scripts/deploy.conf << 'DEPLOYEOF'
PROJECT_NAME=\"comparison\"
REPO_URL=\"%REPO_URL%\"
DEPLOY_REF=\"%DEPLOY_REF%\"
REPO_ROOT=\"\"
SSO_HOST=\"%SSO_HOST%\"
APP_HOST=\"%APP_HOST%\"
PYTHON_HOST=\"%PYTHON_HOST%\"
SSH_USER_SSO=\"%SSH_USER_SSO%\"
SSH_USER_APP=\"%SSH_USER_APP%\"
SSH_USER_PY=\"%SSH_USER_PY%\"
APP_BASE_URL=\"%APP_BASE_URL%\"
KEYCLOAK_PUBLIC_URL=\"%KEYCLOAK_PUBLIC_URL%\"
KEYCLOAK_REALM=\"%KEYCLOAK_REALM%\"
KEYCLOAK_CLIENT_ID=\"%KEYCLOAK_CLIENT_ID%\"
KEYCLOAK_ADMIN_USER=\"%KEYCLOAK_ADMIN_USER%\"
KEYCLOAK_ADMIN_PASSWORD=\"%KEYCLOAK_ADMIN_PASSWORD%\"
KEYCLOAK_CLIENT_SECRET=\"\"
KEYCLOAK_CREATE_REALM=\"false\"
DB_NAME=\"%DB_NAME%\"
DB_USER=\"%DB_USER%\"
DB_PASSWORD=\"%DB_PASSWORD%\"
REDIS_DB_BROKER=\"%REDIS_DB_BROKER%\"
REDIS_DB_RESULT=\"%REDIS_DB_RESULT%\"
REDIS_DB_CACHE=\"%REDIS_DB_CACHE%\"
MINIO_MANAGED=\"%MINIO_MANAGED%\"
MINIO_ACCESS_KEY=\"%MINIO_ACCESS_KEY%\"
MINIO_SECRET_KEY=\"%MINIO_SECRET_KEY%\"
MINIO_DATA_DIR=\"/data/comparison-minio\"
MINIO_SERVICE_NAME=\"comparison-minio\"
API_KEY=\"%API_KEY%\"
APP_DEPLOY_DIR=\"/var/www/gismartanalytics\"
PY_DEPLOY_DIR=\"/opt/comparison\"
PY_VENV_DIR=\"/opt/comparison/venv\"
PY_LOG_DIR=\"/var/log/comparison-backend\"
PY_SERVICE_USER=\"comparison\"
PY_SERVICE_GROUP=\"comparison\"
PHP_VERSION=\"\"
FASTAPI_PORT=\"8000\"
REDIS_PORT=\"6379\"
MINIO_PORT=\"9000\"
MINIO_CONSOLE_PORT=\"9001\"
PG_PORT=\"5432\"
DEPLOYEOF"

echo.
echo   Running setup-keycloak.sh on App Server...
ssh -tt %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "cd %CLONE_DIR%/deploy/scripts && bash setup-keycloak.sh"

echo.
echo   Running setup-app-server.sh on App Server...
ssh -tt %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "cd %CLONE_DIR%/deploy/scripts && sudo bash setup-app-server.sh"

REM =========================================================
echo.
echo [PHASE 2/4] Python Server — clone repo + setup
echo.

ssh %SSH_OPTS% %SSH_USER_PY%@%PYTHON_HOST% "sudo apt-get update -qq && sudo apt-get install -y -qq git > /dev/null 2>&1; if [ -d '%CLONE_DIR%/.git' ]; then cd '%CLONE_DIR%' && git fetch origin && git checkout '%DEPLOY_REF%' 2>/dev/null; git checkout 'origin/%DEPLOY_REF%' 2>/dev/null; git pull origin '%DEPLOY_REF%' 2>/dev/null || true; else sudo mkdir -p '%CLONE_DIR%' && sudo chown %SSH_USER_PY%:%SSH_USER_PY% '%CLONE_DIR%' && git clone --branch '%DEPLOY_REF%' --single-branch '%REPO_URL%' '%CLONE_DIR%' 2>/dev/null || (git clone '%REPO_URL%' '%CLONE_DIR%' && cd '%CLONE_DIR%' && git checkout '%DEPLOY_REF%'); fi"

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to clone repo on Python Server
    exit /b 1
)

REM Write deploy.conf on Python Server (same content)
ssh %SSH_OPTS% %SSH_USER_PY%@%PYTHON_HOST% "cat > %CLONE_DIR%/deploy/scripts/deploy.conf << 'DEPLOYEOF'
PROJECT_NAME=\"comparison\"
REPO_URL=\"%REPO_URL%\"
DEPLOY_REF=\"%DEPLOY_REF%\"
REPO_ROOT=\"\"
SSO_HOST=\"%SSO_HOST%\"
APP_HOST=\"%APP_HOST%\"
PYTHON_HOST=\"%PYTHON_HOST%\"
SSH_USER_SSO=\"%SSH_USER_SSO%\"
SSH_USER_APP=\"%SSH_USER_APP%\"
SSH_USER_PY=\"%SSH_USER_PY%\"
APP_BASE_URL=\"%APP_BASE_URL%\"
KEYCLOAK_PUBLIC_URL=\"%KEYCLOAK_PUBLIC_URL%\"
KEYCLOAK_REALM=\"%KEYCLOAK_REALM%\"
KEYCLOAK_CLIENT_ID=\"%KEYCLOAK_CLIENT_ID%\"
KEYCLOAK_ADMIN_USER=\"%KEYCLOAK_ADMIN_USER%\"
KEYCLOAK_ADMIN_PASSWORD=\"%KEYCLOAK_ADMIN_PASSWORD%\"
KEYCLOAK_CLIENT_SECRET=\"\"
KEYCLOAK_CREATE_REALM=\"false\"
DB_NAME=\"%DB_NAME%\"
DB_USER=\"%DB_USER%\"
DB_PASSWORD=\"%DB_PASSWORD%\"
REDIS_DB_BROKER=\"%REDIS_DB_BROKER%\"
REDIS_DB_RESULT=\"%REDIS_DB_RESULT%\"
REDIS_DB_CACHE=\"%REDIS_DB_CACHE%\"
MINIO_MANAGED=\"%MINIO_MANAGED%\"
MINIO_ACCESS_KEY=\"%MINIO_ACCESS_KEY%\"
MINIO_SECRET_KEY=\"%MINIO_SECRET_KEY%\"
MINIO_DATA_DIR=\"/data/comparison-minio\"
MINIO_SERVICE_NAME=\"comparison-minio\"
API_KEY=\"%API_KEY%\"
APP_DEPLOY_DIR=\"/var/www/gismartanalytics\"
PY_DEPLOY_DIR=\"/opt/comparison\"
PY_VENV_DIR=\"/opt/comparison/venv\"
PY_LOG_DIR=\"/var/log/comparison-backend\"
PY_SERVICE_USER=\"comparison\"
PY_SERVICE_GROUP=\"comparison\"
PHP_VERSION=\"\"
FASTAPI_PORT=\"8000\"
REDIS_PORT=\"6379\"
MINIO_PORT=\"9000\"
MINIO_CONSOLE_PORT=\"9001\"
PG_PORT=\"5432\"
DEPLOYEOF"

echo.
echo   Running setup-python-server.sh on Python Server...
ssh -tt %SSH_OPTS% %SSH_USER_PY%@%PYTHON_HOST% "cd %CLONE_DIR%/deploy/scripts && sudo bash setup-python-server.sh"

REM =========================================================
echo.
echo [PHASE 3/4] Validation — running from App Server
echo.

ssh %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "cd %CLONE_DIR%/deploy/scripts && bash validate.sh"

REM =========================================================
echo.
echo =========================================================
echo   Deployment complete.
echo   Open %APP_BASE_URL% in your browser to test.
echo =========================================================
echo.
