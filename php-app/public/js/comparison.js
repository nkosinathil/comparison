/**
 * Comparison page — file uploads, job submission, and progress polling.
 *
 * Depends on getCsrfToken() from app.js (loaded first via layout).
 */
(function () {
    'use strict';

    var caseId = null;
    var sourceUploaded = false;
    var targetCount = 0;

    // ---- Upload helpers ----

    function setupZone(zoneId, inputId, listId, type) {
        var zone = document.getElementById(zoneId);
        var input = document.getElementById(inputId);
        var list = document.getElementById(listId);

        if (!zone || !input) return;

        zone.addEventListener('dragover', function (e) {
            e.preventDefault();
            zone.classList.add('drag-over');
        });
        zone.addEventListener('dragleave', function () {
            zone.classList.remove('drag-over');
        });
        zone.addEventListener('drop', function (e) {
            e.preventDefault();
            zone.classList.remove('drag-over');
            uploadFiles(e.dataTransfer.files, type, list);
        });
        input.addEventListener('change', function () {
            uploadFiles(input.files, type, list);
        });
    }

    function uploadFiles(files, uploadType, listEl) {
        if (!files || files.length === 0) return;

        var caseName = document.getElementById('case_name').value || 'Comparison ' + new Date().toISOString().slice(0, 16);

        var formData = new FormData();
        for (var i = 0; i < files.length; i++) {
            formData.append('files[]', files[i]);
        }
        formData.append('upload_type', uploadType);
        if (caseId) {
            formData.append('case_id', caseId);
        } else {
            formData.append('case_name', caseName);
        }

        fetch('/comparison/upload', {
            method: 'POST',
            headers: { 'X-CSRF-TOKEN': getCsrfToken() },
            body: formData,
        })
        .then(function (resp) { return resp.json(); })
        .then(function (data) {
            if (data.error) {
                alert('Upload error: ' + data.error);
                return;
            }

            if (data.case_id) caseId = data.case_id;

            (data.uploads || []).forEach(function (u) {
                var item = document.createElement('div');
                item.className = 'file-item';
                item.textContent = u.filename + (u.error ? ' (' + u.error + ')' : '');
                listEl.appendChild(item);

                if (uploadType === 'source' && !u.error) sourceUploaded = true;
                if (uploadType === 'target' && !u.error) targetCount++;
            });

            updateStartButton();
        })
        .catch(function (err) {
            alert('Upload failed: ' + err);
        });
    }

    function updateStartButton() {
        var btn = document.getElementById('btn-start');
        btn.disabled = !(sourceUploaded && targetCount > 0);
    }

    // ---- Job submission ----

    function startComparison() {
        if (!caseId) {
            alert('Please upload files first.');
            return;
        }

        var settings = {
            case_id: caseId,
            compare_types: getSelectedTypes(),
            use_semantic: document.getElementById('use_semantic').checked ? 1 : 0,
            simhash_max_dist: document.getElementById('simhash_max_dist').value,
            jaccard_near_dup: document.getElementById('jaccard_near_dup').value,
            cosine_near_dup: document.getElementById('cosine_near_dup').value,
            semantic_threshold: document.getElementById('semantic_threshold').value,
            semantic_review_threshold: document.getElementById('semantic_review').value,
        };

        var body = new URLSearchParams(settings).toString();

        fetch('/comparison/start', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'X-CSRF-TOKEN': getCsrfToken(),
            },
            body: body,
        })
        .then(function (resp) { return resp.json(); })
        .then(function (data) {
            if (data.error) {
                alert('Failed to start: ' + data.error);
                return;
            }
            showProgress(data.job_id);
        })
        .catch(function (err) {
            alert('Request failed: ' + err);
        });
    }

    function getSelectedTypes() {
        var sel = document.getElementById('compare_types');
        var values = [];
        for (var i = 0; i < sel.options.length; i++) {
            if (sel.options[i].selected) values.push(sel.options[i].value);
        }
        return values;
    }

    // ---- Progress polling ----

    function showProgress(jobId) {
        document.getElementById('progress-overlay').style.display = 'flex';
        pollStatus(jobId);
    }

    function pollStatus(jobId) {
        fetch('/comparison/' + jobId + '/status')
        .then(function (resp) { return resp.json(); })
        .then(function (data) {
            var bar = document.getElementById('progress-bar');
            var text = document.getElementById('progress-text');
            var status = data.status || 'unknown';

            if (data.task_status && data.task_status.progress) {
                var p = data.task_status.progress;
                bar.style.width = (p.percent || 0) + '%';
                text.textContent = p.current || status;
            } else {
                text.textContent = status;
            }

            if (status === 'completed') {
                bar.style.width = '100%';
                text.textContent = 'Completed! Redirecting...';
                setTimeout(function () {
                    window.location.href = '/results/' + jobId;
                }, 1000);
            } else if (status === 'failed' || status === 'cancelled') {
                text.textContent = 'Job ' + status + '.';
            } else {
                setTimeout(function () { pollStatus(jobId); }, 2000);
            }
        })
        .catch(function () {
            setTimeout(function () { pollStatus(jobId); }, 4000);
        });
    }

    // ---- Init ----
    setupZone('source-zone', 'source-file', 'source-list', 'source');
    setupZone('target-zone', 'target-files', 'target-list', 'target');

    var btnStart = document.getElementById('btn-start');
    if (btnStart) {
        btnStart.addEventListener('click', startComparison);
    }
})();
