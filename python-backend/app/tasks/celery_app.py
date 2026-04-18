"""
Celery Application Configuration

Configures Celery for distributed task processing.
"""
from celery import Celery

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("tasks.celery_app")

# Create Celery app
celery_app = Celery(
    "comparison_tasks",
    broker=settings.redis_url,
    backend=settings.redis_result_url
)

# Configure Celery
celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=settings.celery_task_time_limit,
    task_soft_time_limit=settings.celery_task_soft_time_limit,
    result_expires=settings.celery_result_expires,
    worker_prefetch_multiplier=1,  # Process one task at a time
    task_acks_late=True,  # Acknowledge tasks after completion
    worker_max_tasks_per_child=50,  # Restart worker after N tasks to prevent memory leaks
)

# Auto-discover tasks in this module
celery_app.autodiscover_tasks(["app.tasks"])

logger.info("Celery app configured")
