<?php $pageTitle = 'Dashboard'; ?>
<?php ob_start(); ?>

<div class="page-header">
    <h1>Dashboard</h1>
    <a href="/comparison/new" class="btn btn-primary">New Comparison</a>
</div>

<!-- Stats cards -->
<div class="stats-grid">
    <div class="stat-card">
        <div class="stat-value"><?= (int)($totalJobs ?? 0) ?></div>
        <div class="stat-label">Total Jobs</div>
    </div>
    <div class="stat-card">
        <div class="stat-value"><?= count($cases ?? []) ?></div>
        <div class="stat-label">Active Cases</div>
    </div>
    <div class="stat-card">
        <div class="stat-value <?= ($backendHealth['status'] ?? '') === 'healthy' ? 'text-green' : 'text-red' ?>">
            <?= htmlspecialchars($backendHealth['status'] ?? 'unknown') ?>
        </div>
        <div class="stat-label">Backend Status</div>
    </div>
</div>

<!-- Recent Jobs -->
<section class="card">
    <div class="card-header">
        <h2>Recent Jobs</h2>
    </div>
    <div class="card-body">
        <?php if (empty($recentJobs)): ?>
            <p class="text-muted">No jobs yet. <a href="/comparison/new">Start your first comparison.</a></p>
        <?php else: ?>
        <table class="table">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Case</th>
                    <th>Source</th>
                    <th>Status</th>
                    <th>Created</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($recentJobs as $job): ?>
                <tr>
                    <td>#<?= (int)$job['id'] ?></td>
                    <td><?= htmlspecialchars($job['case_name'] ?? '—') ?></td>
                    <td><?= htmlspecialchars($job['source_filename'] ?? '—') ?></td>
                    <td><span class="badge badge-<?= htmlspecialchars($job['status']) ?>"><?= htmlspecialchars($job['status']) ?></span></td>
                    <td><?= htmlspecialchars(substr($job['created_at'] ?? '', 0, 16)) ?></td>
                    <td>
                        <?php if ($job['status'] === 'completed'): ?>
                            <a href="/results/<?= (int)$job['id'] ?>" class="btn btn-sm">View</a>
                        <?php elseif (in_array($job['status'], ['pending', 'queued', 'processing'])): ?>
                            <a href="/comparison/<?= (int)$job['id'] ?>/status" class="btn btn-sm">Track</a>
                        <?php else: ?>
                            —
                        <?php endif; ?>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>
    </div>
</section>

<?php $content = ob_get_clean(); ?>
<?php require __DIR__ . '/../layouts/app.php'; ?>
