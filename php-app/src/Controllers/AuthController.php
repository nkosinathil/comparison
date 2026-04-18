<?php
/**
 * Authentication Controller
 * 
 * Handles login, logout, and OAuth callback.
 */

namespace App\Controllers;

use App\Services\KeycloakService;
use App\Repositories\UserRepository;
use App\Repositories\AuditLogRepository;

class AuthController extends Controller
{
    private KeycloakService $keycloak;
    private UserRepository $userRepo;
    private AuditLogRepository $auditRepo;

    public function __construct()
    {
        parent::__construct();
        $this->keycloak = new KeycloakService();
        $this->userRepo = new UserRepository();
        $this->auditRepo = new AuditLogRepository();
    }

    /**
     * Show login page or redirect to Keycloak
     */
    public function login(): void
    {
        // If already authenticated, redirect to dashboard
        if ($this->isAuthenticated()) {
            $this->redirect('/dashboard');
            return;
        }

        // Generate state for CSRF protection
        $state = bin2hex(random_bytes(16));
        $this->session->set('oauth_state', $state);

        // Get authorization URL
        $authUrl = $this->keycloak->getAuthorizationUrl($state);

        // Redirect to Keycloak
        $this->redirect($authUrl);
    }

    /**
     * Handle OAuth callback from Keycloak
     */
    public function callback(): void
    {
        // Get parameters
        $code = $this->input('code');
        $state = $this->input('state');
        $error = $this->input('error');
        $errorDescription = $this->input('error_description');

        // Check for errors
        if ($error) {
            error_log("OAuth error: $error - $errorDescription");
            $this->auditRepo->logFailedLogin(
                'unknown',
                "OAuth error: $error",
                $this->getClientIp(),
                $this->getUserAgent()
            );
            $this->render('errors/auth_failed', [
                'error' => $errorDescription ?? $error
            ]);
            return;
        }

        // Validate state
        $sessionState = $this->session->get('oauth_state');
        if (!$state || !$sessionState || $state !== $sessionState) {
            error_log("OAuth state mismatch");
            $this->auditRepo->logFailedLogin(
                'unknown',
                'State mismatch',
                $this->getClientIp(),
                $this->getUserAgent()
            );
            $this->render('errors/auth_failed', [
                'error' => 'Invalid state parameter. Please try again.'
            ]);
            return;
        }

        // Clear state
        $this->session->remove('oauth_state');

        // Exchange code for tokens
        $tokens = $this->keycloak->exchangeCodeForToken($code);

        if (!$tokens) {
            error_log("Token exchange failed");
            $this->auditRepo->logFailedLogin(
                'unknown',
                'Token exchange failed',
                $this->getClientIp(),
                $this->getUserAgent()
            );
            $this->render('errors/auth_failed', [
                'error' => 'Failed to exchange authorization code. Please try again.'
            ]);
            return;
        }

        // Get user info
        $userInfo = $this->keycloak->getUserInfo($tokens['access_token']);

        if (!$userInfo) {
            error_log("Failed to get user info");
            $this->auditRepo->logFailedLogin(
                'unknown',
                'Failed to get user info',
                $this->getClientIp(),
                $this->getUserAgent()
            );
            $this->render('errors/auth_failed', [
                'error' => 'Failed to retrieve user information. Please try again.'
            ]);
            return;
        }

        // Sync user with database
        $user = $this->userRepo->syncFromKeycloak($userInfo);

        if (!$user) {
            error_log("Failed to sync user");
            $this->auditRepo->logFailedLogin(
                $userInfo['email'] ?? 'unknown',
                'Failed to sync user',
                $this->getClientIp(),
                $this->getUserAgent()
            );
            $this->render('errors/auth_failed', [
                'error' => 'Failed to create or update user account. Please contact support.'
            ]);
            return;
        }

        // Store user info in session
        $this->session->set('user_id', $user['id']);
        $this->session->set('user_email', $user['email']);
        $this->session->set('user_name', $user['name']);
        $this->session->set('access_token', $tokens['access_token']);
        $this->session->set('refresh_token', $tokens['refresh_token'] ?? null);
        $this->session->set('id_token', $tokens['id_token'] ?? null);

        // Regenerate session ID for security
        $this->session->regenerate(true);

        // Log successful login
        $this->auditRepo->logLogin(
            $user['id'],
            $this->getClientIp(),
            $this->getUserAgent()
        );

        // Redirect to intended page or dashboard
        $redirectTo = $this->session->get('redirect_after_login', '/dashboard');
        $this->session->remove('redirect_after_login');
        
        $this->redirect($redirectTo);
    }

    /**
     * Logout user
     */
    public function logout(): void
    {
        $userId = $this->session->get('user_id');
        $idToken = $this->session->get('id_token');

        // Log logout if user was authenticated
        if ($userId) {
            $this->auditRepo->logLogout(
                $userId,
                $this->getClientIp(),
                $this->getUserAgent()
            );
        }

        // Destroy session
        $this->session->destroy();

        // Get Keycloak logout URL
        $logoutUrl = $this->keycloak->getLogoutUrl($idToken);

        // Redirect to Keycloak logout
        $this->redirect($logoutUrl);
    }
}
