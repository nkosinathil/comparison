<?php $pageTitle = '403 — Access Denied'; ?>
<?php ob_start(); ?>

<div class="error-page">
    <h1>403</h1>
    <p><?= htmlspecialchars($message ?? 'You do not have permission to access this resource.') ?></p>
    <a href="/dashboard" class="btn btn-primary">Go to Dashboard</a>
</div>

<?php $content = ob_get_clean(); ?>
<?php require __DIR__ . '/../layouts/app.php'; ?>
