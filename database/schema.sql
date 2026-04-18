-- ========================================
-- Database Schema for File Comparison Web App
-- PostgreSQL 12+
-- ========================================

-- Drop existing tables (for clean install)
DROP TABLE IF EXISTS sessions CASCADE;
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS results CASCADE;
DROP TABLE IF EXISTS job_progress CASCADE;
DROP TABLE IF EXISTS jobs CASCADE;
DROP TABLE IF EXISTS uploads CASCADE;
DROP TABLE IF EXISTS cases CASCADE;
DROP TABLE IF EXISTS user_preferences CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS app_settings CASCADE;

-- ========================================
-- USERS TABLE
-- ========================================
-- Stores user records authenticated via Keycloak
-- These are mapped from Keycloak's user database
-- The keycloak_sub is the unique identifier from Keycloak
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    keycloak_sub VARCHAR(255) UNIQUE NOT NULL,  -- Keycloak subject ID (UUID)
    email VARCHAR(255),
    name VARCHAR(255),
    roles TEXT[],  -- Array of role names: {'admin', 'analyst', 'viewer'}
    created_at TIMESTAMP DEFAULT NOW(),
    last_login TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_users_keycloak_sub ON users(keycloak_sub);
CREATE INDEX idx_users_email ON users(email);

COMMENT ON TABLE users IS 'Application users mapped from Keycloak SSO';
COMMENT ON COLUMN users.keycloak_sub IS 'Unique Keycloak subject identifier from id_token';
COMMENT ON COLUMN users.roles IS 'Array of roles assigned in Keycloak';

-- ========================================
-- USER PREFERENCES TABLE
-- ========================================
-- Stores user-specific settings and preferences
CREATE TABLE user_preferences (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    preference_key VARCHAR(100) NOT NULL,
    preference_value TEXT,
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, preference_key)
);

CREATE INDEX idx_user_prefs_user_id ON user_preferences(user_id);

COMMENT ON TABLE user_preferences IS 'User-specific configuration and preferences';

-- ========================================
-- CASES TABLE
-- ========================================
-- Workspaces/containers for organizing comparison work
-- Each case can have multiple uploads and jobs
CREATE TABLE cases (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'active',  -- active, archived, deleted
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_cases_user_id ON cases(user_id);
CREATE INDEX idx_cases_status ON cases(status);

COMMENT ON TABLE cases IS 'Workspaces/cases containing related comparison jobs';
COMMENT ON COLUMN cases.status IS 'Case lifecycle: active, archived, deleted';

-- ========================================
-- UPLOADS TABLE
-- ========================================
-- Tracks all files uploaded by users
-- Files are stored in MinIO, this table holds metadata
CREATE TABLE uploads (
    id SERIAL PRIMARY KEY,
    case_id INTEGER REFERENCES cases(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id),
    filename VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    sha256 VARCHAR(64) NOT NULL,  -- SHA-256 hash of file content
    minio_bucket VARCHAR(100) NOT NULL,  -- MinIO bucket name
    minio_key VARCHAR(500) NOT NULL,  -- MinIO object key/path
    upload_type VARCHAR(20) NOT NULL,  -- 'source' or 'target'
    file_size BIGINT,  -- Bytes
    mime_type VARCHAR(100),
    uploaded_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_uploads_case_id ON uploads(case_id);
CREATE INDEX idx_uploads_user_id ON uploads(user_id);
CREATE INDEX idx_uploads_sha256 ON uploads(sha256);
CREATE INDEX idx_uploads_type ON uploads(upload_type);

COMMENT ON TABLE uploads IS 'Metadata for files uploaded to MinIO';
COMMENT ON COLUMN uploads.sha256 IS 'Used for deduplication and cache lookup';
COMMENT ON COLUMN uploads.minio_key IS 'Full object path in MinIO: {case_id}/{sha256}/{filename}';
COMMENT ON COLUMN uploads.upload_type IS 'Either source (1 per job) or target (N per job)';

-- ========================================
-- JOBS TABLE
-- ========================================
-- Comparison jobs submitted by users
-- Each job compares one source file against multiple targets
CREATE TABLE jobs (
    id SERIAL PRIMARY KEY,
    case_id INTEGER REFERENCES cases(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id),
    task_id VARCHAR(255) UNIQUE,  -- Celery task ID for tracking
    source_upload_id INTEGER REFERENCES uploads(id),
    settings JSONB,  -- Job configuration: {compare_types, thresholds, etc.}
    status VARCHAR(50) DEFAULT 'pending',  -- pending, queued, processing, completed, failed, cancelled
    error_message TEXT,  -- Error details if status=failed
    created_at TIMESTAMP DEFAULT NOW(),
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE INDEX idx_jobs_case_id ON jobs(case_id);
CREATE INDEX idx_jobs_user_id ON jobs(user_id);
CREATE INDEX idx_jobs_task_id ON jobs(task_id);
CREATE INDEX idx_jobs_status ON jobs(status);

COMMENT ON TABLE jobs IS 'File comparison jobs managed by Celery';
COMMENT ON COLUMN jobs.task_id IS 'Celery task UUID for polling status';
COMMENT ON COLUMN jobs.settings IS 'JSON: compare_types, simhash_max_dist, jaccard_near_dup, etc.';
COMMENT ON COLUMN jobs.status IS 'Lifecycle: pending -> queued -> processing -> completed/failed';

-- ========================================
-- JOB PROGRESS TABLE
-- ========================================
-- Tracks detailed progress during job execution
-- Updated by Celery worker as processing proceeds
CREATE TABLE job_progress (
    id SERIAL PRIMARY KEY,
    job_id INTEGER REFERENCES jobs(id) ON DELETE CASCADE,
    current_step VARCHAR(255),  -- E.g., "Processing target 23 of 50"
    progress_percent INTEGER DEFAULT 0,  -- 0-100
    details JSONB,  -- Additional progress info
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_job_progress_job_id ON job_progress(job_id);

COMMENT ON TABLE job_progress IS 'Real-time progress updates from Celery workers';

-- ========================================
-- RESULTS TABLE
-- ========================================
-- Metadata for completed job results
-- Actual CSV and HTML reports are stored in MinIO
CREATE TABLE results (
    id SERIAL PRIMARY KEY,
    job_id INTEGER REFERENCES jobs(id) ON DELETE CASCADE,
    csv_minio_key VARCHAR(500),  -- Path to results.csv in MinIO
    html_minio_key VARCHAR(500),  -- Path to report.html in MinIO
    summary JSONB,  -- E.g., {"total": 50, "identical": 2, "near_duplicate": 5, ...}
    result_count INTEGER,  -- Number of target files compared
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_results_job_id ON results(job_id);

COMMENT ON TABLE results IS 'Metadata for job results stored in MinIO';
COMMENT ON COLUMN results.summary IS 'JSON summary: counts by verdict type';
COMMENT ON COLUMN results.csv_minio_key IS 'Full MinIO path: results/{job_id}/results.csv';

-- ========================================
-- AUDIT LOGS TABLE
-- ========================================
-- Security and compliance audit trail
-- Records all significant user actions
CREATE TABLE audit_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    action VARCHAR(100) NOT NULL,  -- login, logout, upload, job_create, etc.
    resource_type VARCHAR(50),  -- case, job, upload, etc.
    resource_id INTEGER,  -- ID of affected resource
    details JSONB,  -- Additional context
    ip_address VARCHAR(50),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource_type, resource_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);

COMMENT ON TABLE audit_logs IS 'Security audit trail for all user actions';
COMMENT ON COLUMN audit_logs.action IS 'Action type: login, upload, job_create, download, etc.';

-- ========================================
-- APP SETTINGS TABLE
-- ========================================
-- Application-wide configuration
-- Key-value store for runtime settings
CREATE TABLE app_settings (
    key VARCHAR(100) PRIMARY KEY,
    value TEXT,
    description TEXT,
    updated_at TIMESTAMP DEFAULT NOW(),
    updated_by INTEGER REFERENCES users(id)
);

COMMENT ON TABLE app_settings IS 'Application configuration key-value store';

-- ========================================
-- SESSIONS TABLE
-- ========================================
-- Stores PHP session data when using database session driver
CREATE TABLE sessions (
    session_id VARCHAR(255) PRIMARY KEY,
    data TEXT NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    last_activity TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);
CREATE INDEX idx_sessions_last_activity ON sessions(last_activity);

COMMENT ON TABLE sessions IS 'Stores PHP session data when using database session driver';
COMMENT ON COLUMN sessions.session_id IS 'PHP session identifier';
COMMENT ON COLUMN sessions.data IS 'Serialized session data';
COMMENT ON COLUMN sessions.expires_at IS 'Session expiration timestamp';

-- ========================================
-- INITIAL DATA
-- ========================================

-- Insert default app settings
INSERT INTO app_settings (key, value, description) VALUES
    ('maintenance_mode', 'false', 'Set to true to enable maintenance mode'),
    ('max_upload_size_mb', '500', 'Maximum file upload size in MB'),
    ('max_targets_per_job', '1000', 'Maximum number of target files per job'),
    ('default_simhash_max_dist', '5', 'Default simhash distance threshold'),
    ('default_jaccard_near_dup', '0.50', 'Default Jaccard similarity threshold'),
    ('default_semantic_threshold', '0.90', 'Default semantic similarity threshold'),
    ('default_semantic_review_threshold', '0.75', 'Default semantic review threshold'),
    ('default_cosine_near_dup', '0.85', 'Default cosine similarity threshold'),
    ('ollama_enabled', 'false', 'Enable semantic similarity via Ollama'),
    ('ollama_url', 'http://localhost:11434', 'Ollama API base URL'),
    ('ollama_model', 'nomic-embed-text', 'Ollama embedding model name');

-- ========================================
-- TRIGGERS
-- ========================================

-- Auto-update updated_at timestamp for cases
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_cases_updated_at BEFORE UPDATE ON cases
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_prefs_updated_at BEFORE UPDATE ON user_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_app_settings_updated_at BEFORE UPDATE ON app_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ========================================
-- VIEWS (for convenience)
-- ========================================

-- View: Active jobs with user and case info
CREATE OR REPLACE VIEW active_jobs_view AS
SELECT 
    j.id,
    j.task_id,
    j.status,
    j.created_at,
    j.started_at,
    j.completed_at,
    u.name AS user_name,
    u.email AS user_email,
    c.name AS case_name,
    up.filename AS source_filename,
    (j.settings->>'compare_types') AS compare_types
FROM jobs j
JOIN users u ON j.user_id = u.id
JOIN cases c ON j.case_id = c.id
LEFT JOIN uploads up ON j.source_upload_id = up.id
WHERE j.status NOT IN ('completed', 'failed', 'cancelled')
ORDER BY j.created_at DESC;

COMMENT ON VIEW active_jobs_view IS 'Currently active jobs with context';

-- View: Job statistics by user
CREATE OR REPLACE VIEW user_job_stats AS
SELECT 
    u.id AS user_id,
    u.name,
    u.email,
    COUNT(*) AS total_jobs,
    COUNT(*) FILTER (WHERE j.status = 'completed') AS completed_jobs,
    COUNT(*) FILTER (WHERE j.status = 'failed') AS failed_jobs,
    COUNT(*) FILTER (WHERE j.status IN ('pending', 'queued', 'processing')) AS active_jobs
FROM users u
LEFT JOIN jobs j ON u.id = j.user_id
GROUP BY u.id, u.name, u.email;

COMMENT ON VIEW user_job_stats IS 'Job statistics aggregated by user';

-- ========================================
-- GRANTS (if using separate app user)
-- ========================================
-- Example if you create a dedicated database user for the PHP app
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO comparison_app_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO comparison_app_user;

-- ========================================
-- COMPLETION
-- ========================================
-- Schema created successfully
-- Next steps:
-- 1. Run this script on PostgreSQL server (192.168.1.66)
-- 2. Create dedicated database user if not using default
-- 3. Configure connection string in PHP .env file
-- 4. Test connection from PHP app
