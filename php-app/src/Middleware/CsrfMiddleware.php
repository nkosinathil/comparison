<?php
/**
 * CSRF Middleware
 * 
 * Protects against Cross-Site Request Forgery attacks.
 */

namespace App\Middleware;

use App\Services\SessionManager;
use App\Config\AppConfig;

class CsrfMiddleware implements MiddlewareInterface
{
    private SessionManager $session;
    private AppConfig $config;

    public function __construct()
    {
        $this->session = new SessionManager();
        $this->config = AppConfig::getInstance();
    }

    public function handle(callable $next)
    {
        // Start session if not started
        $this->session->start();

        // Generate CSRF token if not exists
        if (!$this->session->has('csrf_token')) {
            $this->session->set('csrf_token', $this->generateToken());
        }

        // Check CSRF token for state-changing requests
        $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
        
        if (in_array($method, ['POST', 'PUT', 'PATCH', 'DELETE'])) {
            $tokenName = $this->config->get('csrf.token_name');
            $submittedToken = $_POST[$tokenName] ?? $_SERVER['HTTP_X_CSRF_TOKEN'] ?? null;
            $sessionToken = $this->session->get('csrf_token');

            if (!$submittedToken || !hash_equals($sessionToken, $submittedToken)) {
                http_response_code(403);
                echo json_encode(['error' => 'CSRF token validation failed']);
                exit;
            }
        }

        return $next();
    }

    /**
     * Generate a random CSRF token
     */
    private function generateToken(): string
    {
        return bin2hex(random_bytes(32));
    }

    /**
     * Get current CSRF token
     */
    public static function getToken(): string
    {
        $session = new SessionManager();
        $session->start();
        
        if (!$session->has('csrf_token')) {
            $session->set('csrf_token', bin2hex(random_bytes(32)));
        }
        
        return $session->get('csrf_token');
    }
}
