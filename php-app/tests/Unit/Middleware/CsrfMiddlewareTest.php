<?php

namespace Tests\Unit\Middleware;

use PHPUnit\Framework\TestCase;
use App\Middleware\CsrfMiddleware;

class CsrfMiddlewareTest extends TestCase
{
    public function testGetTokenReturnsNonEmpty(): void
    {
        $token = CsrfMiddleware::getToken();
        $this->assertNotEmpty($token);
        $this->assertSame(64, strlen($token), 'Token should be 64 hex characters (32 bytes)');
    }

    public function testGetTokenIdempotent(): void
    {
        $a = CsrfMiddleware::getToken();
        $b = CsrfMiddleware::getToken();
        $this->assertSame($a, $b, 'Token should remain stable within one session');
    }
}
