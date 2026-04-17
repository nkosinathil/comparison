<?php
/**
 * Simple URL Router
 *
 * Maps URI paths to controller actions.
 * Enforces CSRF protection on state-changing methods.
 */

namespace App;

use App\Middleware\CsrfMiddleware;

class Router
{
    private array $routes = [];
    private array $csrfExempt = [];

    /**
     * Register a GET route
     */
    public function get(string $path, string $controller, string $action): void
    {
        $this->routes['GET'][$path] = [$controller, $action];
    }

    /**
     * Register a POST route
     */
    public function post(string $path, string $controller, string $action): void
    {
        $this->routes['POST'][$path] = [$controller, $action];
    }

    /**
     * Mark a path as CSRF-exempt (e.g. OAuth callback)
     */
    public function csrfExempt(string $path): void
    {
        $this->csrfExempt[] = $path;
    }

    /**
     * Dispatch the current request to the matched controller action
     */
    public function dispatch(): void
    {
        $method = $_SERVER['REQUEST_METHOD'];
        $uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
        $uri = rtrim($uri, '/') ?: '/';

        // Exact match
        if (isset($this->routes[$method][$uri])) {
            [$controller, $action] = $this->routes[$method][$uri];
            $this->runWithCsrf($method, $uri, $controller, $action);
            return;
        }

        // Pattern match (simple :id style)
        foreach ($this->routes[$method] ?? [] as $pattern => [$ctrl, $act]) {
            $regex = preg_replace('#:([a-zA-Z_]+)#', '(?P<$1>[^/]+)', $pattern);
            $regex = '#^' . $regex . '$#';
            if (preg_match($regex, $uri, $matches)) {
                $_GET = array_merge($_GET, array_filter($matches, 'is_string', ARRAY_FILTER_USE_KEY));
                $this->runWithCsrf($method, $uri, $ctrl, $act);
                return;
            }
        }

        http_response_code(404);
        echo "404 — Not Found";
    }

    private function runWithCsrf(string $method, string $uri, string $controllerClass, string $action): void
    {
        if (in_array($method, ['POST', 'PUT', 'PATCH', 'DELETE']) && !$this->isCsrfExempt($uri)) {
            $csrf = new CsrfMiddleware();
            $csrf->handle(function () use ($controllerClass, $action) {
                $this->call($controllerClass, $action);
            });
        } else {
            $this->call($controllerClass, $action);
        }
    }

    private function isCsrfExempt(string $uri): bool
    {
        return in_array($uri, $this->csrfExempt, true);
    }

    private function call(string $controllerClass, string $action): void
    {
        if (!class_exists($controllerClass)) {
            http_response_code(500);
            echo "Controller not found: $controllerClass";
            return;
        }

        $controller = new $controllerClass();

        if (!method_exists($controller, $action)) {
            http_response_code(500);
            echo "Action not found: $controllerClass::$action";
            return;
        }

        $controller->$action();
    }
}
