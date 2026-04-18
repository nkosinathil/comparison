<?php
/**
 * Application Configuration
 * 
 * Loads and manages environment-based configuration.
 */

namespace App\Config;

use Dotenv\Dotenv;

class AppConfig
{
    private static ?AppConfig $instance = null;
    private array $config = [];

    private function __construct()
    {
        // Load .env file
        $dotenv = Dotenv::createImmutable(__DIR__ . '/../../');
        $dotenv->load();

        // Load configuration from environment
        $this->config = [
            'app' => [
                'name' => $_ENV['APP_NAME'] ?? 'File Comparison System',
                'env' => $_ENV['APP_ENV'] ?? 'production',
                'debug' => filter_var($_ENV['APP_DEBUG'] ?? false, FILTER_VALIDATE_BOOLEAN),
                'url' => $_ENV['APP_URL'] ?? 'http://localhost',
                'timezone' => $_ENV['APP_TIMEZONE'] ?? 'UTC',
            ],
            'database' => [
                'connection' => $_ENV['DB_CONNECTION'] ?? 'pgsql',
                'host' => $_ENV['DB_HOST'] ?? 'localhost',
                'port' => (int)($_ENV['DB_PORT'] ?? 5432),
                'database' => $_ENV['DB_DATABASE'] ?? 'comparison_app',
                'username' => $_ENV['DB_USERNAME'] ?? 'postgres',
                'password' => $_ENV['DB_PASSWORD'] ?? '',
                'schema' => $_ENV['DB_SCHEMA'] ?? 'public',
            ],
            'keycloak' => [
                'url' => $_ENV['KEYCLOAK_URL'] ?? '',
                'realm' => $_ENV['KEYCLOAK_REALM'] ?? '',
                'client_id' => $_ENV['KEYCLOAK_CLIENT_ID'] ?? '',
                'client_secret' => $_ENV['KEYCLOAK_CLIENT_SECRET'] ?? '',
                'redirect_uri' => $_ENV['KEYCLOAK_REDIRECT_URI'] ?? '',
                'logout_redirect' => $_ENV['KEYCLOAK_LOGOUT_REDIRECT'] ?? '',
            ],
            'session' => [
                'driver' => $_ENV['SESSION_DRIVER'] ?? 'file',
                'lifetime' => (int)($_ENV['SESSION_LIFETIME'] ?? 7200),
                'cookie_name' => $_ENV['SESSION_COOKIE_NAME'] ?? 'comparison_session',
                'cookie_secure' => filter_var($_ENV['SESSION_COOKIE_SECURE'] ?? false, FILTER_VALIDATE_BOOLEAN),
                'cookie_httponly' => filter_var($_ENV['SESSION_COOKIE_HTTPONLY'] ?? true, FILTER_VALIDATE_BOOLEAN),
                'cookie_samesite' => $_ENV['SESSION_COOKIE_SAMESITE'] ?? 'Lax',
            ],
            'csrf' => [
                'token_name' => $_ENV['CSRF_TOKEN_NAME'] ?? '_csrf_token',
                'cookie_name' => $_ENV['CSRF_COOKIE_NAME'] ?? 'csrf_cookie',
            ],
            'python_api' => [
                'url' => $_ENV['PYTHON_API_URL'] ?? 'http://localhost:8000',
                'timeout' => (int)($_ENV['PYTHON_API_TIMEOUT'] ?? 30),
                'api_key' => $_ENV['PYTHON_API_KEY'] ?? '',
            ],
            'upload' => [
                'max_size' => (int)($_ENV['MAX_UPLOAD_SIZE'] ?? 524288000), // 500MB
                'allowed_extensions' => explode(',', $_ENV['ALLOWED_EXTENSIONS'] ?? 'pdf,docx,xlsx,txt,eml,msg'),
                'temp_dir' => $_ENV['UPLOAD_TEMP_DIR'] ?? '/tmp/comparison_uploads',
            ],
            'logging' => [
                'level' => $_ENV['LOG_LEVEL'] ?? 'info',
                'file' => $_ENV['LOG_FILE'] ?? __DIR__ . '/../../storage/logs/app.log',
                'max_size' => (int)($_ENV['LOG_MAX_SIZE'] ?? 10485760), // 10MB
                'max_files' => (int)($_ENV['LOG_MAX_FILES'] ?? 5),
            ],
            'audit' => [
                'enabled' => filter_var($_ENV['AUDIT_ENABLED'] ?? true, FILTER_VALIDATE_BOOLEAN),
                'log_file' => $_ENV['AUDIT_LOG_FILE'] ?? __DIR__ . '/../../storage/logs/audit.log',
            ],
        ];

        // Set timezone
        date_default_timezone_set($this->config['app']['timezone']);
    }

    public static function getInstance(): AppConfig
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    public function get(string $key, $default = null)
    {
        $keys = explode('.', $key);
        $value = $this->config;

        foreach ($keys as $k) {
            if (!isset($value[$k])) {
                return $default;
            }
            $value = $value[$k];
        }

        return $value;
    }

    public function all(): array
    {
        return $this->config;
    }

    public function isProduction(): bool
    {
        return $this->get('app.env') === 'production';
    }

    public function isDebug(): bool
    {
        return $this->get('app.debug', false);
    }
}
