<?php
/**
 * Comparison Controller
 *
 * Handles the comparison workflow: create new comparison, upload files,
 * start processing, and poll status.
 */

namespace App\Controllers;

use App\Repositories\CaseRepository;
use App\Repositories\JobRepository;
use App\Repositories\AuditLogRepository;
use App\Services\PythonApiClient;

class ComparisonController extends Controller
{
    private CaseRepository $caseRepo;
    private JobRepository $jobRepo;
    private AuditLogRepository $auditRepo;
    private PythonApiClient $api;

    public function __construct()
    {
        parent::__construct();
        $this->caseRepo = new CaseRepository();
        $this->jobRepo = new JobRepository();
        $this->auditRepo = new AuditLogRepository();
        $this->api = new PythonApiClient();
    }

    /**
     * Show the new comparison form
     */
    public function create(): void
    {
        if (!$this->isAuthenticated()) {
            $this->session->set('redirect_after_login', '/comparison/new');
            $this->redirect('/login');
            return;
        }

        $user = $this->getUser();
        $cases = $this->caseRepo->getByUser($user['id']);

        $this->render('comparison/create', [
            'user' => $user,
            'cases' => $cases,
        ]);
    }

    /**
     * Handle file uploads (source + targets) via AJAX
     */
    public function upload(): void
    {
        if (!$this->isAuthenticated()) {
            $this->json(['error' => 'Unauthorized'], 401);
            return;
        }

        $user = $this->getUser();

        $caseName = $this->input('case_name', 'Comparison ' . date('Y-m-d H:i'));
        $caseId = (int)$this->input('case_id', 0);

        if ($caseId) {
            $case = $this->caseRepo->findById($caseId);
            if (!$case || (int)$case['user_id'] !== $user['id']) {
                $this->json(['error' => 'Case not found'], 404);
                return;
            }
        } else {
            $case = $this->caseRepo->create($user['id'], $caseName);
            if (!$case) {
                $this->json(['error' => 'Failed to create case'], 500);
                return;
            }
            $caseId = $case['id'];
        }

        $uploadType = $this->input('upload_type', 'target');
        $uploaded = [];

        $files = $_FILES['files'] ?? null;
        if (!$files || empty($files['name'])) {
            $this->json(['error' => 'No files uploaded'], 400);
            return;
        }

        $names = is_array($files['name']) ? $files['name'] : [$files['name']];
        $tmpNames = is_array($files['tmp_name']) ? $files['tmp_name'] : [$files['tmp_name']];
        $sizes = is_array($files['size']) ? $files['size'] : [$files['size']];
        $types = is_array($files['type']) ? $files['type'] : [$files['type']];

        foreach ($names as $i => $originalName) {
            $tmpPath = $tmpNames[$i];
            if (!is_uploaded_file($tmpPath)) {
                continue;
            }

            $sha256 = hash_file('sha256', $tmpPath);
            $objectKey = "{$caseId}/{$sha256}/{$originalName}";

            $result = $this->api->uploadFile($tmpPath, $originalName, 'uploads', $objectKey);

            if (!$result) {
                $uploaded[] = ['filename' => $originalName, 'error' => 'Upload to storage failed'];
                continue;
            }

            $upload = $this->jobRepo->createUpload([
                'case_id' => $caseId,
                'user_id' => $user['id'],
                'filename' => $result['object_key'] ?? $objectKey,
                'original_filename' => $originalName,
                'sha256' => $sha256,
                'minio_bucket' => $result['bucket'] ?? 'uploads',
                'minio_key' => $result['object_key'] ?? $objectKey,
                'upload_type' => $uploadType,
                'file_size' => $sizes[$i],
                'mime_type' => $types[$i],
            ]);

            $uploaded[] = [
                'upload_id' => $upload['id'] ?? null,
                'filename' => $originalName,
                'minio_key' => $result['object_key'] ?? $objectKey,
                'sha256' => $sha256,
            ];
        }

        $this->auditRepo->log(
            $user['id'],
            'upload',
            'case',
            $caseId,
            ['count' => count($uploaded), 'type' => $uploadType],
            $this->getClientIp(),
            $this->getUserAgent()
        );

        $this->json([
            'case_id' => $caseId,
            'uploads' => $uploaded,
        ]);
    }

    /**
     * Start a comparison job (AJAX)
     */
    public function start(): void
    {
        if (!$this->isAuthenticated()) {
            $this->json(['error' => 'Unauthorized'], 401);
            return;
        }

        $user = $this->getUser();
        $caseId = (int)$this->input('case_id');

        if (!$caseId) {
            $this->json(['error' => 'case_id is required'], 400);
            return;
        }

        $case = $this->caseRepo->findById($caseId);
        if (!$case || (int)$case['user_id'] !== $user['id']) {
            $this->json(['error' => 'Case not found'], 404);
            return;
        }

        $sourceUploads = $this->jobRepo->getUploadsByCase($caseId, 'source');
        $targetUploads = $this->jobRepo->getUploadsByCase($caseId, 'target');

        if (empty($sourceUploads)) {
            $this->json(['error' => 'No source file uploaded'], 400);
            return;
        }
        if (empty($targetUploads)) {
            $this->json(['error' => 'No target files uploaded'], 400);
            return;
        }

        $source = $sourceUploads[0];
        $targetKeys = array_map(fn($u) => $u['minio_key'], $targetUploads);

        $settings = [
            'compare_types' => $this->input('compare_types', ['all']),
            'use_semantic' => (bool)$this->input('use_semantic', false),
            'simhash_max_dist' => (int)$this->input('simhash_max_dist', 5),
            'jaccard_near_dup' => (float)$this->input('jaccard_near_dup', 0.50),
            'cosine_near_dup' => (float)$this->input('cosine_near_dup', 0.85),
            'semantic_threshold' => (float)$this->input('semantic_threshold', 0.90),
            'semantic_review_threshold' => (float)$this->input('semantic_review_threshold', 0.75),
        ];

        $job = $this->jobRepo->createJob(
            $caseId,
            $user['id'],
            $source['id'],
            $settings
        );

        if (!$job) {
            $this->json(['error' => 'Failed to create job'], 500);
            return;
        }

        $result = $this->api->submitJob(
            $job['id'],
            $source['minio_key'],
            $source['minio_bucket'],
            $targetKeys,
            'uploads',
            $settings
        );

        if (!$result) {
            $this->jobRepo->updateJobStatus($job['id'], 'failed', null, 'Failed to submit to processing engine');
            $this->json(['error' => 'Failed to submit job to processing engine'], 500);
            return;
        }

        $this->jobRepo->updateJobStatus($job['id'], 'queued', $result['task_id'] ?? null);

        $this->auditRepo->log(
            $user['id'],
            'job_create',
            'job',
            $job['id'],
            ['case_id' => $caseId, 'targets' => count($targetKeys)],
            $this->getClientIp(),
            $this->getUserAgent()
        );

        $this->json([
            'job_id' => $job['id'],
            'task_id' => $result['task_id'] ?? null,
            'status' => 'queued',
        ]);
    }

    /**
     * Poll job status (AJAX)
     */
    public function status(): void
    {
        if (!$this->isAuthenticated()) {
            $this->json(['error' => 'Unauthorized'], 401);
            return;
        }

        $user = $this->getUser();
        $jobId = (int)$this->input('id');
        $job = $this->jobRepo->findJobById($jobId);

        if (!$job || (int)$job['user_id'] !== $user['id']) {
            $this->json(['error' => 'Job not found'], 404);
            return;
        }

        $taskStatus = null;
        if ($job['task_id']) {
            $taskStatus = $this->api->taskStatus($job['task_id']);

            if ($taskStatus) {
                $state = $taskStatus['state'] ?? '';
                if ($state === 'SUCCESS' && $job['status'] !== 'completed') {
                    $this->jobRepo->updateJobStatus($job['id'], 'completed');
                    $job['status'] = 'completed';

                    $taskResult = $this->api->taskResult($job['task_id']);
                    if ($taskResult && isset($taskResult['result'])) {
                        $r = $taskResult['result'];
                        $this->jobRepo->createResult(
                            $job['id'],
                            $r['csv_key'] ?? '',
                            $r['html_key'] ?? '',
                            $r['summary'] ?? [],
                            $r['summary']['total_targets'] ?? 0
                        );
                    }
                } elseif ($state === 'FAILURE' && $job['status'] !== 'failed') {
                    $this->jobRepo->updateJobStatus(
                        $job['id'],
                        'failed',
                        null,
                        $taskStatus['error'] ?? 'Task failed'
                    );
                    $job['status'] = 'failed';
                }
            }
        }

        $this->json([
            'job_id' => $job['id'],
            'status' => $job['status'],
            'task_status' => $taskStatus,
        ]);
    }
}
