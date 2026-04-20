# Fresh Deployment Guide — file.gismartanalytics.com

This document describes how to deploy the application from scratch on a clean app server.

## Architecture

| Role | Server | IP |
|------|--------|----|
| Keycloak SSO | SSO server | 192.168.1.59 |
| PHP app | App server | 192.168.1.66 |
| Python backend | Python server | 192.168.1.90 |

- **Realm:** forensics  
- **Client:** file.gismartanalytics.com  
- **App URL:** http://file.gismartanalytics.com (LAN/HTTP during initial testing)

---

## Prerequisites

Before deploying:

1. **Keycloak** is already running on 192.168.1.59:8080 with the `forensics` realm.
2. **SSH key-based access** is configured for your deploy user on all three servers.  
   Run `./setup-ssh-keys.sh <user>@<host>` if not yet set up.
3. **A filled `deploy.conf`** exists at the repo root (NOT committed — see `docs/SECRETS_AND_ENV.md`).

---

## Step 1: Prepare deploy.conf

```bash
# From the repo root on your workstation:
cp deploy.conf.example deploy.conf
nano deploy.conf   # fill in all __CHANGE_ME__ values
```

Required values to fill in:

| Variable | Description |
|----------|-------------|
| `DEPLOY_REF` | Git branch or tag to deploy (e.g. `copilot/update-deploy-windows-cmd`) |
| `SSH_USER_SSO` | SSH user on SSO server |
| `SSH_USER_APP` | SSH user on app server |
| `SSH_USER_PY` | SSH user on Python server |
| `KEYCLOAK_ADMIN_USER` | Keycloak admin username |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password |
| `DB_PASSWORD` | PostgreSQL password for `comparison_user` |
| `MINIO_ACCESS_KEY` | MinIO access key |
| `MINIO_SECRET_KEY` | MinIO secret key |
| `API_KEY` | Shared PHP↔Python API key (generate with `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`) |

---

## Step 2: Run preflight checks

```bash
bash deploy/scripts/preflight.sh
```

This verifies SSH connectivity, required env vars, callback alignment, and branch targeting. Fix any errors before proceeding.

---

## Step 3: Clean the app server (first deploy only)

If there is an existing deployment of this app that you want to remove cleanly:

```bash
# On the app server (192.168.1.66):
sudo bash /opt/comparison-deploy/deploy/scripts/cleanup-app-server.sh
```

Or remotely:

```bash
ssh deploy@192.168.1.66 "sudo bash /opt/comparison-deploy/deploy/scripts/cleanup-app-server.sh"
```

See `docs/APP_SERVER_CLEANUP.md` for exactly what this removes and what it leaves untouched.

---

## Step 4: Deploy

### Linux/macOS (from workstation):

```bash
# Set required vars (or rely on deploy.conf):
export SSO_USER=deploy   APP_USER=deploy   PY_USER=deploy
export SSO_HOST=192.168.1.59  APP_HOST=192.168.1.66  PY_HOST=192.168.1.90
export REPO_URL=https://github.com/nkosinathil/comparison.git
export DEPLOY_REF=copilot/update-deploy-windows-cmd

bash deploy-all.sh
```

### Windows (from workstation):

1. Edit `deploy-windows.cmd` and fill in all `__SET_ME__` values.
2. Run in Command Prompt:
   ```
   deploy-windows.cmd
   ```

---

## Step 5: Verify

After deployment completes:

1. Open `http://file.gismartanalytics.com` in a browser.
2. You should be redirected to the Keycloak login page.
3. Log in with a user from the `forensics` realm.
4. You should be redirected back to `http://file.gismartanalytics.com/auth/callback` and then to the dashboard.

---

## Step 6: Post-deploy security tasks (manual)

These must be done manually after the first successful deployment:

- [ ] Rotate `DB_PASSWORD` and update the database user password accordingly.
- [ ] Rotate `API_KEY` across PHP and Python `.env` files.
- [ ] Rotate `MINIO_ACCESS_KEY` and `MINIO_SECRET_KEY`.
- [ ] Rotate `KEYCLOAK_ADMIN_PASSWORD` after confirming the client secret is saved.
- [ ] Restrict Keycloak admin account access.
- [ ] Enable HTTPS and update `KEYCLOAK_REDIRECT_URI` and `APP_BASE_URL` accordingly.
- [ ] Set `SESSION_COOKIE_SECURE=true` after HTTPS is live.
- [ ] Set `KEYCLOAK_TLS_VERIFY=true` (default) and verify Keycloak TLS cert is valid.

---

## Env files to fill before deployment

### PHP app: `/var/www/file.gismartanalytics/.env`

This is written automatically by `setup-app-server.sh` from `deploy.conf`. The template is at `php-app/.env.example`.

### Python backend: `/opt/comparison/.env`

This is written automatically by `setup-python-server.sh` from `deploy.conf`. The template is at `python-backend/.env.example`.

---

## Remaining manual blockers

- DNS entry for `file.gismartanalytics.com` must point to 192.168.1.66 (or be in local `/etc/hosts`).
- Keycloak `forensics` realm must exist before running `setup-keycloak.sh`.
- SSH key-based access must be configured for all three deploy users before running `deploy-all.sh`.
