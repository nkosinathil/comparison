#!/usr/bin/env python3
from __future__ import annotations

import csv
import sys
import time
import traceback
import webbrowser
from pathlib import Path
from typing import List, Optional

try:
    from PySide6.QtCore import Qt, QObject, QThread, Signal
    from PySide6.QtWidgets import (
        QApplication, QWidget, QLabel, QPushButton, QLineEdit, QTextEdit,
        QFileDialog, QVBoxLayout, QHBoxLayout, QGridLayout, QMessageBox,
        QCheckBox, QProgressBar, QGroupBox, QDoubleSpinBox, QSpinBox
    )
except ImportError:
    raise SystemExit("PySide6 is required. Install it with: pip install PySide6")

import unified_compare_app as core


class CompareWorker(QObject):
    progress = Signal(int)
    log = Signal(str)
    finished = Signal(str, str)  # csv_path, html_path
    error = Signal(str)

    def __init__(
        self,
        source: str,
        targets: str,
        out_dir: str,
        compare_types: List[str],
        use_semantic: bool,
        ollama_url: str,
        ollama_model: str,
        simhash_max_dist: int,
        jaccard_near_dup: float,
        semantic_threshold: float,
        semantic_review_threshold: float,
        cosine_near_dup: float,
        cache_path: str,
    ) -> None:
        super().__init__()
        self.source = Path(source).expanduser().resolve()
        self.targets = Path(targets).expanduser().resolve()
        self.out_dir = Path(out_dir).expanduser().resolve()
        self.compare_types = compare_types
        self.use_semantic = use_semantic
        self.ollama_url = ollama_url
        self.ollama_model = ollama_model
        self.simhash_max_dist = simhash_max_dist
        self.jaccard_near_dup = jaccard_near_dup
        self.semantic_threshold = semantic_threshold
        self.semantic_review_threshold = semantic_review_threshold
        self.cosine_near_dup = cosine_near_dup
        self.cache_path = cache_path.strip()
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True
        self.log.emit("Cancellation requested...")

    def run(self) -> None:
        try:
            self.out_dir.mkdir(parents=True, exist_ok=True)

            if not self.source.exists() or not self.source.is_file():
                raise RuntimeError(f"Source file does not exist: {self.source}")
            if not self.targets.exists() or not self.targets.is_dir():
                raise RuntimeError(f"Target folder does not exist: {self.targets}")

            allowed_exts = core.selected_extensions(self.compare_types)
            if not core.source_type_matches(self.source, allowed_exts):
                raise RuntimeError(
                    f"Source file type {self.source.suffix.lower()} does not match the selected comparison types: "
                    f"{', '.join(self.compare_types)}"
                )

            cache_conn = None
            if self.cache_path:
                cache_db = Path(self.cache_path).expanduser().resolve()
                cache_db.parent.mkdir(parents=True, exist_ok=True)
                cache_conn = core.open_cache(cache_db)
                self.log.emit(f"Cache enabled: {cache_db}")

            t0 = time.time()
            self.log.emit(f"Loading source: {self.source}")
            source = core.compute_or_load(self.source, cache_conn)

            target_files = core.iter_supported_files(self.targets, allowed_exts)
            if not target_files:
                raise RuntimeError("No supported target files found in the selected target folder.")

            self.log.emit(f"Found {len(target_files)} target file(s).")
            self.progress.emit(0)

            source_emb = None
            if self.use_semantic:
                self.log.emit(f"Generating source embedding using {self.ollama_model}...")
                source_text = source["record"].get("body_text_clean", "") or source["record"].get("body_text_full", "")
                source_emb = core.embed_text_ollama(source_text, base_url=self.ollama_url, model=self.ollama_model)
                if source_emb is None:
                    self.log.emit("Warning: semantic enabled but source embedding failed. Continuing without semantic.")
                    self.use_semantic = False

            rows = []

            total = len(target_files)
            for i, tp in enumerate(target_files, start=1):
                if self._cancelled:
                    if cache_conn is not None:
                        cache_conn.commit()
                        cache_conn.close()
                    self.log.emit("Comparison cancelled.")
                    return

                self.log.emit(f"[{i}/{total}] Comparing: {tp}")
                try:
                    target = core.compute_or_load(tp, cache_conn)
                except Exception as e:
                    rows.append({
                        "target_path": str(tp),
                        "verdict": "ERROR",
                        "reasons": f"parse_error:{e}",
                    })
                    self.progress.emit(int((i / total) * 100))
                    continue

                target_emb = None
                semantic_used = False
                if self.use_semantic and source_emb is not None:
                    tgt_text = target["record"].get("body_text_clean", "") or target["record"].get("body_text_full", "")
                    target_emb = core.embed_text_ollama(tgt_text, base_url=self.ollama_url, model=self.ollama_model)
                    semantic_used = target_emb is not None

                verdict, reasons, scores = core.verdict_for(
                    source=source,
                    target=target,
                    simhash_max_dist=self.simhash_max_dist,
                    jaccard_near_dup=self.jaccard_near_dup,
                    semantic_threshold=self.semantic_threshold,
                    semantic_review_threshold=self.semantic_review_threshold,
                    use_semantic=(self.use_semantic and source_emb is not None and semantic_used),
                    source_emb=source_emb,
                    target_emb=target_emb,
                    cosine_near_dup=self.cosine_near_dup,
                )

                s_fps = source["fps"]
                t_fps = target["fps"]
                s_attach = set(s_fps.get("attachment_hashes", []) or [])
                t_attach = set(t_fps.get("attachment_hashes", []) or [])
                attach_overlap = sorted(s_attach.intersection(t_attach))

                row = {
                    "target_path": str(tp),
                    "target_type": target["record"].get("file_type", ""),
                    "target_subject": target["record"].get("subject", ""),
                    "verdict": verdict,
                    "reasons": ";".join(reasons),
                    "raw_hash_match": int(s_fps["sha256_raw"] == t_fps["sha256_raw"]),
                    "canonical_hash_match": int(s_fps["sha256_canonical"] == t_fps["sha256_canonical"]),
                    "body_hash_match": int(s_fps["sha256_body_clean"] == t_fps["sha256_body_clean"]),
                    "attachment_match_count": len(attach_overlap),
                    "simhash_distance": scores.get("simhash_distance", ""),
                    "token_jaccard": scores.get("token_jaccard", ""),
                    "cosine_tfidf": scores.get("cosine_tfidf", ""),
                    "semantic_cosine": scores.get("semantic_cosine", ""),
                    "comparison_score": scores.get("comparison_score", ""),
                }
                rows.append(row)
                self.progress.emit(int((i / total) * 100))

            if cache_conn is not None:
                cache_conn.commit()
                cache_conn.close()

            rows.sort(key=lambda r: float(r.get("comparison_score") or 0.0), reverse=True)

            csv_path = self.out_dir / "results.csv"
            fieldnames = [
                "target_path",
                "target_type",
                "target_subject",
                "verdict",
                "reasons",
                "raw_hash_match",
                "canonical_hash_match",
                "body_hash_match",
                "attachment_match_count",
                "simhash_distance",
                "token_jaccard",
                "cosine_tfidf",
                "semantic_cosine",
                "comparison_score",
            ]
            with csv_path.open("w", newline="", encoding="utf-8") as f:
                w = csv.DictWriter(f, fieldnames=fieldnames)
                w.writeheader()
                for r in rows:
                    w.writerow(r)

            html_path = self.out_dir / "report.html"
            core.write_html_report(
                html_path=html_path,
                source_path=str(self.source),
                target_root=str(self.targets),
                rows=rows,
                generated_ts=time.strftime("%Y-%m-%d %H:%M:%S"),
            )

            dt = time.time() - t0
            self.log.emit(f"Done. Compared {len(rows)} target(s) in {dt:.1f}s")
            self.log.emit(f"CSV:  {csv_path}")
            self.log.emit(f"HTML: {html_path}")
            self.finished.emit(str(csv_path), str(html_path))
        except Exception as e:
            tb = traceback.format_exc()
            self.error.emit(f"{e}\n\n{tb}")


class MainWindow(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Unified Comparison Tool")
        self.resize(980, 720)
        self._thread: Optional[QThread] = None
        self._worker: Optional[CompareWorker] = None
        self._last_report = ""
        self._build_ui()

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)

        header = QLabel("Unified Comparison Tool")
        header.setStyleSheet("font-size: 24px; font-weight: bold;")
        sub = QLabel("Compare emails, PDFs, Excel, Word, text, TIFF, or all, and generate the same style of HTML report.")
        sub.setWordWrap(True)

        root.addWidget(header)
        root.addWidget(sub)

        files_box = QGroupBox("Inputs")
        files_grid = QGridLayout(files_box)

        self.source_edit = QLineEdit()
        self.targets_edit = QLineEdit()
        self.out_edit = QLineEdit()
        self.cache_edit = QLineEdit()

        btn_source = QPushButton("Browse File")
        btn_targets = QPushButton("Browse Folder")
        btn_out = QPushButton("Browse Folder")
        btn_cache = QPushButton("Browse File")

        btn_source.clicked.connect(self.pick_source)
        btn_targets.clicked.connect(self.pick_targets)
        btn_out.clicked.connect(self.pick_output)
        btn_cache.clicked.connect(self.pick_cache)

        files_grid.addWidget(QLabel("Source File"), 0, 0)
        files_grid.addWidget(self.source_edit, 0, 1)
        files_grid.addWidget(btn_source, 0, 2)

        files_grid.addWidget(QLabel("Target Folder"), 1, 0)
        files_grid.addWidget(self.targets_edit, 1, 1)
        files_grid.addWidget(btn_targets, 1, 2)

        files_grid.addWidget(QLabel("Output Folder"), 2, 0)
        files_grid.addWidget(self.out_edit, 2, 1)
        files_grid.addWidget(btn_out, 2, 2)

        files_grid.addWidget(QLabel("Cache DB (optional)"), 3, 0)
        files_grid.addWidget(self.cache_edit, 3, 1)
        files_grid.addWidget(btn_cache, 3, 2)

        root.addWidget(files_box)

        types_box = QGroupBox("Comparison Types")
        types_layout = QHBoxLayout(types_box)
        self.chk_email = QCheckBox("Email")
        self.chk_pdf = QCheckBox("PDF")
        self.chk_excel = QCheckBox("Excel")
        self.chk_word = QCheckBox("Word")
        self.chk_text = QCheckBox("Text")
        self.chk_tiff = QCheckBox("TIFF")
        self.chk_all = QCheckBox("All")
        self.chk_all.setChecked(True)

        for chk in [self.chk_email, self.chk_pdf, self.chk_excel, self.chk_word, self.chk_text, self.chk_tiff]:
            chk.toggled.connect(self.on_type_changed)
            types_layout.addWidget(chk)

        self.chk_all.toggled.connect(self.on_all_changed)
        types_layout.addWidget(self.chk_all)
        types_layout.addStretch(1)

        root.addWidget(types_box)

        options_box = QGroupBox("Options")
        options_grid = QGridLayout(options_box)

        self.semantic_chk = QCheckBox("Enable semantic similarity (Ollama)")
        self.semantic_chk.setChecked(False)
        self.ollama_url_edit = QLineEdit("http://localhost:11434")
        self.ollama_model_edit = QLineEdit("nomic-embed-text")

        self.simhash_spin = QSpinBox()
        self.simhash_spin.setRange(0, 64)
        self.simhash_spin.setValue(6)

        self.jaccard_spin = QDoubleSpinBox()
        self.jaccard_spin.setRange(0.0, 1.0)
        self.jaccard_spin.setSingleStep(0.01)
        self.jaccard_spin.setDecimals(2)
        self.jaccard_spin.setValue(0.80)

        self.cosine_spin = QDoubleSpinBox()
        self.cosine_spin.setRange(0.0, 1.0)
        self.cosine_spin.setSingleStep(0.01)
        self.cosine_spin.setDecimals(2)
        self.cosine_spin.setValue(0.85)

        self.semantic_thresh_spin = QDoubleSpinBox()
        self.semantic_thresh_spin.setRange(0.0, 1.0)
        self.semantic_thresh_spin.setSingleStep(0.01)
        self.semantic_thresh_spin.setDecimals(2)
        self.semantic_thresh_spin.setValue(0.90)

        self.semantic_review_spin = QDoubleSpinBox()
        self.semantic_review_spin.setRange(0.0, 1.0)
        self.semantic_review_spin.setSingleStep(0.01)
        self.semantic_review_spin.setDecimals(2)
        self.semantic_review_spin.setValue(0.80)

        options_grid.addWidget(self.semantic_chk, 0, 0, 1, 2)
        options_grid.addWidget(QLabel("Ollama URL"), 1, 0)
        options_grid.addWidget(self.ollama_url_edit, 1, 1)
        options_grid.addWidget(QLabel("Ollama Model"), 2, 0)
        options_grid.addWidget(self.ollama_model_edit, 2, 1)
        options_grid.addWidget(QLabel("SimHash Max Distance"), 3, 0)
        options_grid.addWidget(self.simhash_spin, 3, 1)
        options_grid.addWidget(QLabel("Jaccard Near-Duplicate"), 4, 0)
        options_grid.addWidget(self.jaccard_spin, 4, 1)
        options_grid.addWidget(QLabel("Cosine (TF-IDF) Near-Duplicate"), 5, 0)
        options_grid.addWidget(self.cosine_spin, 5, 1)
        options_grid.addWidget(QLabel("Semantic Threshold"), 6, 0)
        options_grid.addWidget(self.semantic_thresh_spin, 6, 1)
        options_grid.addWidget(QLabel("Semantic Review Threshold"), 7, 0)
        options_grid.addWidget(self.semantic_review_spin, 7, 1)

        root.addWidget(options_box)

        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.setValue(0)
        root.addWidget(self.progress)

        buttons = QHBoxLayout()
        self.run_btn = QPushButton("Begin Comparison")
        self.cancel_btn = QPushButton("Cancel")
        self.open_report_btn = QPushButton("Open Report")
        self.open_report_btn.setEnabled(False)

        self.run_btn.clicked.connect(self.start_compare)
        self.cancel_btn.clicked.connect(self.cancel_compare)
        self.open_report_btn.clicked.connect(self.open_report)

        buttons.addWidget(self.run_btn)
        buttons.addWidget(self.cancel_btn)
        buttons.addWidget(self.open_report_btn)
        buttons.addStretch(1)
        root.addLayout(buttons)

        self.log_box = QTextEdit()
        self.log_box.setReadOnly(True)
        root.addWidget(self.log_box, 1)

        self.setStyleSheet("""
            QWidget { font-family: Arial, sans-serif; font-size: 12px; }
            QGroupBox { font-weight: bold; margin-top: 10px; }
            QGroupBox::title { subcontrol-origin: margin; left: 10px; padding: 0 4px; }
            QPushButton { min-height: 32px; padding: 6px 12px; }
            QLineEdit, QTextEdit, QSpinBox, QDoubleSpinBox { padding: 4px; }
            QTextEdit { background: #111; color: #e8e8e8; }
        """)

    def append_log(self, text: str) -> None:
        self.log_box.append(text)

    def on_all_changed(self, checked: bool) -> None:
        checks = [self.chk_email, self.chk_pdf, self.chk_excel, self.chk_word, self.chk_text, self.chk_tiff]
        if checked:
            for chk in checks:
                chk.blockSignals(True)
                chk.setChecked(False)
                chk.blockSignals(False)

    def on_type_changed(self) -> None:
        any_specific = any(chk.isChecked() for chk in [self.chk_email, self.chk_pdf, self.chk_excel, self.chk_word, self.chk_text, self.chk_tiff])
        if any_specific and self.chk_all.isChecked():
            self.chk_all.blockSignals(True)
            self.chk_all.setChecked(False)
            self.chk_all.blockSignals(False)
        elif not any_specific:
            self.chk_all.blockSignals(True)
            self.chk_all.setChecked(True)
            self.chk_all.blockSignals(False)

    def selected_types(self) -> List[str]:
        if self.chk_all.isChecked():
            return ["all"]
        mapping = [
            (self.chk_email, "email"),
            (self.chk_pdf, "pdf"),
            (self.chk_excel, "excel"),
            (self.chk_word, "word"),
            (self.chk_text, "text"),
            (self.chk_tiff, "tiff"),
        ]
        values = [name for chk, name in mapping if chk.isChecked()]
        return values or ["all"]

    def pick_source(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Select Source File")
        if path:
            self.source_edit.setText(path)

    def pick_targets(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Select Target Folder")
        if path:
            self.targets_edit.setText(path)

    def pick_output(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Select Output Folder")
        if path:
            self.out_edit.setText(path)
            if not self.cache_edit.text().strip():
                self.cache_edit.setText(str(Path(path) / "fingerprints.sqlite"))

    def pick_cache(self) -> None:
        path, _ = QFileDialog.getSaveFileName(self, "Select Cache SQLite File", filter="SQLite DB (*.sqlite *.db);;All Files (*)")
        if path:
            self.cache_edit.setText(path)

    def validate_inputs(self) -> bool:
        if not self.source_edit.text().strip():
            QMessageBox.warning(self, "Missing source", "Please choose a source file.")
            return False
        if not self.targets_edit.text().strip():
            QMessageBox.warning(self, "Missing target folder", "Please choose a target folder.")
            return False
        if not self.out_edit.text().strip():
            QMessageBox.warning(self, "Missing output folder", "Please choose an output folder.")
            return False
        return True

    def start_compare(self) -> None:
        if not self.validate_inputs():
            return
        if self._thread is not None:
            QMessageBox.information(self, "Busy", "A comparison is already running.")
            return

        self.progress.setValue(0)
        self.open_report_btn.setEnabled(False)
        self._last_report = ""
        self.log_box.clear()

        self._thread = QThread()
        self._worker = CompareWorker(
            source=self.source_edit.text().strip(),
            targets=self.targets_edit.text().strip(),
            out_dir=self.out_edit.text().strip(),
            compare_types=self.selected_types(),
            use_semantic=self.semantic_chk.isChecked(),
            ollama_url=self.ollama_url_edit.text().strip(),
            ollama_model=self.ollama_model_edit.text().strip(),
            simhash_max_dist=self.simhash_spin.value(),
            jaccard_near_dup=self.jaccard_spin.value(),
            semantic_threshold=self.semantic_thresh_spin.value(),
            semantic_review_threshold=self.semantic_review_spin.value(),
            cosine_near_dup=self.cosine_spin.value(),
            cache_path=self.cache_edit.text().strip(),
        )
        self._worker.moveToThread(self._thread)
        self._thread.started.connect(self._worker.run)
        self._worker.progress.connect(self.progress.setValue)
        self._worker.log.connect(self.append_log)
        self._worker.finished.connect(self.on_finished)
        self._worker.error.connect(self.on_error)
        self._worker.finished.connect(self._thread.quit)
        self._worker.error.connect(self._thread.quit)
        self._thread.finished.connect(self.cleanup_thread)

        self.run_btn.setEnabled(False)
        self.append_log("Starting comparison...")
        self._thread.start()

    def cancel_compare(self) -> None:
        if self._worker is not None:
            self._worker.cancel()

    def cleanup_thread(self) -> None:
        self.run_btn.setEnabled(True)
        if self._worker is not None:
            self._worker.deleteLater()
            self._worker = None
        if self._thread is not None:
            self._thread.deleteLater()
            self._thread = None

    def on_finished(self, csv_path: str, html_path: str) -> None:
        self._last_report = html_path
        self.open_report_btn.setEnabled(True)
        self.progress.setValue(100)
        QMessageBox.information(
            self,
            "Comparison complete",
            f"Comparison finished successfully.\n\nCSV:\n{csv_path}\n\nReport:\n{html_path}",
        )

    def on_error(self, message: str) -> None:
        self.append_log("ERROR")
        self.append_log(message)
        QMessageBox.critical(self, "Comparison failed", message)

    def open_report(self) -> None:
        if not self._last_report:
            return
        webbrowser.open(Path(self._last_report).as_uri())


def main() -> int:
    app = QApplication(sys.argv)
    w = MainWindow()
    w.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
