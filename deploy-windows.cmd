@echo off
setlocal DisableDelayedExpansion
REM =============================================================================
REM deploy-windows.cmd — Windows CMD deployment driver
REM =============================================================================

REM ---- EDIT THESE VALUES ----
set "REPO_URL=https://github.com/nkosinathil/comparison.git"
set "DEPLOY_REF=cursor/continue-migration-85c4"
set "CLONE_DIR=/opt/comparison-deploy"

set "SSO_HOST=192.168.1.59"
set "APP_HOST=192.168.1.66"
set "PYTHON_HOST=192.168.1.90"

set "SSH_USER_SSO=deploy"
set "SSH_USER_APP=deploy"
set "SSH_USER_PY=deploy"

set "APP_BASE_URL=http://192.168.1.66"
set "KEYCLOAK_PUBLIC_URL=http://192.168.1.59:8080"
set "KEYCLOAK_REALM=forensic"
set "KEYCLOAK_CLIENT_ID=comparison-web-app"
set "KEYCLOAK_ADMIN_USER=admin"
set "KEYCLOAK_ADMIN_PASSWORD=admin123"

set "DB_NAME=comparison_app"
set "DB_USER=comparison_user"
set "DB_PASSWORD=5ucc3SS!@#s"

set "MINIO_MANAGED=true"
set "MINIO_ACCESS_KEY=minioadmin"
set "MINIO_SECRET_KEY=n80FuR61Xah4wD6aEe3Dar8G2xIOsJUy"

set "API_KEY=b73906ec5f8222caeb548f8bedf03ea1bccfe96e21baa370"

set "REDIS_DB_BROKER=8"
set "REDIS_DB_RESULT=9"
set "REDIS_DB_CACHE=10"

REM ---- DO NOT EDIT BELOW THIS LINE ----
set "SSH_OPTS=-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15"

echo.
echo =========================================================
echo   File Comparison — Multi-Server Deployment (Windows)
echo   App:    %APP_HOST%
echo   Python: %PYTHON_HOST%
echo   SSO:    %SSO_HOST%
echo =========================================================
echo.

echo [PHASE 0/5] SSH pre-checks...
ssh %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "echo ok"
if errorlevel 1 (
  echo ERROR: SSH pre-check failed for App Server
  exit /b 1
)
ssh %SSH_OPTS% %SSH_USER_PY%@%PYTHON_HOST% "echo ok"
if errorlevel 1 (
  echo ERROR: SSH pre-check failed for Python Server
  exit /b 1
)
ssh %SSH_OPTS% %SSH_USER_SSO%@%SSO_HOST% "echo ok"
if errorlevel 1 (
  echo ERROR: SSH pre-check failed for SSO Server
  exit /b 1
)
echo   SSH pre-checks passed.

echo.
echo [PHASE 1/5] App Server — clone repo + Keycloak setup + app setup
echo.
ssh %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "sudo apt-get update -qq && sudo apt-get install -y -qq git curl jq > /dev/null 2>&1; if [ -d '%CLONE_DIR%/.git' ]; then cd '%CLONE_DIR%' && git fetch origin && (git checkout '%DEPLOY_REF%' 2>/dev/null || git checkout 'origin/%DEPLOY_REF%' 2>/dev/null) && git pull origin '%DEPLOY_REF%' 2>/dev/null || true; else sudo mkdir -p '%CLONE_DIR%' && sudo chown %SSH_USER_APP%:%SSH_USER_APP% '%CLONE_DIR%' && (git clone --branch '%DEPLOY_REF%' --single-branch '%REPO_URL%' '%CLONE_DIR%' 2>/dev/null || (git clone '%REPO_URL%' '%CLONE_DIR%' && cd '%CLONE_DIR%' && git checkout '%DEPLOY_REF%')); fi"
if errorlevel 1 (
  echo ERROR: Failed to clone/update repo on App Server
  exit /b 1
)

ssh %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "cat > %CLONE_DIR%/deploy/scripts/deploy.conf << 'DEPLOYEOF'^
PROJECT_NAME='comparison'^
REPO_URL='%REPO_URL%'^
DEPLOY_REF='%DEPLOY_REF%'^
REPO_ROOT=''^
SSO_HOST='%SSO_HOST%'^
APP_HOST='%APP_HOST%'^
PYTHON_HOST='%PYTHON_HOST%'^
SSH_USER_SSO='%SSH_USER_SSO%'^
SSH_USER_APP='%SSH_USER_APP%'^
SSH_USER_PY='%SSH_USER_PY%'^
APP_BASE_URL='%APP_BASE_URL%'^
KEYCLOAK_PUBLIC_URL='%KEYCLOAK_PUBLIC_URL%'^
KEYCLOAK_REALM='%KEYCLOAK_REALM%'^
KEYCLOAK_CLIENT_ID='%KEYCLOAK_CLIENT_ID%'^
KEYCLOAK_ADMIN_USER='%KEYCLOAK_ADMIN_USER%'^
KEYCLOAK_ADMIN_PASSWORD='%KEYCLOAK_ADMIN_PASSWORD%'^
KEYCLOAK_CLIENT_SECRET=''^
KEYCLOAK_CREATE_REALM='false'^
DB_NAME='%DB_NAME%'^
DB_USER='%DB_USER%'^
DB_PASSWORD='%DB_PASSWORD%'^
REDIS_DB_BROKER='%REDIS_DB_BROKER%'^
REDIS_DB_RESULT='%REDIS_DB_RESULT%'^
REDIS_DB_CACHE='%REDIS_DB_CACHE%'^
MINIO_MANAGED='%MINIO_MANAGED%'^
MINIO_ACCESS_KEY='%MINIO_ACCESS_KEY%'^
MINIO_SECRET_KEY='%MINIO_SECRET_KEY%'^
MINIO_DATA_DIR='/data/comparison-minio'^
MINIO_SERVICE_NAME='comparison-minio'^
API_KEY='%API_KEY%'^
APP_DEPLOY_DIR='/var/www/gismartanalytics'^
PY_DEPLOY_DIR='/opt/comparison'^
PY_VENV_DIR='/opt/comparison/venv'^
PY_LOG_DIR='/var/log/comparison-backend'^
PY_SERVICE_USER='comparison'^
PY_SERVICE_GROUP='comparison'^
PHP_VERSION=''^
FASTAPI_PORT='8000'^
REDIS_PORT='6379'^
MINIO_PORT='9000'^
MINIO_CONSOLE_PORT='9001'^
PG_PORT='5432'^
DEPLOYEOF"
if errorlevel 1 (
  echo ERROR: Failed writing deploy.conf on App Server
  exit /b 1
)

echo.
echo   Running setup-keycloak.sh on App Server...
ssh -tt %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "cd %CLONE_DIR%/deploy/scripts && bash setup-keycloak.sh"
if errorlevel 1 (
  echo ERROR: setup-keycloak.sh failed
  exit /b 1
)

echo.
echo   Running setup-app-server.sh on App Server...
ssh -tt %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "cd %CLONE_DIR%/deploy/scripts && sudo bash setup-app-server.sh"
if errorlevel 1 (
  echo ERROR: setup-app-server.sh failed
  exit /b 1
)

echo.
echo [PHASE 2/5] Python Server — clone repo + setup
echo.
ssh %SSH_OPTS% %SSH_USER_PY%@%PYTHON_HOST% "sudo apt-get update -qq && sudo apt-get install -y -qq git > /dev/null 2>&1; if [ -d '%CLONE_DIR%/.git' ]; then cd '%CLONE_DIR%' && git fetch origin && (git checkout '%DEPLOY_REF%' 2>/dev/null || git checkout 'origin/%DEPLOY_REF%' 2>/dev/null) && git pull origin '%DEPLOY_REF%' 2>/dev/null || true; else sudo mkdir -p '%CLONE_DIR%' && sudo chown %SSH_USER_PY%:%SSH_USER_PY% '%CLONE_DIR%' && (git clone --branch '%DEPLOY_REF%' --single-branch '%REPO_URL%' '%CLONE_DIR%' 2>/dev/null || (git clone '%REPO_URL%' '%CLONE_DIR%' && cd '%CLONE_DIR%' && git checkout '%DEPLOY_REF%')); fi"
if errorlevel 1 (
  echo ERROR: Failed to clone/update repo on Python Server
  exit /b 1
)

ssh %SSH_OPTS% %SSH_USER_PY%@%PYTHON_HOST% "cat > %CLONE_DIR%/deploy/scripts/deploy.conf << 'DEPLOYEOF'^
PROJECT_NAME='comparison'^
REPO_URL='%REPO_URL%'^
DEPLOY_REF='%DEPLOY_REF%'^
REPO_ROOT=''^
SSO_HOST='%SSO_HOST%'^
APP_HOST='%APP_HOST%'^
PYTHON_HOST='%PYTHON_HOST%'^
SSH_USER_SSO='%SSH_USER_SSO%'^
SSH_USER_APP='%SSH_USER_APP%'^
SSH_USER_PY='%SSH_USER_PY%'^
APP_BASE_URL='%APP_BASE_URL%'^
KEYCLOAK_PUBLIC_URL='%KEYCLOAK_PUBLIC_URL%'^
KEYCLOAK_REALM='%KEYCLOAK_REALM%'^
KEYCLOAK_CLIENT_ID='%KEYCLOAK_CLIENT_ID%'^
KEYCLOAK_ADMIN_USER='%KEYCLOAK_ADMIN_USER%'^
KEYCLOAK_ADMIN_PASSWORD='%KEYCLOAK_ADMIN_PASSWORD%'^
KEYCLOAK_CLIENT_SECRET=''^
KEYCLOAK_CREATE_REALM='false'^
DB_NAME='%DB_NAME%'^
DB_USER='%DB_USER%'^
DB_PASSWORD='%DB_PASSWORD%'^
REDIS_DB_BROKER='%REDIS_DB_BROKER%'^
REDIS_DB_RESULT='%REDIS_DB_RESULT%'^
REDIS_DB_CACHE='%REDIS_DB_CACHE%'^
MINIO_MANAGED='%MINIO_MANAGED%'^
MINIO_ACCESS_KEY='%MINIO_ACCESS_KEY%'^
MINIO_SECRET_KEY='%MINIO_SECRET_KEY%'^
MINIO_DATA_DIR='/data/comparison-minio'^
MINIO_SERVICE_NAME='comparison-minio'^
API_KEY='%API_KEY%'^
APP_DEPLOY_DIR='/var/www/gismartanalytics'^
PY_DEPLOY_DIR='/opt/comparison'^
PY_VENV_DIR='/opt/comparison/venv'^
PY_LOG_DIR='/var/log/comparison-backend'^
PY_SERVICE_USER='comparison'^
PY_SERVICE_GROUP='comparison'^
PHP_VERSION=''^
FASTAPI_PORT='8000'^
REDIS_PORT='6379'^
MINIO_PORT='9000'^
MINIO_CONSOLE_PORT='9001'^
PG_PORT='5432'^
DEPLOYEOF"
if errorlevel 1 (
  echo ERROR: Failed writing deploy.conf on Python Server
  exit /b 1
)

echo.
echo   Running setup-python-server.sh on Python Server...
ssh -tt %SSH_OPTS% %SSH_USER_PY%@%PYTHON_HOST% "cd %CLONE_DIR%/deploy/scripts && sudo bash setup-python-server.sh"
if errorlevel 1 (
  echo ERROR: setup-python-server.sh failed
  exit /b 1
)

echo.
echo [PHASE 3/5] Validation — running from App Server
echo.
ssh %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "cd %CLONE_DIR%/deploy/scripts && bash validate.sh"
if errorlevel 1 (
  echo ERROR: Validation failed
  exit /b 1
)

echo.
echo [PHASE 4/5] Post-deploy checks
echo   - Open %APP_BASE_URL%
echo   - Verify service status on servers with systemctl status
echo.
echo [PHASE 5/5] Done
echo =========================================================
echo   Deployment complete.
echo   Open %APP_BASE_URL% in your browser to test.
echo =========================================================
echo.
echo SECURITY: Rotate DB, Keycloak admin, API key, and MinIO secrets after deployment.

endlocal
