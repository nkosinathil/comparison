<?php
/**
 * Base Controller
 * 
 * Provides common functionality for all controllers.
 */

namespace App\Controllers;

use App\Services\SessionManager;
use App\Config\AppConfig;

abstract class Controller
{
    protected SessionManager $session;
    protected AppConfig $config;

    public function __construct()
    {
        $this->session = new SessionManager();
        $this->config = AppConfig::getInstance();
        $this->session->start();
    }

    /**
     * Render a view
     */
    protected function render(string $view, array $data = []): void
    {
        extract($data);
        
        $viewPath = __DIR__ . '/../Views/' . $view . '.php';
        
        if (!file_exists($viewPath)) {
            $this->error404("View not found: $view");
            return;
        }

        require $viewPath;
    }

    /**
     * Return JSON response
     */
    protected function json($data, int $status = 200): void
    {
        http_response_code($status);
        header('Content-Type: application/json');
        echo json_encode($data);
        exit;
    }

    /**
     * Redirect to a URL
     */
    protected function redirect(string $url, int $status = 302): void
    {
        http_response_code($status);
        header("Location: $url");
        exit;
    }

    /**
     * Get current authenticated user
     */
    protected function getUser(): ?array
    {
        $userId = $this->session->get('user_id');
        
        if (!$userId) {
            return null;
        }

        // Get user data from session
        return [
            'user_id' => $userId,
            'email' => $this->session->get('user_email'),
            'username' => $this->session->get('user_username'),
            'full_name' => $this->session->get('user_full_name'),
        ];
    }

    /**
     * Check if user is authenticated
     */
    protected function isAuthenticated(): bool
    {
        return $this->session->get('user_id') !== null;
    }

    /**
     * Get request input
     */
    protected function input(string $key, $default = null)
    {
        if ($_SERVER['REQUEST_METHOD'] === 'GET') {
            return $_GET[$key] ?? $default;
        }

        return $_POST[$key] ?? $default;
    }

    /**
     * Get all request input
     */
    protected function allInput(): array
    {
        if ($_SERVER['REQUEST_METHOD'] === 'GET') {
            return $_GET;
        }

        return $_POST;
    }

    /**
     * Get client IP address
     */
    protected function getClientIp(): string
    {
        if (!empty($_SERVER['HTTP_CLIENT_IP'])) {
            return $_SERVER['HTTP_CLIENT_IP'];
        } elseif (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
            return $_SERVER['HTTP_X_FORWARDED_FOR'];
        } else {
            return $_SERVER['REMOTE_ADDR'] ?? 'unknown';
        }
    }

    /**
     * Get user agent
     */
    protected function getUserAgent(): string
    {
        return $_SERVER['HTTP_USER_AGENT'] ?? 'unknown';
    }

    /**
     * Show 404 error
     */
    protected function error404(string $message = "Page not found"): void
    {
        http_response_code(404);
        $this->render('errors/404', ['message' => $message]);
        exit;
    }

    /**
     * Show 403 error
     */
    protected function error403(string $message = "Access denied"): void
    {
        http_response_code(403);
        $this->render('errors/403', ['message' => $message]);
        exit;
    }

    /**
     * Show 500 error
     */
    protected function error500(string $message = "Internal server error"): void
    {
        http_response_code(500);
        $this->render('errors/500', ['message' => $message]);
        exit;
    }
}
