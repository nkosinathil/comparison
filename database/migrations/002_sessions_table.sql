-- Sessions Table for PHP Session Storage
-- Add this to your existing database schema

CREATE TABLE IF NOT EXISTS sessions (
    session_id VARCHAR(255) PRIMARY KEY,
    data TEXT NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    last_activity TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index for efficient cleanup of expired sessions
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at);

-- Index for last activity queries
CREATE INDEX IF NOT EXISTS idx_sessions_last_activity ON sessions(last_activity);

COMMENT ON TABLE sessions IS 'Stores PHP session data when using database session driver';
COMMENT ON COLUMN sessions.session_id IS 'PHP session identifier';
COMMENT ON COLUMN sessions.data IS 'Serialized session data';
COMMENT ON COLUMN sessions.expires_at IS 'Session expiration timestamp';
COMMENT ON COLUMN sessions.last_activity IS 'Last activity timestamp for monitoring';
