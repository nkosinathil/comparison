<?php
/**
 * Keycloak Service
 * 
 * Handles Keycloak OIDC authentication flows.
 */

namespace App\Services;

use App\Config\AppConfig;
use App\Config\Keycloak;
use GuzzleHttp\Client;
use GuzzleHttp\Exception\GuzzleException;

class KeycloakService
{
    private Keycloak $keycloak;
    private Client $httpClient;
    private AppConfig $config;

    public function __construct()
    {
        $this->keycloak = new Keycloak();
        $this->config = AppConfig::getInstance();
        $this->httpClient = new Client([
            'timeout' => 10,
            'verify' => true,
        ]);
    }

    /**
     * Generate authorization URL for login
     */
    public function getAuthorizationUrl(string $state): string
    {
        $params = [
            'client_id' => $this->keycloak->getClientId(),
            'redirect_uri' => $this->keycloak->getRedirectUri(),
            'response_type' => 'code',
            'scope' => 'openid profile email',
            'state' => $state,
        ];

        return $this->keycloak->getAuthorizationUrl() . '?' . http_build_query($params);
    }

    /**
     * Exchange authorization code for tokens
     */
    public function exchangeCodeForToken(string $code): ?array
    {
        try {
            $response = $this->httpClient->post($this->keycloak->getTokenUrl(), [
                'form_params' => [
                    'grant_type' => 'authorization_code',
                    'code' => $code,
                    'redirect_uri' => $this->keycloak->getRedirectUri(),
                    'client_id' => $this->keycloak->getClientId(),
                    'client_secret' => $this->keycloak->getClientSecret(),
                ],
            ]);

            $data = json_decode($response->getBody()->getContents(), true);
            
            if (isset($data['access_token'])) {
                return $data;
            }

            return null;
        } catch (GuzzleException $e) {
            error_log("Token exchange failed: " . $e->getMessage());
            return null;
        }
    }

    /**
     * Refresh access token using refresh token
     */
    public function refreshToken(string $refreshToken): ?array
    {
        try {
            $response = $this->httpClient->post($this->keycloak->getTokenUrl(), [
                'form_params' => [
                    'grant_type' => 'refresh_token',
                    'refresh_token' => $refreshToken,
                    'client_id' => $this->keycloak->getClientId(),
                    'client_secret' => $this->keycloak->getClientSecret(),
                ],
            ]);

            $data = json_decode($response->getBody()->getContents(), true);
            
            if (isset($data['access_token'])) {
                return $data;
            }

            return null;
        } catch (GuzzleException $e) {
            error_log("Token refresh failed: " . $e->getMessage());
            return null;
        }
    }

    /**
     * Get user information from Keycloak
     */
    public function getUserInfo(string $accessToken): ?array
    {
        try {
            $response = $this->httpClient->get($this->keycloak->getUserInfoUrl(), [
                'headers' => [
                    'Authorization' => 'Bearer ' . $accessToken,
                ],
            ]);

            $data = json_decode($response->getBody()->getContents(), true);
            return $data;
        } catch (GuzzleException $e) {
            error_log("Get user info failed: " . $e->getMessage());
            return null;
        }
    }

    /**
     * Validate access token
     */
    public function validateToken(string $accessToken): bool
    {
        // Attempt to get user info - if successful, token is valid
        $userInfo = $this->getUserInfo($accessToken);
        return $userInfo !== null;
    }

    /**
     * Generate logout URL
     */
    public function getLogoutUrl(?string $idToken = null): string
    {
        $params = [
            'post_logout_redirect_uri' => $this->keycloak->getLogoutRedirectUri(),
            'client_id' => $this->keycloak->getClientId(),
        ];

        if ($idToken) {
            $params['id_token_hint'] = $idToken;
        }

        return $this->keycloak->getLogoutUrl() . '?' . http_build_query($params);
    }

    /**
     * Decode JWT token (basic, no signature verification)
     * For production, use a proper JWT library with signature verification
     */
    public function decodeToken(string $token): ?array
    {
        $parts = explode('.', $token);
        
        if (count($parts) !== 3) {
            return null;
        }

        try {
            $payload = base64_decode(strtr($parts[1], '-_', '+/'));
            return json_decode($payload, true);
        } catch (\Exception $e) {
            error_log("Token decode failed: " . $e->getMessage());
            return null;
        }
    }

    /**
     * Check if token is expired
     */
    public function isTokenExpired(string $token): bool
    {
        $decoded = $this->decodeToken($token);
        
        if (!$decoded || !isset($decoded['exp'])) {
            return true;
        }

        return time() >= $decoded['exp'];
    }
}
