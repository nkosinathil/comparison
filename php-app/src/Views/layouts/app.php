<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= htmlspecialchars($pageTitle ?? 'File Comparison') ?></title>
    <link rel="stylesheet" href="/css/app.css">
</head>
<body>
    <nav class="navbar">
        <div class="container nav-inner">
            <a href="/dashboard" class="nav-brand">File Comparison</a>
            <?php if (isset($user) && $user): ?>
            <div class="nav-links">
                <a href="/dashboard">Dashboard</a>
                <a href="/comparison/new">New Comparison</a>
                <a href="/results">Results</a>
                <span class="nav-user"><?= htmlspecialchars($user['name'] ?? $user['email']) ?></span>
                <a href="/logout" class="btn btn-sm btn-outline">Logout</a>
            </div>
            <?php endif; ?>
        </div>
    </nav>

    <main class="container main-content">
        <?php if (!empty($flash)): ?>
        <div class="alert alert-<?= htmlspecialchars($flash['type'] ?? 'info') ?>">
            <?= htmlspecialchars($flash['message'] ?? '') ?>
        </div>
        <?php endif; ?>

        <?= $content ?? '' ?>
    </main>

    <footer class="footer">
        <div class="container">
            <p>&copy; <?= date('Y') ?> File Comparison Web Application</p>
        </div>
    </footer>

    <script src="/js/app.js"></script>
</body>
</html>
