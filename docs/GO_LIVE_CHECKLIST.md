# Go-Live Checklist

## Security

- [ ] **Rotate all temporary credentials**
  - [ ] `DB_PASSWORD` — change from deploy default
  - [ ] `MINIO_SECRET_KEY` — change from deploy default
  - [ ] `API_KEY` — regenerate: `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`
  - [ ] `KEYCLOAK_ADMIN_PASSWORD` — change in Keycloak admin console
  - [ ] Update all `.env` files on both servers after rotation

- [ ] **TLS / HTTPS**
  - [ ] Install SSL certificates on App Server (Let's Encrypt or enterprise CA)
  - [ ] Update Apache vhost to listen on 443 with SSL
  - [ ] Set `SESSION_COOKIE_SECURE=true` in PHP `.env`
  - [ ] Update `APP_BASE_URL` to `https://...` in deploy.conf and PHP `.env`
  - [ ] Update `KEYCLOAK_REDIRECT_URI` to use `https://`
  - [ ] Update Keycloak client redirect URIs to use `https://`
  - [ ] Consider TLS between App and Python servers (or use VPN/private network)

- [ ] **Firewall hardened**
  - [ ] Only required ports open (80/443 on App, FastAPI port from App only)
  - [ ] MinIO console (9001) not exposed externally
  - [ ] Redis (6379) not exposed externally
  - [ ] PostgreSQL (5432) only from App + Python hosts
  - [ ] Run `sudo ufw status verbose` on each server to verify

- [ ] **SSH hardened**
  - [ ] Key-only authentication (disable password auth)
  - [ ] Deploy user has minimal sudo permissions
  - [ ] Root login disabled over SSH

## Operational

- [ ] **Backups configured**
  - [ ] PostgreSQL: `pg_dump` cron job (daily)
    ```bash
    # /etc/cron.d/comparison-backup
    0 2 * * * postgres pg_dump comparison_app | gzip > /var/backups/pg/comparison_$(date +\%Y\%m\%d).sql.gz
    ```
  - [ ] MinIO: replicate or backup `/data/minio` directory
  - [ ] Test restore procedure: restore a backup to a test database

- [ ] **Monitoring & alerting**
  - [ ] Health endpoint polling: `http://<PYTHON_HOST>:8000/health`
  - [ ] Apache access/error log rotation configured (`logrotate`)
  - [ ] Python app log rotation configured (built into logging module)
  - [ ] Disk space monitoring on MinIO data volume
  - [ ] Service restart alerting (systemd `OnFailure=` or external monitor)

- [ ] **Log review**
  - [ ] Check Apache error log is clean: `tail /var/log/apache2/comparison-error.log`
  - [ ] Check Python API logs: `sudo journalctl -u comparison-api --since "1 hour ago"`
  - [ ] Check Celery worker logs: `sudo journalctl -u comparison-worker --since "1 hour ago"`
  - [ ] No stack traces or critical errors in any log

## Functional

- [ ] **End-to-end auth flow**
  - [ ] Open `APP_BASE_URL` in browser
  - [ ] Redirected to Keycloak login
  - [ ] Login with valid credentials
  - [ ] Redirected back to dashboard
  - [ ] Logout works (redirected to Keycloak logout then back to app)

- [ ] **File comparison workflow**
  - [ ] Upload a source file (drag-and-drop works)
  - [ ] Upload target files
  - [ ] Start comparison
  - [ ] Progress bar updates
  - [ ] Results page shows summary
  - [ ] CSV download works
  - [ ] HTML report download works

- [ ] **Validate script passes**
  ```bash
  bash deploy/scripts/validate.sh
  # Expected: ALL CHECKS PASSED
  ```

## Sign-off

| Check | Owner | Date | Status |
|-------|-------|------|--------|
| Security review | | | |
| Backup test | | | |
| Load test (optional) | | | |
| Stakeholder approval | | | |
