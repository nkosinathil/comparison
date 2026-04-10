# Repository Analysis: Qt Desktop to Web Migration

## Current Application Overview

### Application Purpose
The existing application is a **Unified File Comparison Tool** that:
- Compares a source file against multiple target files in a folder
- Supports multiple file types: emails (.eml, .msg), PDFs, Excel, Word, text files, and TIFF images
- Generates comparison reports with similarity analysis
- Uses various algorithms: SHA-256 hashing, simhash, Jaccard similarity, TF-IDF, and optional semantic similarity via Ollama embeddings

### Current Architecture

**Two-file structure:**
1. `unified_compare_qt.py` (546 lines) - Qt-based GUI
2. `unified_compare_app.py` (956 lines) - Core processing logic

### Code Classification

#### 1. **UI-Only Code (Qt-specific - TO REPLACE)**
Located in `unified_compare_qt.py`:
- `MainWindow` class - entire Qt UI
- `CompareWorker` class - Qt threading for background processing
- All PySide6 imports and widgets
- File browser dialogs
- Progress bars and log displays
- Button click handlers

**Total lines to replace: ~546 lines**

#### 2. **Pure Business Logic (PRESERVE & REUSE)**
Located in `unified_compare_app.py`:

**Text Processing (lines 71-147):**
- `normalize_whitespace()` - whitespace normalization
- `clean_text()` - text cleaning
- `tokenize()` - text tokenization
- `token_jaccard()` - Jaccard similarity calculation
- `simhash64()` - simhash fingerprinting
- `simhash_distance()` - Hamming distance calculation
- `_strip_html()` - HTML stripping

**Hashing Functions (lines 87-148):**
- `sha256_bytes()` - raw file hashing
- `sha256_text()` - text content hashing
- `canonical_attachment_set_hash()` - attachment hashing

**Semantic Similarity (lines 153-185):**
- `embed_text_ollama()` - Ollama embeddings API client
- `cosine_similarity()` - cosine similarity calculation

**File Parsers (lines 212-423):**
- `parse_text()` - plain text files
- `parse_docx()` - Word documents
- `parse_xlsx()` - Excel files
- `parse_pdf()` - PDF files
- `parse_eml()` - email files
- `parse_msg()` - Outlook MSG files
- `parse_tiff()` - TIFF images with OCR
- `parse_any()` - dispatcher function

**Comparison Logic (lines 446-661):**
- `compute_fingerprints()` - generates all fingerprints for a file
- `verdict_for()` - determines comparison verdict with scoring
- Verdict types: IDENTICAL, CONTENT_DUPLICATE, ATTACHMENT_MATCH, NEAR_DUPLICATE, SEMANTICALLY_SIMILAR, REVIEW_SEMANTIC, UNRELATED

**Report Generation (lines 668-760):**
- `write_html_report()` - generates styled HTML report

**Total reusable business logic: ~690 lines**

#### 3. **Local State Logic (MIGRATE TO PostgreSQL/MinIO)**

**Current SQLite Cache (lines 472-532):**
- `open_cache()` - SQLite connection
- `cache_get()` - retrieve cached fingerprints
- `cache_put()` - store cached fingerprints
- Stores: file path, raw SHA-256, parsed content, fingerprints

**File I/O:**
- Reads files from local filesystem
- Stores outputs (CSV, HTML) to local folders

**Migration Strategy:**
- SQLite cache → PostgreSQL + Redis
- Local files → MinIO object storage
- Results.csv → database table + downloadable export
- Report.html → web pages + downloadable export

#### 4. **Configuration & Settings**

**Current settings (hardcoded/UI inputs):**
- Source file path
- Target folder path
- Output folder path
- Comparison types (checkboxes)
- Semantic similarity toggle
- Ollama URL and model
- Threshold values:
  - `simhash_max_dist` (default: 5)
  - `jaccard_near_dup` (default: 0.50)
  - `semantic_threshold` (default: 0.90)
  - `semantic_review_threshold` (default: 0.75)
  - `cosine_near_dup` (default: 0.85)

**Will migrate to:**
- .env files for infrastructure settings
- PostgreSQL for user preferences
- UI forms for per-job settings

## Dependencies

### Current Requirements
```
PySide6 - Qt GUI (will remove)
python-docx - Word parsing (keep)
openpyxl - Excel parsing (keep)
pypdf/PyPDF2 - PDF parsing (keep)
extract-msg - Outlook MSG parsing (keep)
pillow - image handling (keep)
pytesseract - OCR (keep)
requests - HTTP calls (keep for Ollama)
```

### New Dependencies Needed

**Python Backend:**
- FastAPI - REST API framework
- Celery - task queue
- Redis - broker/cache
- SQLAlchemy - ORM
- Alembic - migrations
- boto3/minio - object storage
- python-multipart - file uploads
- pydantic - validation

**PHP Frontend:**
- Guzzle - HTTP client
- PHP-JWT - token handling
- Twig or Blade - templating (or pure PHP)
- Composer - dependency management

## Web Architecture Design

### Server Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    User's Browser                           │
│                  (OIDC Login Flow)                          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              SSO Server (192.168.1.59)                      │
│                                                             │
│  - Keycloak                                                 │
│  - OIDC/OAuth2 Provider                                     │
│  - Role Management (Admin, Analyst, Client/Viewer)          │
└─────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│        Application Server (192.168.1.66)                    │
│                                                             │
│  - Apache + PHP 8.1 + PHP-FPM                               │
│  - PostgreSQL (application database)                        │
│  - Web UI (MVC PHP app)                                     │
│  - Document root: /var/www/gismartanalytics/public         │
│                                                             │
│  Responsibilities:                                          │
│  - Handle browser requests                                  │
│  - Session management                                       │
│  - Keycloak authentication                                  │
│  - UI rendering                                             │
│  - PostgreSQL queries (metadata, jobs, users)               │
│  - HTTP calls to Python API                                 │
└────────────┬────────────────────────────────────────────────┘
             │ HTTP API calls
             ▼
┌─────────────────────────────────────────────────────────────┐
│          Python Server (192.168.1.90)                       │
│                                                             │
│  - FastAPI (REST API)                                       │
│  - Celery Workers                                           │
│  - Redis (broker + result backend + cache)                  │
│  - MinIO (object storage)                                   │
│                                                             │
│  Responsibilities:                                          │
│  - File processing endpoints                                │
│  - Celery task management                                   │
│  - Heavy comparison computations                            │
│  - MinIO file storage/retrieval                             │
│  - Redis caching                                            │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow: Complete Workflow

```
1. User logs in via browser
   └─> Browser redirects to Keycloak (192.168.1.59)
   └─> User authenticates
   └─> Keycloak redirects back to PHP app with auth code
   └─> PHP exchanges code for tokens
   └─> PHP creates session, stores user info in PostgreSQL

2. User creates a case/workspace
   └─> PHP stores case metadata in PostgreSQL
   └─> Returns case ID to browser

3. User uploads source file
   └─> Browser POSTs file to PHP
   └─> PHP validates file
   └─> PHP sends file to Python API (/api/upload)
   └─> Python stores file in MinIO
   └─> Python returns MinIO object reference
   └─> PHP stores upload record in PostgreSQL (references MinIO object)

4. User uploads target files
   └─> Same as step 3, multiple times

5. User triggers comparison
   └─> PHP calls Python API (/api/process)
   └─> Python creates Celery task
   └─> Python returns task_id immediately
   └─> PHP stores job record in PostgreSQL with task_id
   └─> Browser receives job_id

6. Celery worker processes job
   └─> Downloads source from MinIO
   └─> Downloads targets from MinIO
   └─> Runs comparison algorithms (reused from unified_compare_app.py)
   └─> Stores intermediate results in Redis
   └─> Stores final results in MinIO
   └─> Updates task status

7. User polls job status
   └─> Browser requests PHP (/jobs/{id}/status)
   └─> PHP calls Python API (/api/task/{task_id}/status)
   └─> Python queries Celery task state
   └─> Returns: pending/processing/completed/failed + progress %

8. Job completes
   └─> PHP retrieves results from Python API
   └─> PHP stores result metadata in PostgreSQL
   └─> User can view results in browser
   └─> User can download CSV/HTML reports from MinIO
```

## Key Design Decisions

### 1. **Preserve Python Processing Logic**
- All algorithms in `unified_compare_app.py` will be reused
- No rewriting of comparison logic
- Move code to `python-backend/app/legacy_logic/` initially
- Refactor into proper modules over time

### 2. **Asynchronous Processing**
- File comparison can be slow (hundreds of files)
- Use Celery to avoid HTTP timeouts
- Return task ID immediately
- Client polls for status

### 3. **Object Storage Strategy**
- Upload files → MinIO
- Processing results → MinIO
- PostgreSQL stores only metadata + MinIO references
- Avoids storing BLOBs in database

### 4. **Security Model**
- Keycloak handles authentication
- PHP validates sessions
- Role-based access in both PHP and Python
- No hardcoded credentials
- Environment-based configuration

### 5. **Caching Strategy**
- Current SQLite cache → Redis
- Cache fingerprints by file SHA-256
- Reduces re-processing of identical files

## Risks & Mitigations

### Risk 1: OCR Dependencies
**Issue:** pytesseract requires system Tesseract installation
**Mitigation:** Document installation steps; make OCR optional with graceful fallback

### Risk 2: Ollama Dependency
**Issue:** Semantic similarity requires external Ollama service
**Mitigation:** Make it completely optional; app works without it

### Risk 3: Large File Uploads
**Issue:** PHP has upload limits; MinIO needs sizing
**Mitigation:** Configure php.ini limits; document MinIO storage requirements

### Risk 4: Slow Processing
**Issue:** Comparing 1000+ files can take minutes
**Mitigation:** Use Celery; show progress; allow cancellation

### Risk 5: Network Configuration
**Issue:** Three separate servers need to communicate
**Mitigation:** Environment-driven URLs; clear documentation; health checks

## Target Folder Structure

```
/home/runner/work/comparison/comparison/
├── README.md (updated)
├── .gitignore (updated)
├── .env.example
│
├── docs/
│   ├── ANALYSIS.md (this file)
│   ├── architecture.md
│   ├── deployment.md
│   ├── configuration.md
│   ├── database.md
│   ├── api.md
│   ├── authentication.md
│   ├── maintenance.md
│   ├── troubleshooting.md
│   └── migration-from-qt.md
│
├── database/
│   ├── schema.sql
│   └── migrations/
│       ├── 001_initial_schema.sql
│       ├── 002_add_audit_logs.sql
│       └── ...
│
├── deploy/
│   ├── apache/
│   │   └── gismartanalytics.conf (vhost example)
│   ├── systemd/
│   │   ├── fastapi.service
│   │   ├── celery-worker.service
│   │   └── celery-beat.service (if needed)
│   ├── nginx/ (reverse proxy examples if needed)
│   └── docker/ (future: docker-compose if desired)
│
├── php-app/
│   ├── .env.example
│   ├── composer.json
│   ├── composer.lock
│   ├── public/
│   │   ├── index.php (entry point)
│   │   ├── css/
│   │   ├── js/
│   │   └── assets/
│   ├── src/
│   │   ├── Config/
│   │   │   ├── Database.php
│   │   │   ├── Keycloak.php
│   │   │   └── AppConfig.php
│   │   ├── Controllers/
│   │   │   ├── AuthController.php
│   │   │   ├── DashboardController.php
│   │   │   ├── CaseController.php
│   │   │   ├── UploadController.php
│   │   │   ├── JobController.php
│   │   │   ├── ResultController.php
│   │   │   └── AdminController.php
│   │   ├── Services/
│   │   │   ├── KeycloakService.php
│   │   │   ├── PythonApiClient.php
│   │   │   ├── SessionService.php
│   │   │   └── AuditLogger.php
│   │   ├── Repositories/
│   │   │   ├── UserRepository.php
│   │   │   ├── CaseRepository.php
│   │   │   ├── UploadRepository.php
│   │   │   ├── JobRepository.php
│   │   │   └── ResultRepository.php
│   │   ├── Middleware/
│   │   │   ├── AuthMiddleware.php
│   │   │   ├── RoleMiddleware.php
│   │   │   └── CsrfMiddleware.php
│   │   ├── Views/
│   │   │   ├── layout.php
│   │   │   ├── login.php
│   │   │   ├── dashboard.php
│   │   │   ├── cases.php
│   │   │   ├── upload.php
│   │   │   ├── jobs.php
│   │   │   ├── results.php
│   │   │   └── admin.php
│   │   └── Utils/
│   │       ├── Router.php
│   │       └── Validator.php
│   └── storage/
│       └── logs/
│
└── python-backend/
    ├── .env.example
    ├── requirements.txt
    ├── alembic.ini (database migrations)
    ├── app/
    │   ├── main.py (FastAPI app)
    │   ├── api/
    │   │   ├── __init__.py
    │   │   ├── health.py
    │   │   ├── upload.py
    │   │   ├── process.py
    │   │   ├── tasks.py
    │   │   └── results.py
    │   ├── services/
    │   │   ├── __init__.py
    │   │   ├── minio_client.py
    │   │   └── redis_client.py
    │   ├── tasks/
    │   │   ├── __init__.py
    │   │   ├── celery_app.py
    │   │   └── comparison_tasks.py
    │   ├── models/
    │   │   ├── __init__.py
    │   │   └── schemas.py (Pydantic models)
    │   ├── core/
    │   │   ├── __init__.py
    │   │   ├── config.py
    │   │   └── logging.py
    │   ├── adapters/
    │   │   ├── __init__.py
    │   │   └── legacy_wrapper.py
    │   └── legacy_logic/
    │       ├── __init__.py
    │       ├── parsers.py (from unified_compare_app.py)
    │       ├── fingerprints.py
    │       ├── comparison.py
    │       └── reporting.py
    └── tests/
        ├── test_api.py
        └── test_tasks.py
```

## Next Steps

Phase 2 will create this folder structure and generate skeleton files with:
- Environment configuration templates
- Database schema
- Basic routing and controllers
- Service class stubs
- Documentation structure

**Estimated Implementation Timeline:**
- Phase 2-3: 2-3 days (infrastructure + skeleton)
- Phase 4: 1-2 days (authentication)
- Phase 5: 3-4 days (core workflow)
- Phase 6: 2-3 days (processing logic migration)
- Phase 7: 2-3 days (UI development)
- Phase 8: 1-2 days (integration)
- Phase 9: 1 day (documentation)

**Total: ~12-18 days for complete migration**
