<?php
/**
 * Audit Log Repository
 * 
 * Handles security audit logging.
 * Column mapping matches database/schema.sql:
 *   audit_logs(id, user_id, action, resource_type, resource_id, details, ip_address, user_agent, created_at)
 */

namespace App\Repositories;

use App\Config\Database;
use PDO;

class AuditLogRepository
{
    private Database $db;

    public function __construct()
    {
        $this->db = Database::getInstance();
    }

    /**
     * Log an audit event
     */
    public function log(
        ?int $userId,
        string $action,
        string $resourceType,
        ?int $resourceId = null,
        ?array $details = null,
        ?string $ipAddress = null,
        ?string $userAgent = null
    ): bool {
        $conn = $this->db->getConnection();

        $stmt = $conn->prepare(
            "INSERT INTO audit_logs 
             (user_id, action, resource_type, resource_id, details, ip_address, user_agent)
             VALUES 
             (:user_id, :action, :resource_type, :resource_id, :details::jsonb, :ip_address, :user_agent)"
        );

        return $stmt->execute([
            'user_id' => $userId,
            'action' => $action,
            'resource_type' => $resourceType,
            'resource_id' => $resourceId,
            'details' => $details ? json_encode($details) : null,
            'ip_address' => $ipAddress,
            'user_agent' => $userAgent,
        ]);
    }

    /**
     * Log user login
     */
    public function logLogin(int $userId, string $ipAddress, string $userAgent): bool
    {
        return $this->log(
            $userId,
            'login',
            'user',
            $userId,
            null,
            $ipAddress,
            $userAgent
        );
    }

    /**
     * Log user logout
     */
    public function logLogout(int $userId, string $ipAddress, string $userAgent): bool
    {
        return $this->log(
            $userId,
            'logout',
            'user',
            $userId,
            null,
            $ipAddress,
            $userAgent
        );
    }

    /**
     * Log failed login attempt
     */
    public function logFailedLogin(string $email, string $reason, string $ipAddress, string $userAgent): bool
    {
        return $this->log(
            null,
            'failed_login',
            'user',
            null,
            ['email' => $email, 'reason' => $reason],
            $ipAddress,
            $userAgent
        );
    }

    /**
     * Get audit logs for a user
     */
    public function getByUser(int $userId, int $limit = 100, int $offset = 0): array
    {
        $conn = $this->db->getConnection();

        $stmt = $conn->prepare(
            "SELECT * FROM audit_logs
             WHERE user_id = :user_id
             ORDER BY created_at DESC
             LIMIT :limit OFFSET :offset"
        );

        $stmt->bindValue('user_id', $userId, PDO::PARAM_INT);
        $stmt->bindValue('limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue('offset', $offset, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * Get recent audit logs (for admin)
     */
    public function getRecent(int $limit = 100, int $offset = 0): array
    {
        $conn = $this->db->getConnection();

        $stmt = $conn->prepare(
            "SELECT a.*, u.email, u.name
             FROM audit_logs a
             LEFT JOIN users u ON a.user_id = u.id
             ORDER BY a.created_at DESC
             LIMIT :limit OFFSET :offset"
        );

        $stmt->bindValue('limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue('offset', $offset, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * Get audit logs by action
     */
    public function getByAction(string $action, int $limit = 100, int $offset = 0): array
    {
        $conn = $this->db->getConnection();

        $stmt = $conn->prepare(
            "SELECT * FROM audit_logs
             WHERE action = :action
             ORDER BY created_at DESC
             LIMIT :limit OFFSET :offset"
        );

        $stmt->bindValue('action', $action);
        $stmt->bindValue('limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue('offset', $offset, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * Count audit logs
     */
    public function count(?int $userId = null): int
    {
        $conn = $this->db->getConnection();

        if ($userId !== null) {
            $stmt = $conn->prepare("SELECT COUNT(*) FROM audit_logs WHERE user_id = :user_id");
            $stmt->execute(['user_id' => $userId]);
        } else {
            $stmt = $conn->query("SELECT COUNT(*) FROM audit_logs");
        }

        return (int)$stmt->fetchColumn();
    }
}
