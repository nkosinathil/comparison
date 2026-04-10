<?php
/**
 * Guest Middleware
 * 
 * Redirects authenticated users away from guest-only pages (like login).
 */

namespace App\Middleware;

use App\Services\SessionManager;

class GuestMiddleware implements MiddlewareInterface
{
    private SessionManager $session;

    public function __construct()
    {
        $this->session = new SessionManager();
    }

    public function handle(callable $next)
    {
        // Start session if not started
        $this->session->start();

        // Check if user is authenticated
        $userId = $this->session->get('user_id');

        if ($userId) {
            // User is authenticated, redirect to dashboard
            header('Location: /dashboard');
            exit;
        }

        // User is not authenticated, continue
        return $next();
    }
}
