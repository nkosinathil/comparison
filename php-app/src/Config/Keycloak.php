<?php
/**
 * Keycloak Configuration
 * 
 * Provides Keycloak OIDC endpoints and configuration.
 */

namespace App\Config;

class Keycloak
{
    private AppConfig $config;

    public function __construct()
    {
        $this->config = AppConfig::getInstance();
    }

    public function getAuthorizationUrl(): string
    {
        return $this->getRealmUrl() . '/protocol/openid-connect/auth';
    }

    public function getTokenUrl(): string
    {
        return $this->getRealmUrl() . '/protocol/openid-connect/token';
    }

    public function getUserInfoUrl(): string
    {
        return $this->getRealmUrl() . '/protocol/openid-connect/userinfo';
    }

    public function getLogoutUrl(): string
    {
        return $this->getRealmUrl() . '/protocol/openid-connect/logout';
    }

    public function getRealmUrl(): string
    {
        $baseUrl = $this->config->get('keycloak.url');
        $realm = $this->config->get('keycloak.realm');
        return rtrim($baseUrl, '/') . '/realms/' . $realm;
    }

    public function getClientId(): string
    {
        return $this->config->get('keycloak.client_id');
    }

    public function getClientSecret(): string
    {
        return $this->config->get('keycloak.client_secret');
    }

    public function getRedirectUri(): string
    {
        return $this->config->get('keycloak.redirect_uri');
    }

    public function getLogoutRedirectUri(): string
    {
        return $this->config->get('keycloak.logout_redirect');
    }

    public function isConfigured(): bool
    {
        return !empty($this->config->get('keycloak.url'))
            && !empty($this->config->get('keycloak.realm'))
            && !empty($this->config->get('keycloak.client_id'))
            && !empty($this->config->get('keycloak.client_secret'));
    }
}
