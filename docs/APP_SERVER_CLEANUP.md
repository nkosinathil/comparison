# App Server Cleanup Guide

This document describes exactly what `deploy/scripts/cleanup-app-server.sh` removes and what it leaves untouched.

## When to use it

Run the cleanup script before a **fresh first deployment** when you need to remove an existing installation of this app and start from a clean slate.

**Do not run this script if you want to update an existing deployment** — use `deploy-all.sh` or `setup-app-server.sh` directly instead (they are idempotent).

---

## Running the script

On the app server (192.168.1.66):

```bash
# From inside the repo clone:
sudo bash deploy/scripts/cleanup-app-server.sh

# Or remotely from your workstation:
ssh deploy@192.168.1.66 "sudo bash /opt/comparison-deploy/deploy/scripts/cleanup-app-server.sh"
```

The script reads `APP_DEPLOY_DIR` from `deploy.conf` and refuses to run if it points to a protected system path.

---

## What the cleanup script REMOVES

| Item | Path / Scope |
|------|-------------|
| PHP app deployment directory | `/var/www/file.gismartanalytics/` (entire directory tree) |
| Apache vhost config for this app | `/etc/apache2/sites-available/comparison-app.conf` |
| Apache vhost symlink (if enabled) | `/etc/apache2/sites-enabled/comparison-app.conf` |
| App-specific upload temp files | `/tmp/comparison_uploads/` |
| App-specific Apache log files | `/var/log/apache2/comparison-error.log`, `comparison-access.log` |

After removal, Apache is gracefully reloaded so the vhost disappears cleanly.

---

## What the cleanup script does NOT remove

| Item | Reason |
|------|--------|
| Other Apache vhosts | Only this app's `comparison-app.conf` is removed |
| Other apps in `/var/www/` | Only `APP_DEPLOY_DIR` is deleted |
| PostgreSQL service | Not touched |
| `comparison_app` database | Not dropped — must be dropped manually if needed |
| `comparison_user` DB user | Not dropped — must be removed manually if needed |
| PostgreSQL `pg_hba.conf` entries | Entries added by `setup-app-server.sh` remain; remove manually if needed |
| Shared Apache config (`/etc/apache2/`) | Only the vhost file is removed |
| PHP-FPM service | Not touched |
| Any other running services | Not touched |
| SSH keys or user accounts | Not touched |
| `deploy.conf` | Not touched |
| The repo clone at `/opt/comparison-deploy/` | Not touched |

---

## Manually cleaning the database (if needed)

If you also want to remove the PostgreSQL database and user:

```bash
sudo -u postgres psql <<'SQL'
DROP DATABASE IF EXISTS comparison_app;
DROP ROLE IF EXISTS comparison_user;
SQL
```

Remove the app's `pg_hba.conf` entries (lines marked `# comparison-deploy`) and reload:

```bash
sudo nano $(sudo -u postgres psql -t -c "SHOW hba_file;" | xargs)
# Delete lines between "# comparison-deploy" markers
sudo systemctl reload postgresql
```

---

## Safety checks

The script includes the following safety guards:

- Refuses to delete if `APP_DEPLOY_DIR` is `/`, `/var/www`, `/etc`, `/opt`, or `/usr`.
- Refuses to delete if the target directory does not look like this PHP app (no `composer.json` or `public/`).
- Only removes files it explicitly lists — does not do wildcard deletion of system directories.
- Reports each action with `[INFO]` logs so you can see exactly what happened.
