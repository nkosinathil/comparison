<?php
/**
 * Database Connection Manager
 * 
 * Provides PostgreSQL database connectivity.
 */

namespace App\Config;

use PDO;
use PDOException;

class Database
{
    private static ?Database $instance = null;
    private ?PDO $connection = null;
    private AppConfig $config;

    private function __construct()
    {
        $this->config = AppConfig::getInstance();
    }

    public static function getInstance(): Database
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    public function getConnection(): PDO
    {
        if ($this->connection === null) {
            $this->connect();
        }
        return $this->connection;
    }

    private function connect(): void
    {
        $dbConfig = $this->config->get('database');

        $dsn = sprintf(
            "pgsql:host=%s;port=%d;dbname=%s",
            $dbConfig['host'],
            $dbConfig['port'],
            $dbConfig['database']
        );

        try {
            $this->connection = new PDO(
                $dsn,
                $dbConfig['username'],
                $dbConfig['password'],
                [
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                    PDO::ATTR_EMULATE_PREPARES => false,
                ]
            );

            // Set schema if specified
            if (!empty($dbConfig['schema'])) {
                $this->connection->exec("SET search_path TO {$dbConfig['schema']}");
            }
        } catch (PDOException $e) {
            error_log("Database connection failed: " . $e->getMessage());
            throw new \RuntimeException("Database connection failed: " . $e->getMessage());
        }
    }

    public function beginTransaction(): bool
    {
        return $this->getConnection()->beginTransaction();
    }

    public function commit(): bool
    {
        return $this->getConnection()->commit();
    }

    public function rollBack(): bool
    {
        return $this->getConnection()->rollBack();
    }

    public function lastInsertId(string $name = null): string
    {
        return $this->getConnection()->lastInsertId($name);
    }

    /**
     * Close the database connection
     */
    public function close(): void
    {
        $this->connection = null;
    }

    /**
     * Test database connectivity
     */
    public static function testConnection(): bool
    {
        try {
            $db = self::getInstance();
            $conn = $db->getConnection();
            $stmt = $conn->query("SELECT 1");
            return $stmt !== false;
        } catch (\Exception $e) {
            error_log("Database test connection failed: " . $e->getMessage());
            return false;
        }
    }
}
