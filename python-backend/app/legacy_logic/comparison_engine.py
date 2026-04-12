"""
Comparison Engine — web-backend adapter for unified_compare_app.py

Re-exports the core functions from the original desktop application and
provides a high-level ``compare_files_from_bytes`` entry point that the
Celery worker can call without touching the local filesystem.
"""
from __future__ import annotations

import csv
import io
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import sys
import os

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

from unified_compare_app import (
    ParsedRecord,
    parse_any,
    compute_fingerprints,
    verdict_for,
    write_html_report,
    embed_text_ollama,
    cosine_similarity,
    sha256_bytes,
    selected_extensions,
    TYPE_MAP,
    SUPPORTED_EXTS,
)


def _parse_from_bytes(raw: bytes, filename: str) -> Tuple[ParsedRecord, Dict[str, Any]]:
    """Parse file contents from raw bytes and compute fingerprints.

    Writes the bytes to a temp file so the existing parsers (which expect
    filesystem paths) work unchanged.
    """
    suffix = Path(filename).suffix
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(raw)
        tmp.flush()
        tmp_path = Path(tmp.name)

    try:
        rec = parse_any(tmp_path)
        rec.path = filename
        fps = compute_fingerprints(rec, raw)
    finally:
        tmp_path.unlink(missing_ok=True)

    return rec, fps


def compare_files_from_bytes(
    source_bytes: bytes,
    source_filename: str,
    targets: List[Tuple[str, bytes]],
    compare_types: Optional[List[str]] = None,
    use_semantic: bool = False,
    ollama_url: str = "http://localhost:11434",
    ollama_model: str = "nomic-embed-text",
    simhash_max_dist: int = 5,
    jaccard_near_dup: float = 0.50,
    cosine_near_dup: float = 0.85,
    semantic_threshold: float = 0.90,
    semantic_review_threshold: float = 0.75,
    progress_callback=None,
) -> Tuple[List[Dict[str, Any]], Dict[str, int]]:
    """Run comparison from in-memory bytes (no local filesystem needed).

    Args:
        source_bytes: raw bytes of the source file
        source_filename: original filename (used to select parser)
        targets: list of (filename, raw_bytes) tuples for each target
        compare_types: list of type keys ("email", "pdf", etc.) or None for all
        ... threshold params forwarded to verdict_for
        progress_callback: optional fn(current_step: str, processed: int, total: int)

    Returns:
        (rows, summary) where *rows* is a list of result dicts and *summary*
        has verdict-count tallies.
    """
    allowed_exts = SUPPORTED_EXTS
    if compare_types:
        allowed_exts = selected_extensions(compare_types)

    source_suffix = Path(source_filename).suffix.lower()
    if source_suffix not in allowed_exts:
        raise ValueError(
            f"Source type {source_suffix} does not match selected compare types"
        )

    if progress_callback:
        progress_callback("Parsing source file", 0, len(targets))

    source_rec, source_fps = _parse_from_bytes(source_bytes, source_filename)
    source_data = {"record": source_rec.to_dict(), "fps": source_fps}

    source_emb = None
    if use_semantic:
        src_text = source_rec.body_text_clean or source_rec.body_text_full
        source_emb = embed_text_ollama(src_text, base_url=ollama_url, model=ollama_model)

    rows: List[Dict[str, Any]] = []
    summary: Dict[str, int] = {
        "total_targets": 0,
        "identical": 0,
        "content_duplicate": 0,
        "attachment_match": 0,
        "near_duplicate": 0,
        "semantically_similar": 0,
        "review_semantic": 0,
        "unrelated": 0,
        "errors": 0,
    }

    for i, (target_filename, target_bytes) in enumerate(targets):
        target_suffix = Path(target_filename).suffix.lower()
        if target_suffix not in allowed_exts:
            continue

        summary["total_targets"] += 1

        if progress_callback:
            progress_callback(
                f"Processing target {i + 1} of {len(targets)}", i, len(targets)
            )

        try:
            target_rec, target_fps = _parse_from_bytes(target_bytes, target_filename)
            target_data = {"record": target_rec.to_dict(), "fps": target_fps}

            target_emb = None
            semantic_used = False
            if use_semantic and source_emb is not None:
                tgt_text = target_rec.body_text_clean or target_rec.body_text_full
                target_emb = embed_text_ollama(
                    tgt_text, base_url=ollama_url, model=ollama_model
                )
                semantic_used = target_emb is not None

            verdict, reasons, scores = verdict_for(
                source_data,
                target_data,
                simhash_max_dist=simhash_max_dist,
                jaccard_near_dup=jaccard_near_dup,
                semantic_threshold=semantic_threshold,
                semantic_review_threshold=semantic_review_threshold,
                use_semantic=(use_semantic and source_emb is not None and semantic_used),
                source_emb=source_emb,
                target_emb=target_emb,
                cosine_near_dup=cosine_near_dup,
            )

            s_fps = source_data["fps"]
            t_fps = target_data["fps"]
            s_attach = set(s_fps.get("attachment_hashes", []) or [])
            t_attach = set(t_fps.get("attachment_hashes", []) or [])
            attach_overlap = sorted(s_attach & t_attach)

            row = {
                "target_path": target_filename,
                "target_type": target_rec.file_type,
                "target_subject": target_rec.subject,
                "verdict": verdict,
                "reasons": ";".join(reasons),
                "raw_hash_match": int(s_fps["sha256_raw"] == t_fps["sha256_raw"]),
                "canonical_hash_match": int(
                    s_fps["sha256_canonical"] == t_fps["sha256_canonical"]
                ),
                "body_hash_match": int(
                    s_fps["sha256_body_clean"] == t_fps["sha256_body_clean"]
                ),
                "attachment_match_count": len(attach_overlap),
                "simhash_distance": scores.get("simhash_distance", ""),
                "token_jaccard": scores.get("token_jaccard", ""),
                "cosine_tfidf": scores.get("cosine_tfidf", ""),
                "semantic_cosine": scores.get("semantic_cosine", ""),
                "comparison_score": scores.get("comparison_score", ""),
            }
            rows.append(row)

            verdict_key = verdict.lower()
            if verdict_key in summary:
                summary[verdict_key] += 1

        except Exception as e:
            summary["errors"] += 1
            summary["total_targets"] += 0  # already incremented above
            rows.append(
                {
                    "target_path": target_filename,
                    "target_type": Path(target_filename).suffix.lower().lstrip("."),
                    "target_subject": "",
                    "verdict": "ERROR",
                    "reasons": f"parse_error:{e}",
                    "raw_hash_match": "",
                    "canonical_hash_match": "",
                    "body_hash_match": "",
                    "attachment_match_count": "",
                    "simhash_distance": "",
                    "token_jaccard": "",
                    "cosine_tfidf": "",
                    "semantic_cosine": "",
                    "comparison_score": "",
                }
            )

    rows.sort(key=lambda r: float(r.get("comparison_score") or 0.0), reverse=True)

    return rows, summary


def generate_csv_bytes(rows: List[Dict[str, Any]]) -> bytes:
    """Produce the results CSV as UTF-8 bytes."""
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
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=fieldnames)
    writer.writeheader()
    for r in rows:
        writer.writerow(r)
    return buf.getvalue().encode("utf-8")


def generate_html_bytes(
    rows: List[Dict[str, Any]],
    source_filename: str,
    target_description: str = "uploaded targets",
) -> bytes:
    """Produce the HTML report as UTF-8 bytes using the original report writer."""
    with tempfile.NamedTemporaryFile(
        suffix=".html", delete=False, mode="w"
    ) as tmp:
        tmp_path = Path(tmp.name)

    try:
        write_html_report(
            html_path=tmp_path,
            source_path=source_filename,
            target_root=target_description,
            rows=rows,
            generated_ts=time.strftime("%Y-%m-%d %H:%M:%S"),
        )
        return tmp_path.read_bytes()
    finally:
        tmp_path.unlink(missing_ok=True)
