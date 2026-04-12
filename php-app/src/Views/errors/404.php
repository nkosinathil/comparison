<?php $pageTitle = '404 — Not Found'; ?>
<?php ob_start(); ?>

<div class="error-page">
    <h1>404</h1>
    <p><?= htmlspecialchars($message ?? 'The page you requested could not be found.') ?></p>
    <a href="/dashboard" class="btn btn-primary">Go to Dashboard</a>
</div>

<?php $content = ob_get_clean(); ?>
<?php require __DIR__ . '/../layouts/app.php'; ?>
