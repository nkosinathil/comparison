<?php
/**
 * Keycloak Service
 *
 * Handles Keycloak OIDC authentication flows with proper JWT verification.
 */

namespace App\Services;

use App\Config\AppConfig;
use App\Config\Keycloak;
use Firebase\JWT\JWT;
use Firebase\JWT\JWK;
use Firebase\JWT\Key;
use GuzzleHttp\Client;
use GuzzleHttp\Exception\GuzzleException;

class KeycloakService
{
    private Keycloak $keycloak;
    private Client $httpClient;
    private AppConfig $config;

    private static ?array $jwksCache = null;

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
     * Get user information from Keycloak userinfo endpoint
     */
    public function getUserInfo(string $accessToken): ?array
    {
        try {
            $response = $this->httpClient->get($this->keycloak->getUserInfoUrl(), [
                'headers' => [
                    'Authorization' => 'Bearer ' . $accessToken,
                ],
            ]);

            return json_decode($response->getBody()->getContents(), true);
        } catch (GuzzleException $e) {
            error_log("Get user info failed: " . $e->getMessage());
            return null;
        }
    }

    /**
     * Validate access token by calling userinfo endpoint
     */
    public function validateToken(string $accessToken): bool
    {
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
     * Decode and verify a JWT token using Keycloak's JWKS public keys.
     *
     * Falls back to unsigned decode if the JWKS endpoint is unreachable
     * (e.g. during initial dev setup), but logs a warning.
     */
    public function decodeToken(string $token): ?array
    {
        try {
            $keys = $this->getJwks();
            if ($keys) {
                $decoded = JWT::decode($token, $keys);
                return (array) $decoded;
            }
        } catch (\Exception $e) {
            error_log("JWT verification failed: " . $e->getMessage());
            return null;
        }

        return $this->decodeTokenUnsafe($token);
    }

    /**
     * Check if token is expired.
     * Uses verified decode when possible.
     */
    public function isTokenExpired(string $token): bool
    {
        $decoded = $this->decodeToken($token);

        if (!$decoded || !isset($decoded['exp'])) {
            return true;
        }

        return time() >= $decoded['exp'];
    }

    /**
     * Fetch Keycloak JWKS keys (cached per request).
     *
     * @return array<string, Key>|null
     */
    private function getJwks(): ?array
    {
        if (self::$jwksCache !== null) {
            return self::$jwksCache;
        }

        try {
            $response = $this->httpClient->get($this->keycloak->getCertsUrl());
            $jwksData = json_decode($response->getBody()->getContents(), true);

            if (!$jwksData || empty($jwksData['keys'])) {
                error_log("Keycloak JWKS response empty");
                return null;
            }

            self::$jwksCache = JWK::parseKeySet($jwksData);
            return self::$jwksCache;
        } catch (\Exception $e) {
            error_log("Failed to fetch Keycloak JWKS: " . $e->getMessage());
            return null;
        }
    }

    /**
     * Fallback: decode JWT payload without signature verification.
     * Used ONLY when JWKS is unreachable. Logs a warning.
     */
    private function decodeTokenUnsafe(string $token): ?array
    {
        error_log("WARNING: Decoding JWT without signature verification — JWKS unavailable");

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
}
