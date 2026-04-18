<?php

namespace Tests\Unit\Config;

use PHPUnit\Framework\TestCase;

/**
 * Tests for AppConfig — verifies that configuration keys are loaded
 * and that the dot-notation accessor works correctly.
 *
 * NOTE: Requires a .env file (or environment variables) to be present
 * when running in CI. Copy .env.example to .env for local testing.
 */
class AppConfigTest extends TestCase
{
    public function testSingletonInstance(): void
    {
        $a = \App\Config\AppConfig::getInstance();
        $b = \App\Config\AppConfig::getInstance();
        $this->assertSame($a, $b);
    }

    public function testGetReturnsDefault(): void
    {
        $config = \App\Config\AppConfig::getInstance();
        $this->assertSame('fallback', $config->get('nonexistent.key', 'fallback'));
    }

    public function testGetNestedKey(): void
    {
        $config = \App\Config\AppConfig::getInstance();
        $this->assertIsString($config->get('app.name'));
    }

    public function testAllReturnsArray(): void
    {
        $config = \App\Config\AppConfig::getInstance();
        $all = $config->all();
        $this->assertIsArray($all);
        $this->assertArrayHasKey('app', $all);
        $this->assertArrayHasKey('database', $all);
        $this->assertArrayHasKey('python_api', $all);
    }
}
