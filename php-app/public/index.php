<?php
/**
 * Application Entry Point
 *
 * All HTTP requests are routed through this file (via Apache/Nginx rewrite rules).
 */

require_once __DIR__ . '/../vendor/autoload.php';

use App\Config\AppConfig;
use App\Router;
use App\Controllers\AuthController;
use App\Controllers\DashboardController;
use App\Controllers\ComparisonController;
use App\Controllers\ResultsController;

// Bootstrap configuration (loads .env)
AppConfig::getInstance();

// Set up error reporting based on environment
if (AppConfig::getInstance()->get('app.debug')) {
    error_reporting(E_ALL);
    ini_set('display_errors', '1');
} else {
    error_reporting(0);
    ini_set('display_errors', '0');
}

$router = new Router();

// --- Auth routes ---
$router->get('/login', AuthController::class, 'login');
$router->get('/auth/callback', AuthController::class, 'callback');
$router->get('/logout', AuthController::class, 'logout');

// --- Dashboard ---
$router->get('/', DashboardController::class, 'index');
$router->get('/dashboard', DashboardController::class, 'index');

// --- Comparison workflow ---
$router->get('/comparison/new', ComparisonController::class, 'create');
$router->post('/comparison/upload', ComparisonController::class, 'upload');
$router->post('/comparison/start', ComparisonController::class, 'start');
$router->get('/comparison/:id/status', ComparisonController::class, 'status');

// --- Results ---
$router->get('/results', ResultsController::class, 'index');
$router->get('/results/:id', ResultsController::class, 'show');
$router->get('/results/:id/download/csv', ResultsController::class, 'downloadCsv');
$router->get('/results/:id/download/html', ResultsController::class, 'downloadHtml');

// Dispatch
$router->dispatch();
