/**
 * Global application JavaScript
 */
document.addEventListener('DOMContentLoaded', function () {
    // Auto-dismiss alerts after 5 seconds
    document.querySelectorAll('.alert').forEach(function (el) {
        setTimeout(function () {
            el.style.transition = 'opacity 0.3s';
            el.style.opacity = '0';
            setTimeout(function () { el.remove(); }, 300);
        }, 5000);
    });
});

/**
 * Return the CSRF token from the <meta> tag.
 */
function getCsrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : '';
}
