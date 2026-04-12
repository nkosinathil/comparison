<?php
/**
 * User Repository
 * 
 * Handles user data access and Keycloak user synchronization.
 * Column mapping matches database/schema.sql:
 *   users(id, keycloak_sub, email, name, roles, created_at, last_login, is_active)
 *   user_preferences(id, user_id, preference_key, preference_value, updated_at)
 */

namespace App\Repositories;

use App\Config\Database;
use PDO;

class UserRepository
{
    private Database $db;

    public function __construct()
    {
        $this->db = Database::getInstance();
    }

    /**
     * Find user by Keycloak subject ID
     */
    public function findByKeycloakSub(string $sub): ?array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT * FROM users WHERE keycloak_sub = :sub"
        );
        $stmt->execute(['sub' => $sub]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        return $user ?: null;
    }

    /**
     * Find user by ID
     */
    public function findById(int $id): ?array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT * FROM users WHERE id = :id"
        );
        $stmt->execute(['id' => $id]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        return $user ?: null;
    }

    /**
     * Find user by email
     */
    public function findByEmail(string $email): ?array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT * FROM users WHERE email = :email"
        );
        $stmt->execute(['email' => $email]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        return $user ?: null;
    }

    /**
     * Create or update user from Keycloak data.
     * Maps Keycloak claims to schema columns:
     *   sub           -> keycloak_sub
     *   email         -> email
     *   given_name + family_name (or preferred_username) -> name
     *   realm_access.roles (if present) -> roles (TEXT[])
     */
    public function syncFromKeycloak(array $keycloakData): ?array
    {
        $conn = $this->db->getConnection();

        $sub = $keycloakData['sub'] ?? null;
        $email = $keycloakData['email'] ?? null;
        $firstName = $keycloakData['given_name'] ?? '';
        $lastName = $keycloakData['family_name'] ?? '';
        $name = trim($firstName . ' ' . $lastName);

        if (empty($name)) {
            $name = $keycloakData['preferred_username'] ?? $email;
        }

        if (!$sub || !$email) {
            error_log("Invalid Keycloak data: missing sub or email");
            return null;
        }

        $roles = [];
        if (isset($keycloakData['realm_access']['roles'])) {
            $roles = $keycloakData['realm_access']['roles'];
        }
        $rolesLiteral = '{' . implode(',', array_map(fn($r) => '"' . $r . '"', $roles)) . '}';

        $existingUser = $this->findByKeycloakSub($sub);

        if ($existingUser) {
            $stmt = $conn->prepare(
                "UPDATE users 
                 SET email = :email,
                     name = :name,
                     roles = :roles,
                     last_login = NOW()
                 WHERE keycloak_sub = :sub
                 RETURNING *"
            );

            $stmt->execute([
                'email' => $email,
                'name' => $name,
                'roles' => $rolesLiteral,
                'sub' => $sub,
            ]);
        } else {
            $stmt = $conn->prepare(
                "INSERT INTO users (keycloak_sub, email, name, roles, last_login)
                 VALUES (:sub, :email, :name, :roles, NOW())
                 RETURNING *"
            );

            $stmt->execute([
                'sub' => $sub,
                'email' => $email,
                'name' => $name,
                'roles' => $rolesLiteral,
            ]);
        }

        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        return $user ?: null;
    }

    /**
     * Update last login timestamp
     */
    public function updateLastLogin(int $userId): bool
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "UPDATE users SET last_login = NOW() WHERE id = :id"
        );
        return $stmt->execute(['id' => $userId]);
    }

    /**
     * Get user preferences as key-value array.
     * Schema stores preferences as individual rows (preference_key, preference_value).
     */
    public function getPreferences(int $userId): array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT preference_key, preference_value FROM user_preferences WHERE user_id = :user_id"
        );
        $stmt->execute(['user_id' => $userId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $prefs = [];
        foreach ($rows as $row) {
            $prefs[$row['preference_key']] = $row['preference_value'];
        }
        return $prefs;
    }

    /**
     * Update user preferences (upsert individual key-value pairs)
     */
    public function updatePreferences(int $userId, array $preferences): bool
    {
        $conn = $this->db->getConnection();

        $stmt = $conn->prepare(
            "INSERT INTO user_preferences (user_id, preference_key, preference_value, updated_at)
             VALUES (:user_id, :key, :value, NOW())
             ON CONFLICT (user_id, preference_key)
             DO UPDATE SET preference_value = EXCLUDED.preference_value, updated_at = NOW()"
        );

        foreach ($preferences as $key => $value) {
            $stmt->execute([
                'user_id' => $userId,
                'key' => $key,
                'value' => is_array($value) ? json_encode($value) : (string)$value,
            ]);
        }

        return true;
    }

    /**
     * Get all users (for admin)
     */
    public function getAll(int $limit = 100, int $offset = 0): array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT id, email, name, roles, created_at, last_login, is_active
             FROM users
             ORDER BY created_at DESC
             LIMIT :limit OFFSET :offset"
        );
        $stmt->bindValue('limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue('offset', $offset, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * Count total users
     */
    public function count(): int
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->query("SELECT COUNT(*) FROM users");
        return (int)$stmt->fetchColumn();
    }
}
