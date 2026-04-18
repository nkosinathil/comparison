# Troubleshooting Playbook

## 1. Keycloak / Authentication Errors

### `invalid_grant`
**Cause:** Auth code expired, already used, or clock skew between servers.
```bash
# Check clock sync
date                        # on app server
ssh deploy@192.168.1.59 date  # on SSO server
# Fix: install NTP
sudo apt-get install -y chrony && sudo systemctl enable chrony
```

### `invalid_request` / `invalid_redirect_uri`
**Cause:** `KEYCLOAK_REDIRECT_URI` in PHP `.env` doesn't exactly match what's configured in Keycloak client.
```bash
# Check PHP .env
grep KEYCLOAK_REDIRECT_URI /var/www/gismartanalytics/.env
# Must be exactly: http://<APP_BASE_URL>/auth/callback
# Check Keycloak: Admin Console -> Clients -> comparison-web-app -> Valid Redirect URIs
```

### `code_challenge_method missing` / PKCE errors
**Cause:** Keycloak enforces PKCE (S256) but client doesn't send `code_challenge`.
**Fix:** The current app uses Authorization Code flow (confidential client). If Keycloak requires PKCE:
1. Go to Keycloak Admin -> Clients -> comparison-web-app -> Advanced
2. Set "PKCE Code Challenge Method" to "S256" or "optional"
3. The `setup-keycloak.sh` script sets `pkce.code.challenge.method: S256` in attributes

### Login redirect loop
**Cause:** Session cookie not persisting, or `KEYCLOAK_REDIRECT_URI` mismatch.
```bash
# Check Apache error log
tail -50 /var/log/apache2/comparison-error.log
# Check session table
sudo -u postgres psql -d comparison_app -c "SELECT COUNT(*) FROM sessions;"
# Verify SESSION_DRIVER=database in .env
grep SESSION_DRIVER /var/www/gismartanalytics/.env
```

---

## 2. PHP Errors

### Class not found / autoload failure
```bash
cd /var/www/gismartanalytics
# Ensure vendor/ exists
ls vendor/autoload.php
# Regenerate autoloader
sudo -u www-data composer dump-autoload --optimize
# Check PSR-4 mapping
grep -r '"App\\\\": "src/"' composer.json
```

### 500 Internal Server Error (blank page)
```bash
# Check Apache error log
tail -50 /var/log/apache2/comparison-error.log
# Check PHP-FPM log
sudo journalctl -u php8.1-fpm -n 50
# Enable debug temporarily
sudo sed -i 's/APP_DEBUG="false"/APP_DEBUG="true"/' /var/www/gismartanalytics/.env
sudo systemctl restart apache2
# IMPORTANT: disable debug after investigating
```

### Composer install fails
```bash
# Check PHP version
php -v  # Must be 8.1+
# Check required extensions
php -m | grep -E 'pgsql|curl|mbstring|xml|zip'
# Install missing
sudo apt-get install -y php8.1-pgsql php8.1-curl php8.1-mbstring php8.1-xml php8.1-zip
```

---

## 3. Python Backend Errors

### Module not found (`app.tasks.celery_app`, `unified_compare_app`)
```bash
# Check working directory in systemd unit
grep WorkingDirectory /etc/systemd/system/comparison-worker.service
# Must be: /opt/comparison/python-backend

# Check unified_compare_app.py is accessible
ls /opt/comparison/unified_compare_app.py

# Test import manually
cd /opt/comparison/python-backend
sudo -u comparison /opt/comparison/venv/bin/python -c "from app.tasks.celery_app import celery_app; print('OK')"
```

### FastAPI won't start / bind error
```bash
# Check if port is in use
sudo ss -tlnp | grep 8000
# Check service logs
sudo journalctl -u comparison-api -n 50 --no-pager
# Common fix: kill orphan process
sudo fuser -k 8000/tcp
sudo systemctl restart comparison-api
```

### Celery worker not processing tasks
```bash
# Check worker status
sudo journalctl -u comparison-worker -n 50 --no-pager
# Check Redis connectivity
redis-cli -h localhost -p 6379 PING
# Check Celery can discover tasks
cd /opt/comparison/python-backend
sudo -u comparison /opt/comparison/venv/bin/celery -A app.tasks.celery_app inspect ping
```

---

## 4. Database Errors

### `FATAL: password authentication failed`
```bash
# Check pg_hba.conf has entry for the app user
sudo grep comparison /etc/postgresql/*/main/pg_hba.conf
# Reset password
sudo -u postgres psql -c "ALTER ROLE comparison_user WITH PASSWORD 'new_password';"
# Update .env
sudo nano /var/www/gismartanalytics/.env  # DB_PASSWORD
```

### `FATAL: no pg_hba.conf entry for host`
```bash
# Add entry for the connecting host
PG_HBA=$(sudo -u postgres psql -t -c "SHOW hba_file;" | xargs)
echo "host  comparison_app  comparison_user  <IP>/32  scram-sha-256" | sudo tee -a "$PG_HBA"
sudo systemctl reload postgresql
```

### Connection refused from Python server
```bash
# Check listen_addresses
sudo -u postgres psql -c "SHOW listen_addresses;"
# Must be '*' or include the App server IP
# Check firewall
sudo ufw status | grep 5432
```

---

## 5. MinIO Errors

### Bucket not found
```bash
# Create buckets manually
mc alias set local http://localhost:9000 minioadmin <MINIO_SECRET_KEY>
mc mb --ignore-existing local/uploads
mc mb --ignore-existing local/results
mc mb --ignore-existing local/cache
mc ls local/
```

### Permission denied
```bash
# Check MinIO data directory ownership
ls -la /data/minio
# Fix
sudo chown -R comparison:comparison /data/minio
sudo systemctl restart minio
```

---

## 6. Service Permission / SystemD Errors

### `Permission denied` in service logs
```bash
# Check user exists
id comparison
# Check directory ownership
ls -la /opt/comparison
ls -la /var/log/comparison-backend
# Fix
sudo chown -R comparison:comparison /opt/comparison /var/log/comparison-backend
```

### Service fails to start after reboot
```bash
# Check service is enabled
sudo systemctl is-enabled comparison-api comparison-worker comparison-beat minio redis-server
# Re-enable
sudo systemctl enable comparison-api comparison-worker comparison-beat minio redis-server
# Check dependency order
sudo systemctl cat comparison-api | grep -E 'After|Wants'
```
