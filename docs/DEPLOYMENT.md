# Deployment Guide

Step-by-step instructions for deploying the File Comparison Web Application across three servers.

---

## Prerequisites

| Server | IP | Required Software |
|--------|----|-------------------|
| SSO | 192.168.1.59 | Keycloak (existing) |
| App | 192.168.1.66 | Apache 2.4+, PHP 8.1+ (php-fpm, php-pgsql, php-curl, php-mbstring), PostgreSQL 12+, Composer |
| Python | 192.168.1.90 | Python 3.9+, Redis 6+, MinIO, Nginx (optional), Tesseract OCR (optional) |

---

## 1. Database Setup (App Server — 192.168.1.66)

```bash
# Create database and user
sudo -u postgres psql <<SQL
CREATE DATABASE comparison_app;
CREATE USER comparison_user WITH ENCRYPTED PASSWORD 'CHANGE_ME';
GRANT ALL PRIVILEGES ON DATABASE comparison_app TO comparison_user;
\c comparison_app
GRANT ALL ON SCHEMA public TO comparison_user;
SQL

# Load schema
sudo -u postgres psql -d comparison_app -f /path/to/database/schema.sql
```

---

## 2. PHP Application (App Server — 192.168.1.66)

```bash
# Clone repository
sudo mkdir -p /var/www/gismartanalytics
sudo cp -r php-app/* /var/www/gismartanalytics/
sudo cp unified_compare_app.py /var/www/gismartanalytics/

# Install PHP dependencies
cd /var/www/gismartanalytics
sudo composer install --no-dev --optimize-autoloader

# Configure environment
sudo cp .env.example .env
sudo nano .env   # Fill in database, Keycloak, Python API settings

# Create storage directories
sudo mkdir -p storage/logs storage/cache
sudo chown -R www-data:www-data /var/www/gismartanalytics

# Install Apache vhost
sudo cp deploy/apache/comparison-app.conf /etc/apache2/sites-available/
sudo a2ensite comparison-app
sudo a2enmod rewrite headers proxy_fcgi
sudo systemctl restart apache2
```

---

## 3. Python Backend (Python Server — 192.168.1.90)

```bash
# Create application user
sudo useradd -r -s /bin/false comparison
sudo mkdir -p /opt/comparison

# Copy code
sudo cp -r python-backend /opt/comparison/
sudo cp unified_compare_app.py /opt/comparison/

# Create virtual environment
cd /opt/comparison
sudo python3 -m venv venv
sudo /opt/comparison/venv/bin/pip install -r python-backend/requirements.txt

# Configure environment
sudo cp python-backend/.env.example python-backend/.env
sudo nano python-backend/.env   # Fill in Redis, MinIO, Ollama settings

# Create log directory
sudo mkdir -p /var/log/comparison-backend
sudo chown comparison:comparison /var/log/comparison-backend

# Install systemd services
sudo cp deploy/systemd/comparison-api.service /etc/systemd/system/
sudo cp deploy/systemd/comparison-worker.service /etc/systemd/system/
sudo cp deploy/systemd/comparison-beat.service /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable comparison-api comparison-worker comparison-beat
sudo systemctl start comparison-api comparison-worker comparison-beat

# (Optional) Install Nginx reverse proxy
sudo cp deploy/nginx/python-api.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/python-api.conf /etc/nginx/sites-enabled/
sudo systemctl restart nginx
```

---

## 4. MinIO Setup (Python Server)

```bash
# Ensure MinIO is running, then create buckets
mc alias set local http://localhost:9000 MINIO_ACCESS_KEY MINIO_SECRET_KEY
mc mb local/uploads
mc mb local/results
mc mb local/cache
```

---

## 5. Keycloak Configuration (SSO Server — 192.168.1.59)

In your Keycloak admin console:

1. Create (or use existing) realm
2. Create a client:
   - **Client ID**: `comparison-web-app`
   - **Client Protocol**: `openid-connect`
   - **Access Type**: `confidential`
   - **Valid Redirect URIs**: `http://192.168.1.66/auth/callback`
   - **Post Logout Redirect URIs**: `http://192.168.1.66`
3. Copy the **Client Secret** to the PHP `.env` file
4. Create roles: `admin`, `analyst`, `viewer`
5. Assign roles to users

---

## 6. Verification

```bash
# Check Python API health
curl http://192.168.1.90:8000/health

# Check PHP app (should redirect to Keycloak login)
curl -I http://192.168.1.66/

# Check systemd services
sudo systemctl status comparison-api comparison-worker comparison-beat
```

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| PHP 500 errors | `tail /var/log/apache2/comparison-error.log` |
| Python API down | `sudo journalctl -u comparison-api -f` |
| Celery not processing | `sudo journalctl -u comparison-worker -f` |
| Upload failures | MinIO connectivity, bucket existence |
| Auth redirect loop | Keycloak client config, redirect URIs |
| Database errors | PostgreSQL logs, `psql` connectivity test |
