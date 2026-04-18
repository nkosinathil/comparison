"""
Task Status API Endpoints

Provides task status and progress information.
"""
from fastapi import APIRouter, HTTPException, status
from celery.result import AsyncResult

from app.core.config import settings
from app.core.logging import get_logger
from app.models.schemas import TaskStatusResponse, TaskProgress, TaskState

logger = get_logger("api.tasks")
router = APIRouter()


@router.get("/tasks/{task_id}/status", response_model=TaskStatusResponse)
async def get_task_status(task_id: str):
    """
    Get status of a Celery task
    
    Args:
        task_id: Celery task ID
    
    Returns:
        TaskStatusResponse with current state, progress, and result/error
    """
    logger.info(f"Querying task status: {task_id}")
    
    try:
        from app.tasks.celery_app import celery_app
        
        task_result = AsyncResult(task_id, app=celery_app)
        
        # Get task state
        state = task_result.state
        logger.debug(f"Task {task_id} state: {state}")
        
        response = TaskStatusResponse(
            task_id=task_id,
            state=TaskState(state)
        )
        
        # Add progress if available
        if state == "PROGRESS" and isinstance(task_result.info, dict):
            progress_info = task_result.info
            response.progress = TaskProgress(
                current=progress_info.get("current"),
                total=progress_info.get("total"),
                processed=progress_info.get("processed"),
                percent=progress_info.get("percent")
            )
        
        # Add result if completed
        elif state == "SUCCESS":
            response.result = task_result.result
        
        # Add error if failed
        elif state == "FAILURE":
            response.error = str(task_result.info)
        
        return response
    
    except Exception as e:
        logger.error(f"Failed to get task status for {task_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get task status"
        )


@router.get("/tasks/{task_id}/result")
async def get_task_result(task_id: str):
    """
    Get the result of a completed task
    
    Args:
        task_id: Celery task ID
    
    Returns:
        Task result data (job-specific)
    
    Raises:
        HTTPException: If task is not completed or failed
    """
    logger.info(f"Retrieving task result: {task_id}")
    
    try:
        from app.tasks.celery_app import celery_app
        
        task_result = AsyncResult(task_id, app=celery_app)
        
        if task_result.state == "PENDING":
            raise HTTPException(
                status_code=status.HTTP_202_ACCEPTED,
                detail="Task is still pending"
            )
        elif task_result.state == "STARTED" or task_result.state == "PROGRESS":
            raise HTTPException(
                status_code=status.HTTP_202_ACCEPTED,
                detail=f"Task is still running (state: {task_result.state})"
            )
        elif task_result.state == "FAILURE":
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Task failed: {str(task_result.info)}"
            )
        elif task_result.state == "SUCCESS":
            return {
                "task_id": task_id,
                "state": task_result.state,
                "result": task_result.result
            }
        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unexpected task state: {task_result.state}"
            )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get task result for {task_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get task result"
        )
