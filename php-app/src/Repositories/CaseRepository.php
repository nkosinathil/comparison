<?php
/**
 * Case Repository
 *
 * Data access for the cases (workspaces) table.
 */

namespace App\Repositories;

use App\Config\Database;
use PDO;

class CaseRepository
{
    private Database $db;

    public function __construct()
    {
        $this->db = Database::getInstance();
    }

    public function create(int $userId, string $name, string $description = ''): ?array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "INSERT INTO cases (user_id, name, description)
             VALUES (:user_id, :name, :description)
             RETURNING *"
        );
        $stmt->execute([
            'user_id' => $userId,
            'name' => $name,
            'description' => $description,
        ]);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    public function findById(int $id): ?array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare("SELECT * FROM cases WHERE id = :id");
        $stmt->execute(['id' => $id]);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    public function getByUser(int $userId, string $status = 'active', int $limit = 50, int $offset = 0): array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT * FROM cases
             WHERE user_id = :user_id AND status = :status
             ORDER BY updated_at DESC
             LIMIT :limit OFFSET :offset"
        );
        $stmt->bindValue('user_id', $userId, PDO::PARAM_INT);
        $stmt->bindValue('status', $status);
        $stmt->bindValue('limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue('offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    public function countByUser(int $userId, string $status = 'active'): int
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT COUNT(*) FROM cases WHERE user_id = :user_id AND status = :status"
        );
        $stmt->execute(['user_id' => $userId, 'status' => $status]);
        return (int)$stmt->fetchColumn();
    }

    public function archive(int $id): bool
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare("UPDATE cases SET status = 'archived' WHERE id = :id");
        return $stmt->execute(['id' => $id]);
    }
}
