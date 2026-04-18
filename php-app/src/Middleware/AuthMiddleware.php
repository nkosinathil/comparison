<?php
/**
 * Authentication Middleware
 * 
 * Ensures user is authenticated before accessing protected routes.
 */

namespace App\Middleware;

use App\Services\SessionManager;
use App\Services\KeycloakService;

class AuthMiddleware implements MiddlewareInterface
{
    private SessionManager $session;
    private KeycloakService $keycloak;

    public function __construct()
    {
        $this->session = new SessionManager();
        $this->keycloak = new KeycloakService();
    }

    public function handle(callable $next)
    {
        // Start session if not started
        $this->session->start();

        // Check if user is authenticated
        $userId = $this->session->get('user_id');
        $accessToken = $this->session->get('access_token');

        if (!$userId || !$accessToken) {
            $this->redirectToLogin();
            return null;
        }

        // Check if token is expired
        if ($this->keycloak->isTokenExpired($accessToken)) {
            // Try to refresh token
            $refreshToken = $this->session->get('refresh_token');
            
            if ($refreshToken) {
                $newTokens = $this->keycloak->refreshToken($refreshToken);
                
                if ($newTokens) {
                    // Update session with new tokens
                    $this->session->set('access_token', $newTokens['access_token']);
                    if (isset($newTokens['refresh_token'])) {
                        $this->session->set('refresh_token', $newTokens['refresh_token']);
                    }
                    if (isset($newTokens['id_token'])) {
                        $this->session->set('id_token', $newTokens['id_token']);
                    }
                } else {
                    // Refresh failed, redirect to login
                    $this->session->destroy();
                    $this->redirectToLogin();
                    return null;
                }
            } else {
                // No refresh token, redirect to login
                $this->session->destroy();
                $this->redirectToLogin();
                return null;
            }
        }

        // User is authenticated, continue
        return $next();
    }

    private function redirectToLogin(): void
    {
        $currentUrl = $_SERVER['REQUEST_URI'] ?? '/';
        $this->session->set('redirect_after_login', $currentUrl);
        
        header('Location: /login');
        exit;
    }
}
