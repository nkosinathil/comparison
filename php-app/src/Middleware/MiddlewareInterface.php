<?php
/**
 * Middleware Interface
 * 
 * Base interface for all middleware.
 */

namespace App\Middleware;

interface MiddlewareInterface
{
    /**
     * Handle the request
     * 
     * @param callable $next Next middleware in chain
     * @return mixed
     */
    public function handle(callable $next);
}
