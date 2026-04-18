<?php $pageTitle = '500 — Server Error'; ?>
<?php ob_start(); ?>

<div class="error-page">
    <h1>500</h1>
    <p><?= htmlspecialchars($message ?? 'An internal server error occurred.') ?></p>
    <a href="/dashboard" class="btn btn-primary">Go to Dashboard</a>
</div>

<?php $content = ob_get_clean(); ?>
<?php require __DIR__ . '/../layouts/app.php'; ?>
