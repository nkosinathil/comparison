<?php
/**
 * Job Repository
 *
 * Data access for the jobs, uploads, and results tables.
 */

namespace App\Repositories;

use App\Config\Database;
use PDO;

class JobRepository
{
    private Database $db;

    public function __construct()
    {
        $this->db = Database::getInstance();
    }

    // ------------------------------------------------------------------
    // Uploads
    // ------------------------------------------------------------------

    public function createUpload(array $data): ?array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "INSERT INTO uploads
                (case_id, user_id, filename, original_filename, sha256, minio_bucket, minio_key, upload_type, file_size, mime_type)
             VALUES
                (:case_id, :user_id, :filename, :original_filename, :sha256, :minio_bucket, :minio_key, :upload_type, :file_size, :mime_type)
             RETURNING *"
        );
        $stmt->execute($data);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    public function getUploadsByCase(int $caseId, ?string $uploadType = null): array
    {
        $conn = $this->db->getConnection();
        $sql = "SELECT * FROM uploads WHERE case_id = :case_id";
        $params = ['case_id' => $caseId];

        if ($uploadType) {
            $sql .= " AND upload_type = :upload_type";
            $params['upload_type'] = $uploadType;
        }

        $sql .= " ORDER BY uploaded_at DESC";
        $stmt = $conn->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    // ------------------------------------------------------------------
    // Jobs
    // ------------------------------------------------------------------

    public function createJob(int $caseId, int $userId, int $sourceUploadId, array $settings): ?array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "INSERT INTO jobs (case_id, user_id, source_upload_id, settings, status)
             VALUES (:case_id, :user_id, :source_upload_id, :settings::jsonb, 'pending')
             RETURNING *"
        );
        $stmt->execute([
            'case_id' => $caseId,
            'user_id' => $userId,
            'source_upload_id' => $sourceUploadId,
            'settings' => json_encode($settings),
        ]);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    public function findJobById(int $id): ?array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare("SELECT * FROM jobs WHERE id = :id");
        $stmt->execute(['id' => $id]);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    public function updateJobStatus(int $id, string $status, ?string $taskId = null, ?string $error = null): bool
    {
        $conn = $this->db->getConnection();

        $sets = ["status = :status"];
        $params = ['id' => $id, 'status' => $status];

        if ($taskId !== null) {
            $sets[] = "task_id = :task_id";
            $params['task_id'] = $taskId;
        }
        if ($error !== null) {
            $sets[] = "error_message = :error_message";
            $params['error_message'] = $error;
        }
        if ($status === 'processing') {
            $sets[] = "started_at = NOW()";
        }
        if (in_array($status, ['completed', 'failed', 'cancelled'])) {
            $sets[] = "completed_at = NOW()";
        }

        $sql = "UPDATE jobs SET " . implode(', ', $sets) . " WHERE id = :id";
        $stmt = $conn->prepare($sql);
        return $stmt->execute($params);
    }

    public function getJobsByUser(int $userId, int $limit = 50, int $offset = 0): array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT j.*, c.name AS case_name, u.original_filename AS source_filename
             FROM jobs j
             LEFT JOIN cases c ON j.case_id = c.id
             LEFT JOIN uploads u ON j.source_upload_id = u.id
             WHERE j.user_id = :user_id
             ORDER BY j.created_at DESC
             LIMIT :limit OFFSET :offset"
        );
        $stmt->bindValue('user_id', $userId, PDO::PARAM_INT);
        $stmt->bindValue('limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue('offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    public function countJobsByUser(int $userId): int
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare("SELECT COUNT(*) FROM jobs WHERE user_id = :user_id");
        $stmt->execute(['user_id' => $userId]);
        return (int)$stmt->fetchColumn();
    }

    // ------------------------------------------------------------------
    // Results
    // ------------------------------------------------------------------

    public function createResult(int $jobId, string $csvKey, string $htmlKey, array $summary, int $resultCount): ?array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "INSERT INTO results (job_id, csv_minio_key, html_minio_key, summary, result_count)
             VALUES (:job_id, :csv_key, :html_key, :summary::jsonb, :result_count)
             RETURNING *"
        );
        $stmt->execute([
            'job_id' => $jobId,
            'csv_key' => $csvKey,
            'html_key' => $htmlKey,
            'summary' => json_encode($summary),
            'result_count' => $resultCount,
        ]);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    public function getResultByJobId(int $jobId): ?array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare("SELECT * FROM results WHERE job_id = :job_id");
        $stmt->execute(['job_id' => $jobId]);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    public function getResultsForUser(int $userId, int $limit = 50, int $offset = 0): array
    {
        $conn = $this->db->getConnection();
        $stmt = $conn->prepare(
            "SELECT r.*, j.task_id, j.status AS job_status, j.created_at AS job_created_at,
                    c.name AS case_name, u.original_filename AS source_filename
             FROM results r
             JOIN jobs j ON r.job_id = j.id
             LEFT JOIN cases c ON j.case_id = c.id
             LEFT JOIN uploads u ON j.source_upload_id = u.id
             WHERE j.user_id = :user_id
             ORDER BY r.created_at DESC
             LIMIT :limit OFFSET :offset"
        );
        $stmt->bindValue('user_id', $userId, PDO::PARAM_INT);
        $stmt->bindValue('limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue('offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
}
