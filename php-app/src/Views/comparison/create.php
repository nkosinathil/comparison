<?php $pageTitle = 'New Comparison'; ?>
<?php ob_start(); ?>

<div class="page-header">
    <h1>New Comparison</h1>
</div>

<div class="card">
    <div class="card-header"><h2>1. Case</h2></div>
    <div class="card-body">
        <div class="form-group">
            <label for="case_name">Case Name</label>
            <input type="text" id="case_name" class="form-control"
                   placeholder="e.g. Investigation 2026-04" value="">
        </div>
    </div>
</div>

<div class="card">
    <div class="card-header"><h2>2. Upload Source File</h2></div>
    <div class="card-body">
        <div class="upload-zone" id="source-zone" data-upload-type="source">
            <p>Drag &amp; drop <strong>one</strong> source file here, or click to browse.</p>
            <input type="file" id="source-file" class="file-input" accept=".eml,.msg,.pdf,.docx,.xlsx,.xlsm,.txt,.csv,.log,.json,.xml,.html,.htm,.md,.rtf,.tif,.tiff">
        </div>
        <div id="source-list" class="file-list"></div>
    </div>
</div>

<div class="card">
    <div class="card-header"><h2>3. Upload Target Files</h2></div>
    <div class="card-body">
        <div class="upload-zone" id="target-zone" data-upload-type="target">
            <p>Drag &amp; drop target files here, or click to browse. Multiple files allowed.</p>
            <input type="file" id="target-files" class="file-input" multiple
                   accept=".eml,.msg,.pdf,.docx,.xlsx,.xlsm,.txt,.csv,.log,.json,.xml,.html,.htm,.md,.rtf,.tif,.tiff">
        </div>
        <div id="target-list" class="file-list"></div>
    </div>
</div>

<div class="card">
    <div class="card-header"><h2>4. Settings</h2></div>
    <div class="card-body">
        <div class="form-row">
            <div class="form-group">
                <label for="compare_types">Compare Types</label>
                <select id="compare_types" class="form-control" multiple>
                    <option value="all" selected>All</option>
                    <option value="email">Email (.eml, .msg)</option>
                    <option value="pdf">PDF</option>
                    <option value="word">Word (.docx)</option>
                    <option value="excel">Excel (.xlsx, .xlsm)</option>
                    <option value="text">Text (.txt, .csv, .json, ...)</option>
                    <option value="tiff">TIFF (OCR)</option>
                </select>
            </div>
            <div class="form-group">
                <label>
                    <input type="checkbox" id="use_semantic"> Enable Semantic Similarity (Ollama)
                </label>
            </div>
        </div>

        <details class="advanced-settings">
            <summary>Advanced Thresholds</summary>
            <div class="form-row">
                <div class="form-group">
                    <label for="simhash_max_dist">SimHash Max Distance</label>
                    <input type="number" id="simhash_max_dist" class="form-control" value="5" min="0" max="64">
                </div>
                <div class="form-group">
                    <label for="jaccard_near_dup">Jaccard Threshold</label>
                    <input type="number" id="jaccard_near_dup" class="form-control" value="0.50" min="0" max="1" step="0.01">
                </div>
                <div class="form-group">
                    <label for="cosine_near_dup">Cosine TF-IDF Threshold</label>
                    <input type="number" id="cosine_near_dup" class="form-control" value="0.85" min="0" max="1" step="0.01">
                </div>
                <div class="form-group">
                    <label for="semantic_threshold">Semantic Threshold</label>
                    <input type="number" id="semantic_threshold" class="form-control" value="0.90" min="0" max="1" step="0.01">
                </div>
                <div class="form-group">
                    <label for="semantic_review">Semantic Review Threshold</label>
                    <input type="number" id="semantic_review" class="form-control" value="0.75" min="0" max="1" step="0.01">
                </div>
            </div>
        </details>
    </div>
</div>

<div class="form-actions">
    <button id="btn-start" class="btn btn-primary btn-lg" disabled>Start Comparison</button>
</div>

<!-- Progress overlay (hidden by default) -->
<div id="progress-overlay" class="progress-overlay" style="display:none;">
    <div class="progress-card">
        <h3>Processing...</h3>
        <div class="progress-bar-container">
            <div class="progress-bar" id="progress-bar" style="width:0%"></div>
        </div>
        <p id="progress-text">Queued</p>
    </div>
</div>

<script src="/js/comparison.js"></script>

<?php $content = ob_get_clean(); ?>
<?php require __DIR__ . '/../layouts/app.php'; ?>
