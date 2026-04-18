"""
Comparison Tasks

Celery tasks for file comparison processing.
Uses the legacy comparison engine from unified_compare_app.py via the
comparison_engine adapter.
"""
from celery import Task
from typing import List, Dict, Any
from datetime import datetime, timedelta

from app.tasks.celery_app import celery_app
from app.core.logging import get_logger
from app.services.minio_client import (
    get_minio_client,
    download_file_from_minio,
    upload_file_to_minio,
    list_objects,
    delete_file_from_minio,
)
from app.services.redis_client import cache_get_fingerprints, cache_set_fingerprints
from app.legacy_logic.comparison_engine import (
    compare_files_from_bytes,
    generate_csv_bytes,
    generate_html_bytes,
)

logger = get_logger("tasks.comparison")


class ComparisonTask(Task):
    """Base class for comparison tasks with progress tracking"""

    def update_progress(self, current: str, processed: int = 0, total: int = 0):
        percent = int((processed / total) * 100) if total > 0 else 0
        self.update_state(
            state="PROGRESS",
            meta={
                "current": current,
                "processed": processed,
                "total": total,
                "percent": percent,
            },
        )


@celery_app.task(bind=True, base=ComparisonTask, name="tasks.run_comparison")
def run_comparison_task(
    self,
    job_id: int,
    source_minio_key: str,
    source_bucket: str,
    target_minio_keys: List[str],
    target_bucket: str,
    settings: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Run file comparison job.

    Downloads source and target files from MinIO, runs the comparison engine,
    and uploads CSV + HTML reports back to MinIO.
    """
    logger.info(f"Starting comparison job {job_id}")
    logger.info(f"Source: {source_bucket}/{source_minio_key}")
    logger.info(f"Targets: {len(target_minio_keys)} files")

    try:
        minio_client = get_minio_client()

        self.update_progress("Initializing comparison", 0, len(target_minio_keys))

        # Download source file
        logger.info(f"Job {job_id}: Downloading source file")
        self.update_progress("Downloading source file", 0, len(target_minio_keys))
        source_data = download_file_from_minio(
            minio_client, source_bucket, source_minio_key
        )
        source_filename = source_minio_key.rsplit("/", 1)[-1]

        # Download all target files
        logger.info(f"Job {job_id}: Downloading {len(target_minio_keys)} target files")
        self.update_progress(
            "Downloading target files", 0, len(target_minio_keys)
        )
        targets = []
        for i, key in enumerate(target_minio_keys):
            target_data = download_file_from_minio(minio_client, target_bucket, key)
            target_filename = key.rsplit("/", 1)[-1]
            targets.append((target_filename, target_data))
            if (i + 1) % 20 == 0:
                self.update_progress(
                    f"Downloaded {i + 1} of {len(target_minio_keys)} targets",
                    i + 1,
                    len(target_minio_keys),
                )

        # Extract settings
        compare_types = settings.get("compare_types", ["all"])
        if isinstance(compare_types, str):
            compare_types = [compare_types]

        def _progress(step: str, processed: int, total: int):
            self.update_progress(step, processed, total)

        # Run the comparison engine
        logger.info(f"Job {job_id}: Running comparison engine")
        rows, summary = compare_files_from_bytes(
            source_bytes=source_data,
            source_filename=source_filename,
            targets=targets,
            compare_types=compare_types if compare_types != ["all"] else None,
            use_semantic=settings.get("use_semantic", False),
            ollama_url=settings.get("ollama_url", "http://localhost:11434"),
            ollama_model=settings.get("ollama_model", "nomic-embed-text"),
            simhash_max_dist=settings.get("simhash_max_dist", 5),
            jaccard_near_dup=settings.get("jaccard_near_dup", 0.50),
            cosine_near_dup=settings.get("cosine_near_dup", 0.85),
            semantic_threshold=settings.get("semantic_threshold", 0.90),
            semantic_review_threshold=settings.get("semantic_review_threshold", 0.75),
            progress_callback=_progress,
        )

        # Generate reports
        logger.info(f"Job {job_id}: Generating reports")
        self.update_progress(
            "Generating reports", len(target_minio_keys), len(target_minio_keys)
        )

        csv_bytes = generate_csv_bytes(rows)
        html_bytes = generate_html_bytes(
            rows,
            source_filename=source_filename,
            target_description=f"{len(targets)} uploaded targets",
        )

        # Upload reports to MinIO
        csv_key = f"results/{job_id}/results.csv"
        html_key = f"results/{job_id}/report.html"

        upload_file_to_minio(
            minio_client, "results", csv_key, csv_bytes, "text/csv"
        )
        upload_file_to_minio(
            minio_client, "results", html_key, html_bytes, "text/html"
        )

        logger.info(f"Job {job_id}: Reports uploaded to MinIO")

        result = {
            "job_id": job_id,
            "csv_key": csv_key,
            "html_key": html_key,
            "summary": summary,
            "status": "completed",
        }

        logger.info(f"Job {job_id}: Completed successfully — {summary}")
        return result

    except Exception as e:
        logger.error(f"Job {job_id} failed: {e}", exc_info=True)
        raise


@celery_app.task(name="tasks.cleanup_old_results")
def cleanup_old_results_task(days_old: int = 90):
    """
    Cleanup old result files from MinIO.

    Intended to run periodically via Celery Beat.
    """
    logger.info(f"Cleaning up results older than {days_old} days")

    try:
        minio_client = get_minio_client()
        cutoff = datetime.utcnow() - timedelta(days=days_old)
        deleted = 0

        for obj in list_objects(minio_client, "results", recursive=True):
            if hasattr(obj, "last_modified") and obj.last_modified < cutoff:
                delete_file_from_minio(minio_client, "results", obj.object_name)
                deleted += 1

        logger.info(f"Cleanup completed: deleted {deleted} old objects")
        return {"status": "completed", "days_old": days_old, "deleted": deleted}

    except Exception as e:
        logger.error(f"Cleanup task failed: {e}", exc_info=True)
        return {"status": "failed", "error": str(e)}
