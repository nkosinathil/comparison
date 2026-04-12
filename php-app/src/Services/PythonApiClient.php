<?php
/**
 * Python API Client
 *
 * Communicates with the FastAPI backend on the Python processing server.
 */

namespace App\Services;

use App\Config\AppConfig;
use GuzzleHttp\Client;
use GuzzleHttp\Exception\GuzzleException;
use Psr\Http\Message\ResponseInterface;

class PythonApiClient
{
    private Client $http;
    private string $baseUrl;

    public function __construct()
    {
        $config = AppConfig::getInstance();
        $this->baseUrl = rtrim($config->get('python_api.url', 'http://192.168.1.90:8000'), '/');
        $timeout = (int)$config->get('python_api.timeout', 30);

        $this->http = new Client([
            'base_uri' => $this->baseUrl,
            'timeout' => $timeout,
            'http_errors' => false,
        ]);
    }

    // ------------------------------------------------------------------
    // Health
    // ------------------------------------------------------------------

    public function health(): ?array
    {
        return $this->getJson('/health');
    }

    public function healthDetailed(): ?array
    {
        return $this->getJson('/health/detailed');
    }

    // ------------------------------------------------------------------
    // Upload
    // ------------------------------------------------------------------

    /**
     * Upload a file to MinIO via the Python API.
     *
     * @param string $filePath   Local temp path of the uploaded file
     * @param string $filename   Original filename
     * @param string $bucket     Target MinIO bucket
     * @param string $objectKey  Desired object key
     */
    public function uploadFile(
        string $filePath,
        string $filename,
        string $bucket = 'uploads',
        string $objectKey = ''
    ): ?array {
        try {
            $multipart = [
                [
                    'name' => 'file',
                    'contents' => fopen($filePath, 'r'),
                    'filename' => $filename,
                ],
                ['name' => 'bucket', 'contents' => $bucket],
            ];

            if ($objectKey) {
                $multipart[] = ['name' => 'object_key', 'contents' => $objectKey];
            }

            $response = $this->http->post('/api/upload', [
                'multipart' => $multipart,
            ]);

            return $this->decode($response);
        } catch (GuzzleException $e) {
            error_log("PythonApiClient::uploadFile failed: " . $e->getMessage());
            return null;
        }
    }

    // ------------------------------------------------------------------
    // Process (submit comparison job)
    // ------------------------------------------------------------------

    /**
     * Submit a comparison job to the Celery task queue.
     */
    public function submitJob(
        int $jobId,
        string $sourceMiniKey,
        string $sourceBucket,
        array $targetMinioKeys,
        string $targetBucket,
        array $settings = []
    ): ?array {
        return $this->postJson('/api/process', [
            'job_id' => $jobId,
            'source_minio_key' => $sourceMiniKey,
            'source_bucket' => $sourceBucket,
            'target_minio_keys' => $targetMinioKeys,
            'target_bucket' => $targetBucket,
            'settings' => $settings,
        ]);
    }

    /**
     * Cancel a running job.
     */
    public function cancelJob(string $taskId): ?array
    {
        return $this->postJson("/api/process/{$taskId}/cancel", []);
    }

    // ------------------------------------------------------------------
    // Task status
    // ------------------------------------------------------------------

    public function taskStatus(string $taskId): ?array
    {
        return $this->getJson("/api/tasks/{$taskId}/status");
    }

    public function taskResult(string $taskId): ?array
    {
        return $this->getJson("/api/tasks/{$taskId}/result");
    }

    // ------------------------------------------------------------------
    // Results / downloads
    // ------------------------------------------------------------------

    /**
     * Get a presigned URL for a MinIO object.
     */
    public function presignedUrl(string $bucket, string $objectKey): ?string
    {
        $data = $this->getJson("/api/results/presigned-url", [
            'bucket' => $bucket,
            'object_key' => $objectKey,
        ]);

        return $data['url'] ?? null;
    }

    /**
     * Stream a result file (CSV or HTML) through the Python API.
     */
    public function downloadResult(string $bucket, string $objectKey): ?string
    {
        try {
            $response = $this->http->get("/api/results/download", [
                'query' => [
                    'bucket' => $bucket,
                    'object_key' => $objectKey,
                ],
            ]);

            if ($response->getStatusCode() === 200) {
                return $response->getBody()->getContents();
            }
            return null;
        } catch (GuzzleException $e) {
            error_log("PythonApiClient::downloadResult failed: " . $e->getMessage());
            return null;
        }
    }

    // ------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------

    private function getJson(string $path, array $query = []): ?array
    {
        try {
            $options = $query ? ['query' => $query] : [];
            $response = $this->http->get($path, $options);
            return $this->decode($response);
        } catch (GuzzleException $e) {
            error_log("PythonApiClient GET $path failed: " . $e->getMessage());
            return null;
        }
    }

    private function postJson(string $path, array $body): ?array
    {
        try {
            $response = $this->http->post($path, [
                'json' => $body,
            ]);
            return $this->decode($response);
        } catch (GuzzleException $e) {
            error_log("PythonApiClient POST $path failed: " . $e->getMessage());
            return null;
        }
    }

    private function decode(ResponseInterface $response): ?array
    {
        $code = $response->getStatusCode();
        $body = $response->getBody()->getContents();

        if ($code >= 200 && $code < 300) {
            return json_decode($body, true) ?? [];
        }

        error_log("PythonApiClient response $code: $body");
        return null;
    }
}
