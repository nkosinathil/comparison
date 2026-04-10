"""
Comparison Tasks

Celery tasks for file comparison processing.
These tasks run the actual comparison logic from the original Qt application.
"""
from celery import Task
from typing import List, Dict, Any
import time

from app.tasks.celery_app import celery_app
from app.core.logging import get_logger
from app.services.minio_client import (
    get_minio_client,
    download_file_from_minio,
    upload_file_to_minio
)
from app.services.redis_client import cache_get_fingerprints, cache_set_fingerprints

logger = get_logger("tasks.comparison")


class ComparisonTask(Task):
    """Base class for comparison tasks with progress tracking"""
    
    def update_progress(self, current: str, processed: int = 0, total: int = 0):
        """Update task progress"""
        percent = int((processed / total) * 100) if total > 0 else 0
        self.update_state(
            state="PROGRESS",
            meta={
                "current": current,
                "processed": processed,
                "total": total,
                "percent": percent
            }
        )


@celery_app.task(bind=True, base=ComparisonTask, name="tasks.run_comparison")
def run_comparison_task(
    self,
    job_id: int,
    source_minio_key: str,
    source_bucket: str,
    target_minio_keys: List[str],
    target_bucket: str,
    settings: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Run file comparison job
    
    Args:
        job_id: Job ID from database
        source_minio_key: MinIO key for source file
        source_bucket: Source file bucket
        target_minio_keys: List of target file MinIO keys
        target_bucket: Target files bucket
        settings: Job settings (comparison types, thresholds, etc.)
    
    Returns:
        Dict with result summary and MinIO keys for CSV/HTML reports
    """
    logger.info(f"Starting comparison job {job_id}")
    logger.info(f"Source: {source_bucket}/{source_minio_key}")
    logger.info(f"Targets: {len(target_minio_keys)} files")
    
    try:
        minio_client = get_minio_client()
        
        # Update progress: Starting
        self.update_progress("Initializing comparison", 0, len(target_minio_keys))
        
        # Step 1: Download and process source file
        logger.info(f"Job {job_id}: Downloading source file")
        self.update_progress("Downloading source file", 0, len(target_minio_keys))
        
        source_data = download_file_from_minio(minio_client, source_bucket, source_minio_key)
        
        # TODO: Parse source file and compute fingerprints
        # For now, we'll create a stub that simulates processing
        # This will be replaced with actual logic from unified_compare_app.py
        
        self.update_progress("Processing source file", 0, len(target_minio_keys))
        time.sleep(1)  # Simulate processing
        
        # Step 2: Process each target file
        results = []
        for i, target_key in enumerate(target_minio_keys):
            logger.info(f"Job {job_id}: Processing target {i+1}/{len(target_minio_keys)}: {target_key}")
            self.update_progress(
                f"Processing target {i+1} of {len(target_minio_keys)}",
                i,
                len(target_minio_keys)
            )
            
            # Download target
            target_data = download_file_from_minio(minio_client, target_bucket, target_key)
            
            # TODO: Parse target and compare with source
            # For now, create stub result
            time.sleep(0.5)  # Simulate processing
            
            results.append({
                "target_filename": target_key.split("/")[-1],
                "target_path": target_key,
                "verdict": "UNRELATED",  # Stub
                "reasons": ["stub_processing"],
                "scores": {
                    "simhash_distance": 64,
                    "token_jaccard": 0.0,
                    "cosine_tfidf": 0.0
                }
            })
        
        # Step 3: Generate reports (CSV and HTML)
        logger.info(f"Job {job_id}: Generating reports")
        self.update_progress("Generating reports", len(target_minio_keys), len(target_minio_keys))
        
        # TODO: Use write_html_report and CSV generation from unified_compare_app.py
        # For now, create stub reports
        csv_content = "target,verdict,simhash_distance\n"
        for r in results:
            csv_content += f"{r['target_filename']},{r['verdict']},{r['scores']['simhash_distance']}\n"
        
        html_content = f"<html><body><h1>Comparison Report</h1><p>Job {job_id}: {len(results)} targets processed</p></body></html>"
        
        # Upload reports to MinIO
        csv_key = f"results/{job_id}/results.csv"
        html_key = f"results/{job_id}/report.html"
        
        upload_file_to_minio(
            minio_client,
            "results",
            csv_key,
            csv_content.encode("utf-8"),
            "text/csv"
        )
        
        upload_file_to_minio(
            minio_client,
            "results",
            html_key,
            html_content.encode("utf-8"),
            "text/html"
        )
        
        logger.info(f"Job {job_id}: Reports uploaded to MinIO")
        
        # Build summary
        summary = {
            "total_targets": len(results),
            "identical": 0,
            "near_duplicate": 0,
            "unrelated": len(results),  # Stub
            "errors": 0
        }
        
        result = {
            "job_id": job_id,
            "csv_key": csv_key,
            "html_key": html_key,
            "summary": summary,
            "status": "completed"
        }
        
        logger.info(f"Job {job_id}: Completed successfully")
        return result
    
    except Exception as e:
        logger.error(f"Job {job_id} failed: {e}", exc_info=True)
        raise


@celery_app.task(name="tasks.cleanup_old_results")
def cleanup_old_results_task(days_old: int = 90):
    """
    Cleanup old result files from MinIO
    
    Args:
        days_old: Delete results older than this many days
    
    This task should be run periodically (e.g., daily via Celery Beat)
    """
    logger.info(f"Cleaning up results older than {days_old} days")
    
    # TODO: Implement cleanup logic
    # 1. List objects in results bucket
    # 2. Check timestamps
    # 3. Delete old objects
    
    logger.info("Cleanup task completed")
    return {"status": "completed", "days_old": days_old}
