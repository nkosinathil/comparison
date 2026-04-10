# File Comparison Web Application

## Overview

This is a **three-server web-based file comparison system** converted from a Python Qt desktop application. The system compares files across multiple formats (emails, PDFs, Word, Excel, text, TIFF) using advanced similarity algorithms.

---

## 🏗️ Architecture

### Server Configuration

| Server | IP | Role | Technologies |
|--------|-----|------|-------------|
| **SSO Server** | 192.168.1.59 | Authentication | Keycloak (OIDC/OAuth2) |
| **Application Server** | 192.168.1.66 | Web Frontend | Apache, PHP 8.1, PostgreSQL |
| **Python Server** | 192.168.1.90 | Processing Engine | FastAPI, Celery, Redis, MinIO |

### Data Flow

```
User Browser → Keycloak (SSO) → PHP App → Python API → Celery Workers
                                    ↓              ↓
                               PostgreSQL      MinIO + Redis
```

---

## 📁 Repository Structure

```
/home/runner/work/comparison/comparison/
├── docs/                           # Comprehensive documentation
│   ├── ANALYSIS.md                # Current vs target architecture analysis
│   └── architecture.md            # Detailed system architecture
│
├── database/                      # Database schema and migrations
│   ├── schema.sql                # PostgreSQL schema
│   └── migrations/               # Schema migrations
│
├── deploy/                        # Deployment configurations
│   ├── apache/                   # Apache vhost examples
│   ├── systemd/                  # Systemd service files
│   └── nginx/                    # Reverse proxy examples
│
├── php-app/                       # PHP Web Application
│   ├── public/                   # Web-accessible files
│   │   ├── index.php            # Application entry point
│   │   ├── css/                 # Stylesheets
│   │   ├── js/                  # JavaScript
│   │   └── assets/              # Images, fonts, etc.
│   │
│   ├── src/                      # PHP application code
│   │   ├── Config/              # Configuration classes
│   │   │   ├── AppConfig.php   # Main configuration
│   │   │   ├── Database.php    # PostgreSQL connection
│   │   │   └── Keycloak.php    # Keycloak OIDC config
│   │   │
│   │   ├── Controllers/         # HTTP request handlers
│   │   ├── Services/            # Business logic
│   │   ├── Repositories/        # Data access layer
│   │   ├── Middleware/          # Auth, CSRF, etc.
│   │   ├── Views/               # HTML templates
│   │   └── Utils/               # Helper functions
│   │
│   ├── storage/logs/            # Application logs
│   ├── .env.example             # Environment template
│   └── composer.json            # PHP dependencies
│
└── python-backend/               # Python Processing Engine
    ├── app/
    │   ├── main.py              # FastAPI application
    │   │
    │   ├── api/                 # API endpoints
    │   │   ├── health.py       # Health checks
    │   │   ├── upload.py       # File uploads
    │   │   ├── process.py      # Job submission
    │   │   ├── tasks.py        # Status polling
    │   │   └── results.py      # Results retrieval
    │   │
    │   ├── services/            # Service clients
    │   │   ├── minio_client.py # MinIO operations
    │   │   └── redis_client.py # Redis caching
    │   │
    │   ├── tasks/               # Celery tasks
    │   │   ├── celery_app.py   # Celery configuration
    │   │   └── comparison_tasks.py # Comparison jobs
    │   │
    │   ├── models/              # Data models
    │   │   └── schemas.py      # Pydantic schemas
    │   │
    │   ├── core/                # Core functionality
    │   │   ├── config.py       # Settings
    │   │   └── logging.py      # Logging setup
    │   │
    │   ├── adapters/            # Integration adapters
    │   └── legacy_logic/        # Reused Qt app code
    │
    ├── .env.example             # Environment template
    └── requirements.txt         # Python dependencies
```

---

## 🚀 Quick Start

### Prerequisites

**Application Server (192.168.1.66):**
- Apache with mod_rewrite
- PHP 8.1+ with php-fpm, php-pgsql, php-curl
- PostgreSQL 12+
- Composer

**Python Server (192.168.1.90):**
- Python 3.9+
- Redis 6+
- MinIO
- Tesseract OCR (optional, for TIFF processing)
- Ollama (optional, for semantic similarity)

**SSO Server (192.168.1.59):**
- Keycloak (existing installation)

### Installation

#### 1. Database Setup (Application Server)

```bash
# Create database
sudo -u postgres psql
CREATE DATABASE comparison_app;
CREATE USER comparison_user WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE comparison_app TO comparison_user;
\q

# Load schema
psql -U comparison_user -d comparison_app -f database/schema.sql
```

#### 2. Python Backend Setup (Python Server)

```bash
cd python-backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
nano .env  # Edit with actual values

# Start FastAPI server
uvicorn app.main:app --host 0.0.0.0 --port 8000

# Start Celery worker (in another terminal)
celery -A app.tasks.celery_app worker --loglevel=info
```

#### 3. PHP Application Setup (Application Server)

```bash
cd php-app

# Install dependencies
composer install

# Configure environment
cp .env.example .env
nano .env  # Edit with actual values

# Set permissions
sudo chown -R www-data:www-data storage/
sudo chmod -R 775 storage/

# Configure Apache (see deploy/apache/)
sudo cp ../deploy/apache/gismartanalytics.conf /etc/apache2/sites-available/
sudo a2ensite gismartanalytics
sudo systemctl reload apache2
```

---

## 🔑 Configuration

### Environment Files

**PHP (.env)**
- Database connection
- Keycloak OIDC credentials
- Python API URL
- Session settings
- Upload limits

**Python (.env)**
- Redis connection
- MinIO credentials
- Celery settings
- Processing thresholds
- Ollama settings (optional)

See `.env.example` files for all available options.

---

## 📊 Database Schema

The PostgreSQL database includes:

| Table | Purpose |
|-------|---------|
| `users` | Keycloak-mapped users |
| `cases` | Workspaces/projects |
| `uploads` | File upload metadata |
| `jobs` | Comparison jobs |
| `job_progress` | Real-time progress tracking |
| `results` | Job results metadata |
| `audit_logs` | Security audit trail |
| `app_settings` | Application configuration |
| `user_preferences` | User-specific settings |

See `database/schema.sql` for complete schema.

---

## 🔄 Workflow

### User Journey

1. **Login**: User authenticates via Keycloak
2. **Create Case**: User creates a workspace
3. **Upload Files**: Upload source file and target files
4. **Trigger Comparison**: Submit comparison job
5. **Monitor Progress**: Poll job status (pending → processing → completed)
6. **View Results**: Browse results, download CSV/HTML reports

### Technical Flow

```
1. PHP receives file upload
   ↓
2. PHP forwards to Python API (/api/upload)
   ↓
3. Python stores file in MinIO, returns object key
   ↓
4. PHP stores metadata in PostgreSQL
   ↓
5. User triggers comparison
   ↓
6. PHP calls Python API (/api/process)
   ↓
7. Python creates Celery task, returns task_id
   ↓
8. PHP stores job in database with task_id
   ↓
9. Celery worker processes comparison
   ↓
10. Worker generates CSV + HTML reports
    ↓
11. Worker uploads reports to MinIO
    ↓
12. PHP polls task status (/api/tasks/{task_id}/status)
    ↓
13. When complete, PHP retrieves results
    ↓
14. User downloads reports via presigned URLs
```

---

## 🛠️ Development

### Python Backend

**Run development server:**
```bash
cd python-backend
source venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

**Run Celery worker:**
```bash
celery -A app.tasks.celery_app worker --loglevel=debug
```

**API Documentation:**
Access `/docs` endpoint (development only)

### PHP Frontend

**Run built-in server (testing only):**
```bash
cd php-app/public
php -S localhost:8080
```

**Production: Use Apache with PHP-FPM**

---

## 🔐 Security

- **Authentication**: Keycloak OIDC (Authorization Code Flow)
- **Sessions**: Secure, HTTPOnly cookies
- **CSRF Protection**: Token-based protection
- **Secrets**: Environment variables only (never in code)
- **File Upload**: Type and size validation
- **Audit Logging**: All significant actions logged

---

## 📈 Monitoring

### Health Checks

- **PHP App**: `/health`
- **Python API**: `/health`, `/health/detailed`, `/health/ready`, `/health/live`

### Logs

- **PHP**: `storage/logs/app.log`, `storage/logs/audit.log`
- **Python**: `/var/log/comparison-backend/app.log`
- **Celery**: `/var/log/celery/worker.log`
- **Apache**: `/var/log/apache2/gismartanalytics-*.log`

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| `docs/ANALYSIS.md` | Repository analysis and migration plan |
| `docs/architecture.md` | Detailed system architecture |
| `docs/deployment.md` | Deployment procedures (TBD) |
| `docs/configuration.md` | Configuration guide (TBD) |
| `docs/database.md` | Database schema documentation (TBD) |
| `docs/api.md` | API reference (TBD) |
| `docs/authentication.md` | Authentication flow (TBD) |
| `docs/maintenance.md` | Maintenance procedures (TBD) |
| `docs/troubleshooting.md` | Common issues and solutions (TBD) |
| `docs/migration-from-qt.md` | Qt → Web migration guide (TBD) |

---

## 🔧 Troubleshooting

### Common Issues

**Database connection failed**
- Check PostgreSQL is running
- Verify credentials in `.env`
- Check firewall rules

**Python API not reachable**
- Verify FastAPI is running on port 8000
- Check Python server firewall
- Test with: `curl http://192.168.1.90:8000/health`

**Keycloak authentication fails**
- Verify Keycloak is accessible
- Check client credentials
- Ensure redirect URI is configured

**Celery tasks not processing**
- Check Redis is running
- Verify Celery worker is active: `celery -A app.tasks.celery_app inspect ping`
- Check worker logs

---

## 🧪 Testing

```bash
# Python tests
cd python-backend
pytest

# PHP tests
cd php-app
composer test
```

---

## 📝 License

[Specify your license here]

---

## 👥 Contributors

[List contributors or teams]

---

## 📞 Support

- **Email**: support@example.com
- **Admin**: admin@example.com

---

## 🗺️ Roadmap

- [x] **Phase 1**: Repository analysis and planning
- [x] **Phase 2**: Infrastructure skeleton
- [ ] **Phase 3**: Authentication with Keycloak
- [ ] **Phase 4**: Core workflow implementation
- [ ] **Phase 5**: Processing logic migration
- [ ] **Phase 6**: Web UI development
- [ ] **Phase 7**: Integration and testing
- [ ] **Phase 8**: Documentation completion

**Current Status**: Phase 2 in progress - Python backend skeleton complete, PHP skeleton in progress.

---

## ⚠️ Important Notes

### Current Implementation Status

**✅ Complete:**
- Database schema design
- Python backend API structure
- Environment configuration templates
- Service client classes (MinIO, Redis)
- Celery task framework
- Health check endpoints

**🚧 In Progress:**
- PHP application skeleton
- Keycloak integration
- Processing logic migration
- Web UI templates

**⏳ Pending:**
- Complete end-to-end workflow
- Authentication flow
- Admin interfaces
- Deployment automation

### For Novice Operators

This README provides a high-level overview. Detailed step-by-step guides are in the `docs/` directory. Key concepts:

- **Keycloak**: Handles login for you
- **PostgreSQL**: Stores app data (users, jobs, results metadata)
- **MinIO**: Stores actual files (like cloud storage)
- **Redis**: Speeds things up with caching
- **Celery**: Processes files in the background
- **PHP**: Shows web pages to users
- **Python**: Does the heavy file processing work

---

**For questions or issues, consult the documentation in `docs/` or contact your system administrator.**
