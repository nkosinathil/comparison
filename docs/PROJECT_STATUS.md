# Migration Project Status

## Overview

Migration of the Python Qt desktop file-comparison application to a three-server web architecture.

| Server | IP | Role | Stack |
|--------|----|------|-------|
| SSO Server | 192.168.1.59 | Authentication | Keycloak (OIDC) |
| App Server | 192.168.1.66 | Web Frontend | Apache, PHP 8.1, PostgreSQL |
| Python Server | 192.168.1.90 | Processing | FastAPI, Celery, Redis, MinIO |

---

## Phase 1: Analysis & Planning — COMPLETE

- Analysed `unified_compare_qt.py` (UI, ~546 lines) and `unified_compare_app.py` (engine, ~956 lines).
- Produced `docs/ANALYSIS.md` (code classification) and `docs/architecture.md` (3-server spec).
- Designed PostgreSQL schema (`database/schema.sql`).

## Phase 2: Infrastructure Skeleton — COMPLETE

### Database (`database/`)

| Artefact | Status |
|----------|--------|
| `schema.sql` — 9 tables + sessions, views, triggers, seed data | Done |
| `migrations/002_sessions_table.sql` | Done (also merged into main schema) |

### Python Backend (`python-backend/`)

| Component | Status |
|-----------|--------|
| `app/main.py` — FastAPI with middleware, CORS, logging | Done |
| `app/core/config.py` — Pydantic settings | Done |
| `app/core/logging.py` — structured JSON logging | Done |
| `app/models/schemas.py` — Pydantic request/response models | Done |
| `app/api/health.py` — `/health`, `/health/detailed`, readiness, liveness | Done |
| `app/api/upload.py` — file upload to MinIO | Done |
| `app/api/process.py` — job submission to Celery | Done |
| `app/api/tasks.py` — task status + result endpoints | Done |
| `app/api/results.py` — download and presigned URLs | Done |
| `app/services/minio_client.py` — MinIO upload/download/list/delete | Done |
| `app/services/redis_client.py` — JSON cache + fingerprint cache | Done |
| `app/tasks/celery_app.py` — Celery app config | Done |
| `app/tasks/comparison_tasks.py` — **real** comparison task (see Phase 3) | Done |
| `requirements.txt` + `.env.example` | Done |
| `__init__.py` in every package | Done |

### PHP Application (`php-app/`)

| Component | Status |
|-----------|--------|
| `composer.json` + `.env.example` | Done |
| `src/Config/AppConfig.php` — singleton .env loader | Done |
| `src/Config/Database.php` — PDO singleton + transactions | Done |
| `src/Config/Keycloak.php` — OIDC URL helpers | Done |
| `src/Services/KeycloakService.php` — auth URL, token exchange, refresh, userinfo | Done |
| `src/Services/SessionManager.php` — file + DB session handler | Done |
| `src/Services/PythonApiClient.php` — Guzzle client for all Python API endpoints | Done |
| `src/Repositories/UserRepository.php` — aligned to schema (id, name, roles) | Done |
| `src/Repositories/AuditLogRepository.php` — aligned to schema (resource_type/resource_id) | Done |
| `src/Repositories/CaseRepository.php` — CRUD for cases table | Done |
| `src/Repositories/JobRepository.php` — uploads + jobs + results queries | Done |
| `src/Middleware/AuthMiddleware.php` | Done |
| `src/Middleware/CsrfMiddleware.php` | Done |
| `src/Middleware/GuestMiddleware.php` | Done |
| `src/Controllers/Controller.php` — base with render, JSON, auth helpers | Done |
| `src/Controllers/AuthController.php` — login, callback, logout | Done |
| `src/Controllers/DashboardController.php` — landing page + stats | Done |
| `src/Controllers/ComparisonController.php` — create, upload, start, status | Done |
| `src/Controllers/ResultsController.php` — list, show, download CSV/HTML | Done |
| `src/Router.php` — simple path-based router | Done |
| `public/index.php` — front controller with all routes | Done |
| `public/.htaccess` — Apache rewrite rules | Done |
| `public/css/app.css` — responsive stylesheet | Done |
| `public/js/app.js` + `public/js/comparison.js` — upload + polling JS | Done |
| `src/Views/layouts/app.php` — master layout | Done |
| `src/Views/dashboard/index.php` — dashboard page | Done |
| `src/Views/comparison/create.php` — new comparison wizard | Done |
| `src/Views/results/index.php` — result list | Done |
| `src/Views/results/show.php` — result detail | Done |
| `src/Views/errors/404.php`, `403.php`, `500.php`, `auth_failed.php` | Done |

## Phase 3: Core Logic Integration — COMPLETE

- Added missing `tfidf_cosine_similarity()` and `combined_comparison_score()` to `unified_compare_app.py` (were called by `verdict_for` but never defined).
- Created `python-backend/app/legacy_logic/comparison_engine.py` — adapter module that wraps the original engine functions for use from the web backend.
  - `compare_files_from_bytes()` — runs full comparison from in-memory bytes (no local filesystem needed).
  - `generate_csv_bytes()` / `generate_html_bytes()` — produce report files as bytes.
- Replaced stub Celery task with real implementation:
  - Downloads source + targets from MinIO.
  - Calls `compare_files_from_bytes` with all settings.
  - Uploads CSV + HTML reports back to MinIO.
  - Reports real summary stats.
- `cleanup_old_results_task` now implemented.

---

## Remaining Work

### Phase 4: Deployment Configuration
- [ ] Apache virtual host config for PHP app
- [ ] systemd service files for FastAPI + Celery workers
- [ ] Nginx reverse proxy config for Python server (optional)
- [ ] Docker / docker-compose for development environment

### Phase 5: Testing
- [ ] Python backend unit tests (pytest)
- [ ] PHP unit tests (PHPUnit)
- [ ] Integration tests (end-to-end upload → compare → download)

### Phase 6: Security Hardening
- [ ] JWT signature verification in KeycloakService
- [ ] API authentication between PHP and Python servers
- [ ] Input validation and file-type whitelisting enforcement
- [ ] Rate limiting on upload endpoints

### Phase 7: Production Polish
- [ ] WebSocket or SSE for real-time progress (replace polling)
- [ ] Pagination on results list
- [ ] Admin panel (user management, app settings, audit log viewer)
- [ ] Case management UI (archive, delete)

### Phase 8: Documentation
- [ ] Deployment guide (step-by-step for each server)
- [ ] API reference (auto-generated from FastAPI docs)
- [ ] User guide (how to use the web interface)
