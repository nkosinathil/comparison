<?php $pageTitle = 'Results'; ?>
<?php ob_start(); ?>

<div class="page-header">
    <h1>Comparison Results</h1>
</div>

<div class="card">
    <div class="card-body">
        <?php if (empty($results)): ?>
            <p class="text-muted">No completed comparisons yet.</p>
        <?php else: ?>
        <table class="table">
            <thead>
                <tr>
                    <th>Job</th>
                    <th>Case</th>
                    <th>Source</th>
                    <th>Targets</th>
                    <th>Summary</th>
                    <th>Date</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($results as $r): ?>
                <?php $summary = json_decode($r['summary'] ?? '{}', true); ?>
                <tr>
                    <td>#<?= (int)$r['job_id'] ?></td>
                    <td><?= htmlspecialchars($r['case_name'] ?? '—') ?></td>
                    <td><?= htmlspecialchars($r['source_filename'] ?? '—') ?></td>
                    <td><?= (int)($r['result_count'] ?? 0) ?></td>
                    <td>
                        <?php if ($summary): ?>
                        <span class="badge badge-completed"><?= (int)($summary['identical'] ?? 0) ?> identical</span>
                        <span class="badge badge-processing"><?= (int)($summary['near_duplicate'] ?? 0) ?> near-dup</span>
                        <span class="badge badge-failed"><?= (int)($summary['unrelated'] ?? 0) ?> unrelated</span>
                        <?php else: ?>
                        —
                        <?php endif; ?>
                    </td>
                    <td><?= htmlspecialchars(substr($r['created_at'] ?? '', 0, 16)) ?></td>
                    <td>
                        <a href="/results/<?= (int)$r['job_id'] ?>" class="btn btn-sm">View</a>
                        <a href="/results/<?= (int)$r['job_id'] ?>/download/csv" class="btn btn-sm btn-outline">CSV</a>
                        <a href="/results/<?= (int)$r['job_id'] ?>/download/html" class="btn btn-sm btn-outline">HTML</a>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>
    </div>
</div>

<?php $content = ob_get_clean(); ?>
<?php require __DIR__ . '/../layouts/app.php'; ?>
