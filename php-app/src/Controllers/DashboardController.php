<?php
/**
 * Dashboard Controller
 *
 * Landing page after login: shows recent jobs, system health, and quick actions.
 */

namespace App\Controllers;

use App\Repositories\JobRepository;
use App\Repositories\CaseRepository;
use App\Services\PythonApiClient;

class DashboardController extends Controller
{
    private JobRepository $jobRepo;
    private CaseRepository $caseRepo;

    public function __construct()
    {
        parent::__construct();
        $this->jobRepo = new JobRepository();
        $this->caseRepo = new CaseRepository();
    }

    public function index(): void
    {
        if (!$this->isAuthenticated()) {
            $this->session->set('redirect_after_login', '/dashboard');
            $this->redirect('/login');
            return;
        }

        $user = $this->getUser();
        $userId = $user['id'];

        $recentJobs = $this->jobRepo->getJobsByUser($userId, 10);
        $totalJobs = $this->jobRepo->countJobsByUser($userId);
        $cases = $this->caseRepo->getByUser($userId, 'active', 5);

        $pythonApi = new PythonApiClient();
        $backendHealth = $pythonApi->health();

        $this->render('dashboard/index', [
            'user' => $user,
            'recentJobs' => $recentJobs,
            'totalJobs' => $totalJobs,
            'cases' => $cases,
            'backendHealth' => $backendHealth,
        ]);
    }
}
