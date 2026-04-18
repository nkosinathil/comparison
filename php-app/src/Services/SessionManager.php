<?php
/**
 * Session Manager
 * 
 * Manages user sessions with database or file storage.
 */

namespace App\Services;

use App\Config\AppConfig;
use App\Config\Database;
use PDO;

class SessionManager
{
    private AppConfig $config;
    private ?Database $db = null;
    private bool $started = false;

    public function __construct()
    {
        $this->config = AppConfig::getInstance();
        
        // Only initialize database if using database sessions
        if ($this->config->get('session.driver') === 'database') {
            $this->db = Database::getInstance();
        }
    }

    /**
     * Start the session
     */
    public function start(): bool
    {
        if ($this->started) {
            return true;
        }

        // Configure session settings
        ini_set('session.cookie_httponly', $this->config->get('session.cookie_httponly') ? '1' : '0');
        ini_set('session.cookie_secure', $this->config->get('session.cookie_secure') ? '1' : '0');
        ini_set('session.cookie_samesite', $this->config->get('session.cookie_samesite'));
        ini_set('session.gc_maxlifetime', (string)$this->config->get('session.lifetime'));
        
        session_name($this->config->get('session.cookie_name'));

        // Set custom session handler if using database
        if ($this->config->get('session.driver') === 'database') {
            session_set_save_handler(
                [$this, 'sessionOpen'],
                [$this, 'sessionClose'],
                [$this, 'sessionRead'],
                [$this, 'sessionWrite'],
                [$this, 'sessionDestroy'],
                [$this, 'sessionGc']
            );
        }

        $result = session_start();
        $this->started = $result;

        // Regenerate session ID periodically for security
        if ($result && !$this->has('_session_created')) {
            $this->set('_session_created', time());
            session_regenerate_id(true);
        }

        return $result;
    }

    /**
     * Set a session value
     */
    public function set(string $key, $value): void
    {
        $_SESSION[$key] = $value;
    }

    /**
     * Get a session value
     */
    public function get(string $key, $default = null)
    {
        return $_SESSION[$key] ?? $default;
    }

    /**
     * Check if session key exists
     */
    public function has(string $key): bool
    {
        return isset($_SESSION[$key]);
    }

    /**
     * Remove a session value
     */
    public function remove(string $key): void
    {
        unset($_SESSION[$key]);
    }

    /**
     * Clear all session data
     */
    public function clear(): void
    {
        $_SESSION = [];
    }

    /**
     * Destroy the session
     */
    public function destroy(): bool
    {
        $this->clear();
        
        if ($this->started) {
            return session_destroy();
        }
        
        return true;
    }

    /**
     * Regenerate session ID
     */
    public function regenerate(bool $deleteOldSession = true): bool
    {
        return session_regenerate_id($deleteOldSession);
    }

    /**
     * Get session ID
     */
    public function getId(): string
    {
        return session_id();
    }

    // ========================================
    // Database Session Handler Methods
    // ========================================

    public function sessionOpen($savePath, $sessionName): bool
    {
        return true;
    }

    public function sessionClose(): bool
    {
        return true;
    }

    public function sessionRead($sessionId): string
    {
        if (!$this->db) {
            return '';
        }

        try {
            $conn = $this->db->getConnection();
            $stmt = $conn->prepare(
                "SELECT data FROM sessions 
                 WHERE session_id = :session_id 
                 AND expires_at > NOW()"
            );
            $stmt->execute(['session_id' => $sessionId]);
            $result = $stmt->fetch(PDO::FETCH_ASSOC);

            return $result ? $result['data'] : '';
        } catch (\Exception $e) {
            error_log("Session read error: " . $e->getMessage());
            return '';
        }
    }

    public function sessionWrite($sessionId, $data): bool
    {
        if (!$this->db) {
            return false;
        }

        try {
            $conn = $this->db->getConnection();
            $lifetime = $this->config->get('session.lifetime');
            $expiresAt = date('Y-m-d H:i:s', time() + $lifetime);

            $stmt = $conn->prepare(
                "INSERT INTO sessions (session_id, data, expires_at, last_activity)
                 VALUES (:session_id, :data, :expires_at, NOW())
                 ON CONFLICT (session_id) 
                 DO UPDATE SET 
                    data = EXCLUDED.data,
                    expires_at = EXCLUDED.expires_at,
                    last_activity = NOW()"
            );

            return $stmt->execute([
                'session_id' => $sessionId,
                'data' => $data,
                'expires_at' => $expiresAt,
            ]);
        } catch (\Exception $e) {
            error_log("Session write error: " . $e->getMessage());
            return false;
        }
    }

    public function sessionDestroy($sessionId): bool
    {
        if (!$this->db) {
            return false;
        }

        try {
            $conn = $this->db->getConnection();
            $stmt = $conn->prepare("DELETE FROM sessions WHERE session_id = :session_id");
            return $stmt->execute(['session_id' => $sessionId]);
        } catch (\Exception $e) {
            error_log("Session destroy error: " . $e->getMessage());
            return false;
        }
    }

    public function sessionGc($maxLifetime): int
    {
        if (!$this->db) {
            return 0;
        }

        try {
            $conn = $this->db->getConnection();
            $stmt = $conn->prepare("DELETE FROM sessions WHERE expires_at < NOW()");
            $stmt->execute();
            return $stmt->rowCount();
        } catch (\Exception $e) {
            error_log("Session GC error: " . $e->getMessage());
            return 0;
        }
    }
}
