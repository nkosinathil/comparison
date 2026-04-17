# Deployment Guide

## Overview

The deployment is automated via scripts in `deploy/scripts/`. All parameters are centralized in `deploy.conf` — nothing is hardcoded.

### Architecture

| Server | Role | Software |
|--------|------|----------|
| SSO (`SSO_HOST`) | Authentication | Keycloak |
| App (`APP_HOST`) | Web Frontend + Database | Apache, PHP 8.1+, PostgreSQL 12+ |
| Python (`PYTHON_HOST`) | Processing Engine | FastAPI, Celery, Redis, MinIO |

---

## Quick Start

### 1. Configure

```bash
cd deploy/scripts
cp deploy.conf.example deploy.conf
# Edit deploy.conf — fill in all CHANGE_ME values
nano deploy.conf
```

### 2. Deploy (from operator workstation with SSH access)

**Linux / macOS:**
```bash
bash deploy/scripts/deploy-all.sh
```

**Windows CMD (via SSH to a jump box, or with Git Bash):**
```cmd
bash deploy/scripts/deploy-all.sh
```

**Or, run on each server directly:**
```bash
# On SSO server (or any machine with curl + jq):
bash deploy/scripts/deploy-all.sh --local-only keycloak

# On App server (as root):
sudo bash deploy/scripts/setup-app-server.sh

# On Python server (as root):
sudo bash deploy/scripts/setup-python-server.sh
```

### 3. Validate

```bash
bash deploy/scripts/validate.sh
```

---

## Detailed Step-by-Step

### Prerequisites

| Server | Required |
|--------|----------|
| SSO | Keycloak running, admin credentials available |
| App | Ubuntu/Debian, SSH access, root/sudo |
| Python | Ubuntu/Debian, SSH access, root/sudo |
| Operator | SSH keys configured for all servers, `curl`, `jq` installed |

### Step 1: Prepare deploy.conf

Copy `deploy/scripts/deploy.conf.example` to `deploy/scripts/deploy.conf` and set:

| Variable | What to set |
|----------|-------------|
| `SSO_HOST`, `APP_HOST`, `PYTHON_HOST` | Server IPs or hostnames |
| `SSH_USER_*` | SSH username for each server |
| `APP_BASE_URL` | Public URL of the web app (e.g. `http://comparison.example.com`) |
| `KEYCLOAK_PUBLIC_URL` | Public Keycloak URL (e.g. `http://sso.example.com:8080`) |
| `DB_PASSWORD` | Strong PostgreSQL password |
| `MINIO_SECRET_KEY` | Strong MinIO password (min 8 chars) |
| `API_KEY` | Shared secret for PHP-Python auth |
| `KEYCLOAK_ADMIN_USER/PASSWORD` | Keycloak admin credentials |

Generate secrets:
```bash
python3 -c "import secrets; print(secrets.token_urlsafe(32))"  # API_KEY
python3 -c "import secrets; print(secrets.token_urlsafe(24))"  # DB_PASSWORD
python3 -c "import secrets; print(secrets.token_urlsafe(24))"  # MINIO_SECRET_KEY
```

### Step 2: Run Deployment

**Full automated deployment** (orchestrator SSHes to each server):
```bash
bash deploy/scripts/deploy-all.sh
```

This runs in order:
1. `setup-keycloak.sh` — creates realm, client, roles; saves client secret
2. `setup-app-server.sh` — installs packages, configures DB, deploys PHP, writes `.env`, configures Apache
3. `setup-python-server.sh` — installs packages, deploys Python, writes `.env`, installs systemd services, starts everything
4. `validate.sh` — runs all health checks

**Per-server deployment** (run directly on each server):
```bash
# Copy the entire repo + deploy.conf to the server, then:
sudo bash deploy/scripts/setup-app-server.sh     # on App server
sudo bash deploy/scripts/setup-python-server.sh   # on Python server
```

### Step 3: Validate

```bash
bash deploy/scripts/validate.sh
```

Expected output:
```
  PASS  App Server SSH (192.168.1.66:22)
  PASS  Python Server SSH (192.168.1.90:22)
  PASS  Keycloak realm (HTTP 200)
  PASS  PostgreSQL port (192.168.1.66:5432)
  PASS  FastAPI health (HTTP 200)
  PASS  MinIO health (HTTP 200)
  PASS  App base URL (HTTP 302)
  PASS  CSS asset (HTTP 200)
  PASS  Login redirects to Keycloak
  ...
  Results: N passed, 0 failed (N total)
  ALL CHECKS PASSED
```

---

## Rollback

Backups are created automatically before each deployment. To rollback:

```bash
# List available backups
sudo bash deploy/scripts/rollback.sh app
sudo bash deploy/scripts/rollback.sh python

# Rollback to a specific timestamp
sudo bash deploy/scripts/rollback.sh app 20260417_153000
sudo bash deploy/scripts/rollback.sh python 20260417_153000
```

---

## Execution Commands Reference

### Linux Bash

```bash
# Full deployment
bash deploy/scripts/deploy-all.sh

# Validate only
bash deploy/scripts/deploy-all.sh --validate-only

# Single server (on the server itself)
sudo bash deploy/scripts/setup-app-server.sh
sudo bash deploy/scripts/setup-python-server.sh

# Keycloak setup (from any machine with curl + jq)
bash deploy/scripts/setup-keycloak.sh

# Remote execution via SSH
ssh -tt deploy@192.168.1.66 "cd /path/to/repo && sudo bash deploy/scripts/setup-app-server.sh"
ssh -tt deploy@192.168.1.90 "cd /path/to/repo && sudo bash deploy/scripts/setup-python-server.sh"
```

### Windows CMD (with OpenSSH or PuTTY)

```cmd
REM Full deployment (from Git Bash or WSL)
bash deploy/scripts/deploy-all.sh

REM Remote execution via SSH
ssh -tt deploy@192.168.1.66 "cd /path/to/repo && sudo bash deploy/scripts/setup-app-server.sh"
ssh -tt deploy@192.168.1.90 "cd /path/to/repo && sudo bash deploy/scripts/setup-python-server.sh"

REM Validation
ssh deploy@192.168.1.66 "cd /path/to/repo && bash deploy/scripts/validate.sh"
```

---

## Post-Deployment

See:
- `docs/GO_LIVE_CHECKLIST.md` — security hardening, backup configuration, TLS setup
- `docs/TROUBLESHOOTING.md` — common failure resolution playbook
