<?php $pageTitle = 'Result Detail'; ?>
<?php ob_start(); ?>

<?php $summary = json_decode($result['summary'] ?? '{}', true); ?>

<div class="page-header">
    <h1>Job #<?= (int)$job['id'] ?> — Results</h1>
    <div>
        <a href="/results/<?= (int)$job['id'] ?>/download/csv" class="btn btn-outline">Download CSV</a>
        <a href="/results/<?= (int)$job['id'] ?>/download/html" class="btn btn-outline">Download HTML Report</a>
        <a href="/results" class="btn btn-sm">Back to List</a>
    </div>
</div>

<div class="stats-grid">
    <div class="stat-card">
        <div class="stat-value"><?= (int)($summary['total_targets'] ?? $result['result_count'] ?? 0) ?></div>
        <div class="stat-label">Total Targets</div>
    </div>
    <div class="stat-card">
        <div class="stat-value text-green"><?= (int)($summary['identical'] ?? 0) ?></div>
        <div class="stat-label">Identical</div>
    </div>
    <div class="stat-card">
        <div class="stat-value"><?= (int)($summary['content_duplicate'] ?? 0) ?></div>
        <div class="stat-label">Content Duplicate</div>
    </div>
    <div class="stat-card">
        <div class="stat-value"><?= (int)($summary['near_duplicate'] ?? 0) ?></div>
        <div class="stat-label">Near Duplicate</div>
    </div>
    <div class="stat-card">
        <div class="stat-value"><?= (int)($summary['unrelated'] ?? 0) ?></div>
        <div class="stat-label">Unrelated</div>
    </div>
    <div class="stat-card">
        <div class="stat-value text-red"><?= (int)($summary['errors'] ?? 0) ?></div>
        <div class="stat-label">Errors</div>
    </div>
</div>

<div class="card">
    <div class="card-header"><h2>Job Details</h2></div>
    <div class="card-body">
        <dl class="detail-list">
            <dt>Status</dt>
            <dd><span class="badge badge-<?= htmlspecialchars($job['status']) ?>"><?= htmlspecialchars($job['status']) ?></span></dd>

            <dt>Created</dt>
            <dd><?= htmlspecialchars($job['created_at'] ?? '') ?></dd>

            <dt>Started</dt>
            <dd><?= htmlspecialchars($job['started_at'] ?? '—') ?></dd>

            <dt>Completed</dt>
            <dd><?= htmlspecialchars($job['completed_at'] ?? '—') ?></dd>

            <?php $settings = json_decode($job['settings'] ?? '{}', true); ?>
            <?php if ($settings): ?>
            <dt>Compare Types</dt>
            <dd><?= htmlspecialchars(implode(', ', (array)($settings['compare_types'] ?? ['all']))) ?></dd>

            <dt>Semantic</dt>
            <dd><?= !empty($settings['use_semantic']) ? 'Yes' : 'No' ?></dd>
            <?php endif; ?>
        </dl>
    </div>
</div>

<?php if ($result && $result['html_minio_key']): ?>
<div class="card">
    <div class="card-header"><h2>Embedded Report</h2></div>
    <div class="card-body">
        <p>The full interactive HTML report is available for download above. A summary of the data is shown in the stats cards.</p>
    </div>
</div>
<?php endif; ?>

<?php $content = ob_get_clean(); ?>
<?php require __DIR__ . '/../layouts/app.php'; ?>
