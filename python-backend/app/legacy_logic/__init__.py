"""Legacy logic — wraps the original unified_compare_app.py engine."""
from app.legacy_logic.comparison_engine import (
    compare_files_from_bytes,
    generate_csv_bytes,
    generate_html_bytes,
)

__all__ = [
    "compare_files_from_bytes",
    "generate_csv_bytes",
    "generate_html_bytes",
]
