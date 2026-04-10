"""
Job Processing API Endpoints

Handles submission of comparison jobs to Celery.
"""
from fastapi import APIRouter, HTTPException, status

from app.core.logging import get_logger
from app.models.schemas import ProcessRequest, ProcessResponse
from app.tasks.comparison_tasks import run_comparison_task

logger = get_logger("api.process")
router = APIRouter()


@router.post("/process", response_model=ProcessResponse, status_code=status.HTTP_202_ACCEPTED)
async def process_comparison(request: ProcessRequest):
    """
    Submit a file comparison job to Celery
    
    Args:
        request: ProcessRequest with job details and settings
    
    Returns:
        ProcessResponse with task_id for polling status
    
    Raises:
        HTTPException: If validation fails or task submission fails
    """
    logger.info(f"Processing comparison job {request.job_id}")
    
    # Validate request
    if not request.source_minio_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="source_minio_key is required"
        )
    
    if not request.target_minio_keys or len(request.target_minio_keys) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least one target file is required"
        )
    
    logger.info(
        f"Job {request.job_id}: source={request.source_minio_key}, "
        f"targets={len(request.target_minio_keys)}"
    )
    
    # Submit to Celery
    try:
        task = run_comparison_task.apply_async(
            args=[
                request.job_id,
                request.source_minio_key,
                request.source_bucket,
                request.target_minio_keys,
                request.target_bucket,
                request.settings.model_dump()
            ]
        )
        
        task_id = task.id
        logger.info(f"Job {request.job_id} queued with task_id: {task_id}")
        
        return ProcessResponse(
            task_id=task_id,
            job_id=request.job_id,
            status="queued",
            message=f"Job queued successfully. {len(request.target_minio_keys)} target files will be compared."
        )
    
    except Exception as e:
        logger.error(f"Failed to queue job {request.job_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to queue job: {str(e)}"
        )


@router.post("/process/{task_id}/cancel")
async def cancel_job(task_id: str):
    """
    Cancel a running or queued job
    
    Args:
        task_id: Celery task ID
    
    Returns:
        Cancellation confirmation
    """
    logger.info(f"Cancelling task: {task_id}")
    
    try:
        from celery import Celery
        from app.core.config import settings
        
        celery_app = Celery(broker=settings.redis_url)
        celery_app.control.revoke(task_id, terminate=True, signal='SIGKILL')
        
        logger.info(f"Task {task_id} cancellation requested")
        return {
            "task_id": task_id,
            "status": "cancelled",
            "message": "Task cancellation requested"
        }
    
    except Exception as e:
        logger.error(f"Failed to cancel task {task_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to cancel task: {str(e)}"
        )
