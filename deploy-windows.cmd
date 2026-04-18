@echo off
setlocal DisableDelayedExpansion
REM =============================================================================
REM deploy-windows.cmd — Windows CMD deployment driver
REM =============================================================================

REM ---- EDIT THESE VALUES ----
set "REPO_URL=__SET_ME__"
set "DEPLOY_REF=__SET_ME__"
set "CLONE_DIR=/opt/comparison-deploy"

set "SSO_HOST=__SET_ME__"
set "APP_HOST=__SET_ME__"
set "PYTHON_HOST=__SET_ME__"

set "SSH_USER_SSO=deploy"
set "SSH_USER_APP=deploy"
set "SSH_USER_PY=deploy"

set "APP_BASE_URL=__SET_ME__"
set "KEYCLOAK_PUBLIC_URL=__SET_ME__"
set "KEYCLOAK_REALM=forensic"
set "KEYCLOAK_CLIENT_ID=comparison-web-app"
set "KEYCLOAK_ADMIN_USER=admin"
set "KEYCLOAK_ADMIN_PASSWORD=__SET_ME__"

set "DB_NAME=comparison_app"
set "DB_USER=comparison_user"
set "DB_PASSWORD=__SET_ME__"

set "MINIO_MANAGED=true"
set "MINIO_ACCESS_KEY=__SET_ME__"
set "MINIO_SECRET_KEY=__SET_ME__"

set "API_KEY=__SET_ME__"

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

if "%KEYCLOAK_ADMIN_PASSWORD%"=="__SET_ME__" (
  echo ERROR: Set KEYCLOAK_ADMIN_PASSWORD before running.
  exit /b 1
)
if "%REPO_URL%"=="__SET_ME__" (
  echo ERROR: Set REPO_URL before running.
  exit /b 1
)
if "%DEPLOY_REF%"=="__SET_ME__" (
  echo ERROR: Set DEPLOY_REF before running.
  exit /b 1
)
if "%APP_HOST%"=="__SET_ME__" (
  echo ERROR: Set APP_HOST before running.
  exit /b 1
)
if "%PYTHON_HOST%"=="__SET_ME__" (
  echo ERROR: Set PYTHON_HOST before running.
  exit /b 1
)
if "%SSO_HOST%"=="__SET_ME__" (
  echo ERROR: Set SSO_HOST before running.
  exit /b 1
)
if "%APP_BASE_URL%"=="__SET_ME__" (
  echo ERROR: Set APP_BASE_URL before running.
  exit /b 1
)
if "%KEYCLOAK_PUBLIC_URL%"=="__SET_ME__" (
  echo ERROR: Set KEYCLOAK_PUBLIC_URL before running.
  exit /b 1
)
if "%DB_PASSWORD%"=="__SET_ME__" (
  echo ERROR: Set DB_PASSWORD before running.
  exit /b 1
)
if "%MINIO_SECRET_KEY%"=="__SET_ME__" (
  echo ERROR: Set MINIO_SECRET_KEY before running.
  exit /b 1
)
if "%MINIO_ACCESS_KEY%"=="__SET_ME__" (
  echo ERROR: Set MINIO_ACCESS_KEY before running.
  exit /b 1
)
if "%API_KEY%"=="__SET_ME__" (
  echo ERROR: Set API_KEY before running.
  exit /b 1
)

set "LOCAL_DEPLOY_CONF=%TEMP%\comparison-deploy.conf"
> "%LOCAL_DEPLOY_CONF%" (
  echo PROJECT_NAME='comparison'
  echo REPO_URL='%REPO_URL%'
  echo DEPLOY_REF='%DEPLOY_REF%'
  echo REPO_ROOT=''
  echo SSO_HOST='%SSO_HOST%'
  echo APP_HOST='%APP_HOST%'
  echo PYTHON_HOST='%PYTHON_HOST%'
  echo SSH_USER_SSO='%SSH_USER_SSO%'
  echo SSH_USER_APP='%SSH_USER_APP%'
  echo SSH_USER_PY='%SSH_USER_PY%'
  echo APP_BASE_URL='%APP_BASE_URL%'
  echo KEYCLOAK_PUBLIC_URL='%KEYCLOAK_PUBLIC_URL%'
  echo KEYCLOAK_REALM='%KEYCLOAK_REALM%'
  echo KEYCLOAK_CLIENT_ID='%KEYCLOAK_CLIENT_ID%'
  echo KEYCLOAK_ADMIN_USER='%KEYCLOAK_ADMIN_USER%'
  echo KEYCLOAK_ADMIN_PASSWORD='%KEYCLOAK_ADMIN_PASSWORD%'
  echo KEYCLOAK_CLIENT_SECRET=''
  echo KEYCLOAK_CREATE_REALM='false'
  echo DB_NAME='%DB_NAME%'
  echo DB_USER='%DB_USER%'
  echo DB_PASSWORD='%DB_PASSWORD%'
  echo REDIS_DB_BROKER='%REDIS_DB_BROKER%'
  echo REDIS_DB_RESULT='%REDIS_DB_RESULT%'
  echo REDIS_DB_CACHE='%REDIS_DB_CACHE%'
  echo MINIO_MANAGED='%MINIO_MANAGED%'
  echo MINIO_ACCESS_KEY='%MINIO_ACCESS_KEY%'
  echo MINIO_SECRET_KEY='%MINIO_SECRET_KEY%'
  echo MINIO_DATA_DIR='/data/comparison-minio'
  echo MINIO_SERVICE_NAME='comparison-minio'
  echo API_KEY='%API_KEY%'
  echo APP_DEPLOY_DIR='/var/www/gismartanalytics'
  echo PY_DEPLOY_DIR='/opt/comparison'
  echo PY_VENV_DIR='/opt/comparison/venv'
  echo PY_LOG_DIR='/var/log/comparison-backend'
  echo PY_SERVICE_USER='comparison'
  echo PY_SERVICE_GROUP='comparison'
  echo PHP_VERSION=''
  echo FASTAPI_PORT='8000'
  echo REDIS_PORT='6379'
  echo MINIO_PORT='9000'
  echo MINIO_CONSOLE_PORT='9001'
  echo PG_PORT='5432'
)
if errorlevel 1 (
  echo ERROR: Failed creating local deploy.conf template at %LOCAL_DEPLOY_CONF%
  exit /b 1
)

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

type "%LOCAL_DEPLOY_CONF%" | ssh %SSH_OPTS% %SSH_USER_APP%@%APP_HOST% "cat > %CLONE_DIR%/deploy/scripts/deploy.conf"
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

type "%LOCAL_DEPLOY_CONF%" | ssh %SSH_OPTS% %SSH_USER_PY%@%PYTHON_HOST% "cat > %CLONE_DIR%/deploy/scripts/deploy.conf"
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
del "%LOCAL_DEPLOY_CONF%" >nul 2>&1
if exist "%LOCAL_DEPLOY_CONF%" (
  echo WARNING: Failed to delete temporary file %LOCAL_DEPLOY_CONF%
)

endlocal
