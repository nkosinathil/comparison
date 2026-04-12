<?php
/**
 * Results Controller
 *
 * View and download comparison results.
 */

namespace App\Controllers;

use App\Repositories\JobRepository;
use App\Services\PythonApiClient;

class ResultsController extends Controller
{
    private JobRepository $jobRepo;
    private PythonApiClient $api;

    public function __construct()
    {
        parent::__construct();
        $this->jobRepo = new JobRepository();
        $this->api = new PythonApiClient();
    }

    /**
     * List completed results for the current user
     */
    public function index(): void
    {
        if (!$this->isAuthenticated()) {
            $this->session->set('redirect_after_login', '/results');
            $this->redirect('/login');
            return;
        }

        $user = $this->getUser();
        $results = $this->jobRepo->getResultsForUser($user['id']);

        $this->render('results/index', [
            'user' => $user,
            'results' => $results,
        ]);
    }

    /**
     * Show a single result detail page
     */
    public function show(): void
    {
        if (!$this->isAuthenticated()) {
            $this->redirect('/login');
            return;
        }

        $user = $this->getUser();
        $jobId = (int)$this->input('id');
        $job = $this->jobRepo->findJobById($jobId);

        if (!$job || (int)$job['user_id'] !== $user['id']) {
            $this->error404('Result not found');
            return;
        }

        $result = $this->jobRepo->getResultByJobId($jobId);

        $this->render('results/show', [
            'user' => $user,
            'job' => $job,
            'result' => $result,
        ]);
    }

    /**
     * Download results CSV
     */
    public function downloadCsv(): void
    {
        $this->downloadReport('csv');
    }

    /**
     * Download report HTML
     */
    public function downloadHtml(): void
    {
        $this->downloadReport('html');
    }

    private function downloadReport(string $type): void
    {
        if (!$this->isAuthenticated()) {
            $this->redirect('/login');
            return;
        }

        $user = $this->getUser();
        $jobId = (int)$this->input('id');
        $job = $this->jobRepo->findJobById($jobId);

        if (!$job || (int)$job['user_id'] !== $user['id']) {
            $this->error404('Result not found');
            return;
        }

        $result = $this->jobRepo->getResultByJobId($jobId);
        if (!$result) {
            $this->error404('No results available yet');
            return;
        }

        $key = $type === 'csv' ? $result['csv_minio_key'] : $result['html_minio_key'];
        if (!$key) {
            $this->error404("No $type report available");
            return;
        }

        $content = $this->api->downloadResult('results', $key);
        if ($content === null) {
            $this->error500("Failed to download $type report from storage");
            return;
        }

        $ext = $type === 'csv' ? 'csv' : 'html';
        $mime = $type === 'csv' ? 'text/csv' : 'text/html';
        $filename = "comparison_job_{$jobId}_results.{$ext}";

        header("Content-Type: $mime; charset=utf-8");
        header("Content-Disposition: attachment; filename=\"$filename\"");
        header('Content-Length: ' . strlen($content));
        echo $content;
        exit;
    }
}
