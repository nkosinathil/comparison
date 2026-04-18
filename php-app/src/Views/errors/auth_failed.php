<?php $pageTitle = 'Authentication Failed'; ?>
<?php ob_start(); ?>

<div class="error-page">
    <h1>Authentication Failed</h1>
    <p><?= htmlspecialchars($error ?? 'An error occurred during authentication.') ?></p>
    <a href="/login" class="btn btn-primary">Try Again</a>
</div>

<?php $content = ob_get_clean(); ?>
<?php require __DIR__ . '/../layouts/app.php'; ?>
