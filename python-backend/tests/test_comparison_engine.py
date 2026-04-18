"""Tests for the legacy comparison engine adapter."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from app.legacy_logic.comparison_engine import (
    compare_files_from_bytes,
    generate_csv_bytes,
    generate_html_bytes,
    _parse_from_bytes,
)


class TestParseFromBytes:
    def test_parse_text(self):
        rec, fps = _parse_from_bytes(b"hello world", "sample.txt")
        assert rec.file_type == "txt"
        assert "hello" in fps["tokens"]

    def test_parse_csv(self):
        rec, fps = _parse_from_bytes(b"a,b,c\n1,2,3\n", "data.csv")
        assert rec.file_type == "csv"


class TestCompareFiles:
    def test_identical_files(self):
        rows, summary = compare_files_from_bytes(
            source_bytes=b"Some test content here",
            source_filename="src.txt",
            targets=[("copy.txt", b"Some test content here")],
        )
        assert len(rows) == 1
        assert rows[0]["verdict"] == "IDENTICAL"
        assert summary["identical"] == 1
        assert summary["total_targets"] == 1

    def test_different_files(self):
        rows, summary = compare_files_from_bytes(
            source_bytes=b"Alpha bravo charlie",
            source_filename="src.txt",
            targets=[("other.txt", b"Xylophone yielding zebras")],
        )
        assert len(rows) == 1
        assert rows[0]["verdict"] == "UNRELATED"
        assert summary["unrelated"] == 1

    def test_multiple_targets(self):
        rows, summary = compare_files_from_bytes(
            source_bytes=b"Unique content for testing",
            source_filename="src.txt",
            targets=[
                ("same.txt", b"Unique content for testing"),
                ("diff.txt", b"Completely different material"),
            ],
        )
        assert len(rows) == 2
        assert summary["total_targets"] == 2
        verdicts = {r["verdict"] for r in rows}
        assert "IDENTICAL" in verdicts

    def test_near_duplicate(self):
        src = b"The quick brown fox jumps over the lazy dog near the river bank"
        tgt = b"The quick brown fox jumps over the lazy dog near the river side"
        rows, summary = compare_files_from_bytes(
            source_bytes=src,
            source_filename="a.txt",
            targets=[("b.txt", tgt)],
        )
        assert len(rows) == 1
        assert rows[0]["verdict"] in ("IDENTICAL", "CONTENT_DUPLICATE", "NEAR_DUPLICATE")

    def test_unsupported_source_type(self):
        try:
            compare_files_from_bytes(
                source_bytes=b"data",
                source_filename="file.xyz",
                targets=[],
            )
            assert False, "Should have raised"
        except (ValueError, RuntimeError):
            pass

    def test_progress_callback(self):
        calls = []

        def cb(step, processed, total):
            calls.append((step, processed, total))

        compare_files_from_bytes(
            source_bytes=b"test",
            source_filename="a.txt",
            targets=[("b.txt", b"other")],
            progress_callback=cb,
        )
        assert len(calls) >= 2


class TestReportGeneration:
    def _make_rows(self):
        rows, _ = compare_files_from_bytes(
            source_bytes=b"Hello World",
            source_filename="src.txt",
            targets=[("a.txt", b"Hello World"), ("b.txt", b"xyz")],
        )
        return rows

    def test_csv_generation(self):
        rows = self._make_rows()
        csv = generate_csv_bytes(rows)
        assert b"target_path" in csv
        assert b"verdict" in csv
        lines = csv.decode().strip().split("\n")
        assert len(lines) == 3  # header + 2 rows

    def test_html_generation(self):
        rows = self._make_rows()
        html = generate_html_bytes(rows, "src.txt")
        assert b"<!doctype html>" in html or b"<html>" in html
        assert b"Comparison Report" in html
