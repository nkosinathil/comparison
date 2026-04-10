# System Architecture

## Overview

This document describes the three-server web architecture for the Unified File Comparison application, converted from the original Python Qt desktop application.

## System Components

### 1. SSO Server (192.168.1.59)

**Purpose:** Centralized authentication and authorization

**Technology Stack:**
- Keycloak (OIDC/OAuth2 provider)

**Responsibilities:**
- User authentication
- OIDC token issuance
- Role management (Admin, Analyst, Client/Viewer)
- SSO across applications

**Configuration:**
- Existing Keycloak realm and client ecosystem
- Client configured for Authorization Code Flow
- Redirect URI: `http://192.168.1.66/auth/callback`
- Roles: `admin`, `analyst`, `viewer`

---

### 2. Application Server (192.168.1.66)

**Purpose:** Web frontend and user-facing application logic

**Technology Stack:**
- Apache HTTP Server
- PHP 8.1 + PHP-FPM
- PostgreSQL (application database)
- Document Root: `/var/www/gismartanalytics/public`

**Responsibilities:**
1. **HTTP Request Handling**
   - Serve web pages
   - Handle form submissions
   - Process API requests from browser

2. **Authentication & Session Management**
   - Initiate OIDC login flows
   - Exchange auth codes for tokens
   - Maintain PHP sessions
   - Validate user roles

3. **Database Operations**
   - Store user records (mapped from Keycloak)
   - Manage cases/workspaces
   - Track uploads and jobs
   - Store result metadata
   - Audit logging

4. **Python API Integration**
   - Forward file uploads to Python server
   - Trigger processing jobs
   - Poll job status
   - Retrieve results

**Key Components:**
- **Controllers:** Handle HTTP requests
- **Services:** Business logic (Keycloak, Python API, session)
- **Repositories:** Database access layer
- **Views:** HTML templates
- **Middleware:** Auth checks, CSRF protection

---

### 3. Python Server (192.168.1.90)

**Purpose:** Heavy processing engine and object storage

**Technology Stack:**
- FastAPI (REST API framework)
- Celery (distributed task queue)
- Redis (message broker + result backend + cache)
- MinIO (S3-compatible object storage)

**Responsibilities:**
1. **File Management**
   - Accept file uploads via HTTP
   - Store files in MinIO
   - Return object references

2. **Processing Orchestration**
   - Queue comparison jobs in Celery
   - Return task IDs immediately
   - Provide task status endpoints

3. **Heavy Computation (Celery Workers)**
   - Download files from MinIO
   - Parse documents (PDF, Word, Excel, email, TIFF OCR)
   - Compute fingerprints (SHA-256, simhash, tokens)
   - Run comparison algorithms
   - Generate reports (CSV, HTML)
   - Store results in MinIO

4. **Caching**
   - Cache file fingerprints in Redis (by SHA-256)
   - Avoid re-parsing identical files

**Key Components:**
- **FastAPI app:** HTTP endpoints
- **Celery workers:** Background processing
- **MinIO client:** Object storage operations
- **Redis client:** Caching and Celery broker
- **Legacy logic:** Reused comparison algorithms from Qt app

---

## Authentication Flow

### OIDC Authorization Code Flow

```
1. User accesses protected page on PHP app (192.168.1.66)
   ↓
2. PHP detects no valid session
   ↓
3. PHP redirects browser to Keycloak (192.168.1.59):
   https://192.168.1.59:8080/realms/{realm}/protocol/openid-connect/auth
   ?client_id={client_id}
   &redirect_uri=http://192.168.1.66/auth/callback
   &response_type=code
   &scope=openid profile email roles
   ↓
4. User logs in to Keycloak
   ↓
5. Keycloak redirects back to PHP with auth code:
   http://192.168.1.66/auth/callback?code={auth_code}
   ↓
6. PHP exchanges code for tokens (backend call to Keycloak):
   POST https://192.168.1.59:8080/realms/{realm}/protocol/openid-connect/token
   Body: grant_type=authorization_code&code={auth_code}&redirect_uri=...
   ↓
7. Keycloak returns:
   - access_token (JWT)
   - id_token (JWT with user info)
   - refresh_token
   ↓
8. PHP decodes id_token to get user info (sub, email, name, roles)
   ↓
9. PHP stores user in PostgreSQL if not exists (keyed by Keycloak sub)
   ↓
10. PHP creates session and redirects to original destination
```

### Session Management

- PHP stores session ID in browser cookie (HttpOnly, SameSite)
- Session data includes:
  - User ID (from PostgreSQL)
  - Keycloak subject (sub)
  - Roles
  - Access token (for future API calls if needed)
  - Expiry timestamp

---

## Data Flow: File Comparison Workflow

### Step 1: User Creates a Case

```
Browser → PHP (/cases/create)
PHP → PostgreSQL (INSERT INTO cases)
PHP → Browser (case_id, redirect to upload page)
```

### Step 2: User Uploads Source File

```
Browser → PHP (/upload)
   - multipart/form-data with file

PHP validates:
   - File size
   - File type (allowed extensions)
   - User owns the case

PHP → Python API (POST /api/upload)
   - multipart/form-data with file
   - Headers: X-User-Id, X-Case-Id

Python FastAPI:
   - Validates file
   - Computes SHA-256
   - Uploads to MinIO (bucket: uploads)
   - Object key: {case_id}/{file_sha256}/{filename}
   - Returns JSON: {"object_key": "...", "sha256": "..."}

PHP → PostgreSQL (INSERT INTO uploads)
   - case_id, filename, sha256, minio_key, upload_type='source'

PHP → Browser (upload_id, success message)
```

### Step 3: User Uploads Target Files

Same as Step 2, but `upload_type='target'` and can repeat multiple times.

### Step 4: User Triggers Comparison

```
Browser → PHP (/jobs/create)
   - POST with case_id, settings (comparison types, thresholds)

PHP validates:
   - Case exists
   - User owns case
   - At least 1 source and 1 target file uploaded

PHP → PostgreSQL (INSERT INTO jobs)
   - status='pending', created_at=NOW()
   - Returns job_id

PHP → Python API (POST /api/process)
   - JSON body:
     {
       "job_id": 123,
       "source_minio_key": "...",
       "target_minio_keys": ["...", "..."],
       "settings": {
         "compare_types": ["all"],
         "use_semantic": false,
         "simhash_max_dist": 5,
         ...
       }
     }

Python FastAPI:
   - Creates Celery task
   - Returns task_id immediately

   Celery.apply_async(comparison_task, args=[job_id, source_key, target_keys, settings])
   → Returns task_id

Python → PHP (JSON: {"task_id": "abc-123-def"})

PHP → PostgreSQL (UPDATE jobs SET task_id='abc-123-def', status='queued')

PHP → Browser ({"job_id": 123, "status": "queued"})
```

### Step 5: Celery Worker Processes Job

```
Celery Worker (background, async):
   1. Update task state → 'STARTED'
   
   2. Download source file from MinIO
      - Check Redis cache for fingerprints (key: sha256:{file_hash})
      - If cached, load fingerprints
      - If not, parse file and compute fingerprints, cache in Redis
   
   3. For each target file:
      - Download from MinIO
      - Check Redis cache
      - Parse and fingerprint if not cached
   
   4. For each target:
      - Run comparison algorithm (verdict_for)
      - Compute scores: simhash, jaccard, cosine, semantic
      - Determine verdict: IDENTICAL, NEAR_DUPLICATE, UNRELATED, etc.
   
   5. Generate results:
      - CSV: all comparisons with scores
      - HTML: styled report with color-coded verdicts
   
   6. Upload results to MinIO:
      - results/{job_id}/results.csv
      - results/{job_id}/report.html
   
   7. Update task state → 'SUCCESS'
   
   8. Store result metadata in PostgreSQL via API callback (optional)
      OR PHP polls and updates when status = SUCCESS
```

### Step 6: User Polls Job Status

```
Browser → PHP (/jobs/{job_id}/status)
   - Every 2-5 seconds

PHP → Python API (GET /api/tasks/{task_id}/status)

Python queries Celery task state:
   - PENDING, STARTED, PROGRESS, SUCCESS, FAILURE

Python → PHP (JSON):
   {
     "task_id": "abc-123-def",
     "state": "PROGRESS",
     "progress": 45,
     "current": "Processing target 23 of 50"
   }

PHP → Browser (JSON with status)
```

### Step 7: Job Completes

```
When Python returns state='SUCCESS':

PHP → Python API (GET /api/tasks/{task_id}/result)

Python → PHP (JSON):
   {
     "csv_key": "results/123/results.csv",
     "html_key": "results/123/report.html",
     "summary": {
       "total_targets": 50,
       "identical": 2,
       "near_duplicate": 5,
       "unrelated": 43
     }
   }

PHP → PostgreSQL (INSERT INTO results)
   - job_id, csv_minio_key, html_minio_key, summary_json, completed_at

PHP → PostgreSQL (UPDATE jobs SET status='completed')

Browser → PHP (/jobs/{job_id}/results)
   - Displays summary
   - Links to download CSV and HTML from MinIO via signed URLs
```

---

## Database Schema (PostgreSQL on App Server)

### users
Stores users authenticated via Keycloak.
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    keycloak_sub VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255),
    name VARCHAR(255),
    roles TEXT[], -- e.g., {'admin', 'analyst'}
    created_at TIMESTAMP DEFAULT NOW(),
    last_login TIMESTAMP
);
```

### cases
Workspaces for organizing comparison jobs.
```sql
CREATE TABLE cases (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### uploads
Tracks uploaded files (source and targets).
```sql
CREATE TABLE uploads (
    id SERIAL PRIMARY KEY,
    case_id INTEGER REFERENCES cases(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id),
    filename VARCHAR(255) NOT NULL,
    sha256 VARCHAR(64) NOT NULL,
    minio_key VARCHAR(500) NOT NULL,
    upload_type VARCHAR(20) NOT NULL, -- 'source' or 'target'
    file_size BIGINT,
    uploaded_at TIMESTAMP DEFAULT NOW()
);
```

### jobs
Comparison jobs.
```sql
CREATE TABLE jobs (
    id SERIAL PRIMARY KEY,
    case_id INTEGER REFERENCES cases(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id),
    task_id VARCHAR(255) UNIQUE, -- Celery task ID
    settings JSONB, -- comparison settings
    status VARCHAR(50) DEFAULT 'pending', -- pending, queued, processing, completed, failed
    created_at TIMESTAMP DEFAULT NOW(),
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);
```

### results
Stores metadata about completed job results.
```sql
CREATE TABLE results (
    id SERIAL PRIMARY KEY,
    job_id INTEGER REFERENCES jobs(id) ON DELETE CASCADE,
    csv_minio_key VARCHAR(500),
    html_minio_key VARCHAR(500),
    summary JSONB, -- e.g., {"total": 50, "identical": 2, ...}
    created_at TIMESTAMP DEFAULT NOW()
);
```

### audit_logs
Security and compliance audit trail.
```sql
CREATE TABLE audit_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    action VARCHAR(100) NOT NULL, -- 'login', 'upload', 'job_create', etc.
    resource_type VARCHAR(50), -- 'case', 'job', etc.
    resource_id INTEGER,
    details JSONB,
    ip_address VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW()
);
```

### app_settings
Application-wide configuration.
```sql
CREATE TABLE app_settings (
    key VARCHAR(100) PRIMARY KEY,
    value TEXT,
    updated_at TIMESTAMP DEFAULT NOW()
);
```

---

## Object Storage (MinIO on Python Server)

### Buckets

1. **uploads**
   - User-uploaded files
   - Path: `{case_id}/{sha256}/{filename}`
   - Retention: Until case is deleted

2. **results**
   - Generated CSV and HTML reports
   - Path: `{job_id}/results.csv` and `{job_id}/report.html`
   - Retention: Configurable (e.g., 90 days)

3. **cache** (optional)
   - Preprocessed file fingerprints
   - Path: `fingerprints/{sha256}.json`

---

## Caching Strategy (Redis on Python Server)

### Cache Keys

1. **File Fingerprints**
   - Key: `fp:{sha256}`
   - Value: JSON with parsed content and fingerprints
   - TTL: 7 days (configurable)
   - Avoids re-parsing identical files

2. **Celery Broker**
   - Default Redis database (e.g., db=0)
   - Queues: `celery` (default), `priority` (optional)

3. **Celery Results**
   - Redis database (e.g., db=1)
   - Stores task states and results
   - TTL: 24 hours

---

## Security Considerations

### 1. Authentication
- Keycloak OIDC ensures centralized auth
- PHP validates session on every request
- No passwords stored in application database

### 2. Authorization
- Role checks in PHP middleware
- Python API can verify roles if needed (future enhancement)
- Admins can view all cases; analysts and viewers only their own

### 3. Data Protection
- No hardcoded secrets
- Environment variables for credentials
- HTTPS recommended for production (even internal)
- MinIO access keys in .env
- PostgreSQL credentials in .env

### 4. File Upload Validation
- Check file extensions
- Check MIME types
- Limit file sizes
- Scan for malware (future enhancement)

### 5. CSRF Protection
- PHP middleware generates and validates CSRF tokens
- All state-changing forms include CSRF token

---

## Scalability Considerations

### Horizontal Scaling

1. **PHP App Server**
   - Can run multiple PHP-FPM workers
   - Apache can handle load balancing
   - Stateless (sessions in PostgreSQL or Redis if needed)

2. **Celery Workers**
   - Can add more Celery worker processes/machines
   - All workers connect to same Redis broker
   - Distribute load across workers

3. **MinIO**
   - Can be clustered for high availability
   - Currently single instance acceptable

### Performance Optimization

1. **Redis Caching**
   - Reduces redundant file parsing
   - Caches fingerprints by SHA-256

2. **Celery Concurrency**
   - Configure worker concurrency (e.g., 4-8 parallel tasks per worker)
   - Use multiprocessing or eventlet

3. **Database Indexing**
   - Index on: `users.keycloak_sub`, `jobs.task_id`, `uploads.sha256`, `cases.user_id`

---

## Monitoring & Logging

### Application Logs

1. **PHP Logs**
   - Location: `/var/www/gismartanalytics/storage/logs/app.log`
   - Levels: DEBUG, INFO, WARNING, ERROR
   - Format: JSON or structured

2. **Python Logs**
   - Location: `/var/log/fastapi/app.log`
   - Celery logs: `/var/log/celery/worker.log`
   - Format: JSON with timestamps, levels, context

3. **Apache Logs**
   - Access log: `/var/log/apache2/gismartanalytics-access.log`
   - Error log: `/var/log/apache2/gismartanalytics-error.log`

### Health Checks

1. **PHP App**
   - Endpoint: `/health`
   - Checks: PostgreSQL connection, session store

2. **Python API**
   - Endpoint: `/health`
   - Checks: Redis connection, MinIO connection, Celery broker

3. **Celery Workers**
   - Use `celery inspect ping` to check worker status

---

## Disaster Recovery

### Backups

1. **PostgreSQL**
   - Daily pg_dump backups
   - Retention: 30 days
   - Store offsite or on backup server

2. **MinIO**
   - Periodic snapshots or replication
   - Critical data: uploaded files and results

3. **Configuration**
   - Keep .env files backed up securely
   - Version control for code (Git)

### Restore Procedures

1. Restore PostgreSQL from dump
2. Restore MinIO buckets
3. Redeploy code from Git
4. Restore .env files
5. Restart services

---

## Future Enhancements

1. **WebSocket/SSE for real-time updates**
   - Replace polling with push notifications
   - Show live progress during processing

2. **API Authentication for Python**
   - Validate API keys or JWTs from PHP
   - Prevent unauthorized access to Python endpoints

3. **Advanced Search**
   - Full-text search in PostgreSQL
   - Search across cases, results, etc.

4. **Email Notifications**
   - Notify users when jobs complete
   - Integration with SMTP server

5. **Multi-tenancy**
   - Support organizations with isolated data
   - Keycloak realms or groups

6. **Batch Operations**
   - Upload and process multiple cases at once
   - Bulk export of results
