<?php
/**
 * User Repository
 * 
 * Handles user data access and Keycloak user synchronization.
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
            "SELECT * FROM users WHERE user_id = :id"
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
     * Create or update user from Keycloak data
     */
    public function syncFromKeycloak(array $keycloakData): ?array
    {
        $conn = $this->db->getConnection();

        // Extract user data
        $sub = $keycloakData['sub'] ?? null;
        $email = $keycloakData['email'] ?? null;
        $username = $keycloakData['preferred_username'] ?? $email;
        $firstName = $keycloakData['given_name'] ?? '';
        $lastName = $keycloakData['family_name'] ?? '';
        $fullName = trim($firstName . ' ' . $lastName);
        
        if (empty($fullName)) {
            $fullName = $username;
        }

        if (!$sub || !$email) {
            error_log("Invalid Keycloak data: missing sub or email");
            return null;
        }

        // Check if user exists
        $existingUser = $this->findByKeycloakSub($sub);

        if ($existingUser) {
            // Update existing user
            $stmt = $conn->prepare(
                "UPDATE users 
                 SET email = :email,
                     username = :username,
                     full_name = :full_name,
                     last_login = NOW()
                 WHERE keycloak_sub = :sub
                 RETURNING *"
            );

            $stmt->execute([
                'email' => $email,
                'username' => $username,
                'full_name' => $fullName,
                'sub' => $sub,
            ]);
        } else {
            // Create new user
            $stmt = $conn->prepare(
                "INSERT INTO users (keycloak_sub, email, username, full_name, last_login)
                 VALUES (:sub, :email, :username, :full_name, NOW())
                 RETURNING *"
            );

            $stmt->execute([
                'sub' => $sub,
                'email' => $email,
                'username' => $username,
                'full_name' => $fullName,
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
            "UPDATE users SET last_login = NOW() WHERE user_id = :user_id"
        );
        return $stmt->execute(['user_id' => $userId]);
    }

    /**
     * Get user preferences
     */
    public function getPreferences(int $userId): array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT * FROM user_preferences WHERE user_id = :user_id"
        );
        $stmt->execute(['user_id' => $userId]);
        $prefs = $stmt->fetch(PDO::FETCH_ASSOC);

        return $prefs ?: [];
    }

    /**
     * Update user preferences
     */
    public function updatePreferences(int $userId, array $preferences): bool
    {
        $conn = $this->db->getConnection();

        // Check if preferences exist
        $existing = $this->getPreferences($userId);

        $settingsJson = json_encode($preferences);

        if ($existing) {
            $stmt = $conn->prepare(
                "UPDATE user_preferences 
                 SET settings = :settings::jsonb
                 WHERE user_id = :user_id"
            );
        } else {
            $stmt = $conn->prepare(
                "INSERT INTO user_preferences (user_id, settings)
                 VALUES (:user_id, :settings::jsonb)"
            );
        }

        return $stmt->execute([
            'user_id' => $userId,
            'settings' => $settingsJson,
        ]);
    }

    /**
     * Get all users (for admin)
     */
    public function getAll(int $limit = 100, int $offset = 0): array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT user_id, email, username, full_name, created_at, last_login
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
