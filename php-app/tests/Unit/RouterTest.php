<?php

namespace Tests\Unit;

use PHPUnit\Framework\TestCase;
use App\Router;

class RouterTest extends TestCase
{
    public function testRouteRegistration(): void
    {
        $router = new Router();
        $router->get('/test', 'FakeController', 'action');
        $router->post('/submit', 'FakeController', 'submit');

        $ref = new \ReflectionClass($router);
        $prop = $ref->getProperty('routes');
        $prop->setAccessible(true);
        $routes = $prop->getValue($router);

        $this->assertArrayHasKey('GET', $routes);
        $this->assertArrayHasKey('/test', $routes['GET']);
        $this->assertArrayHasKey('POST', $routes);
        $this->assertArrayHasKey('/submit', $routes['POST']);
    }

    public function testCsrfExempt(): void
    {
        $router = new Router();
        $router->csrfExempt('/webhook');

        $ref = new \ReflectionClass($router);
        $method = $ref->getMethod('isCsrfExempt');
        $method->setAccessible(true);

        $this->assertTrue($method->invoke($router, '/webhook'));
        $this->assertFalse($method->invoke($router, '/other'));
    }
}
