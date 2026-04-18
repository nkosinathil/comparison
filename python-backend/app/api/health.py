"""
Health Check API Endpoints

Provides health status for the service and its dependencies.
"""
from fastapi import APIRouter, status
from fastapi.responses import JSONResponse
import redis
from minio import Minio
from celery import Celery

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("api.health")
router = APIRouter()


@router.get("/health", status_code=status.HTTP_200_OK)
async def health_check():
    """
    Basic health check
    
    Returns 200 if service is running.
    """
    return {
        "status": "healthy",
        "service": "comparison-backend",
        "version": "1.0.0"
    }


@router.get("/health/detailed", status_code=status.HTTP_200_OK)
async def detailed_health_check():
    """
    Detailed health check including all dependencies
    
    Returns:
        - Overall status
        - Redis connection status
        - MinIO connection status
        - Celery broker status
    """
    health_status = {
        "status": "healthy",
        "service": "comparison-backend",
        "version": "1.0.0",
        "dependencies": {}
    }
    
    overall_healthy = True
    
    # Check Redis
    try:
        r = redis.Redis(
            host=settings.redis_host,
            port=settings.redis_port,
            db=settings.redis_db_cache,
            password=settings.redis_password,
            socket_connect_timeout=3
        )
        r.ping()
        health_status["dependencies"]["redis"] = {"status": "healthy", "message": "Connected"}
    except Exception as e:
        health_status["dependencies"]["redis"] = {"status": "unhealthy", "error": str(e)}
        overall_healthy = False
        logger.error(f"Redis health check failed: {e}")
    
    # Check MinIO
    try:
        minio_client = Minio(
            settings.minio_endpoint,
            access_key=settings.minio_access_key,
            secret_key=settings.minio_secret_key,
            secure=settings.minio_secure
        )
        # Try to list buckets
        buckets = list(minio_client.list_buckets())
        health_status["dependencies"]["minio"] = {
            "status": "healthy",
            "message": f"Connected, {len(buckets)} buckets found"
        }
    except Exception as e:
        health_status["dependencies"]["minio"] = {"status": "unhealthy", "error": str(e)}
        overall_healthy = False
        logger.error(f"MinIO health check failed: {e}")
    
    # Check Celery broker (Redis)
    try:
        celery_app = Celery(broker=settings.redis_url)
        # Inspect ping
        inspect = celery_app.control.inspect(timeout=3)
        workers = inspect.ping()
        if workers:
            health_status["dependencies"]["celery"] = {
                "status": "healthy",
                "message": f"{len(workers)} workers responding"
            }
        else:
            health_status["dependencies"]["celery"] = {
                "status": "degraded",
                "message": "No workers responding"
            }
            overall_healthy = False
    except Exception as e:
        health_status["dependencies"]["celery"] = {"status": "unhealthy", "error": str(e)}
        overall_healthy = False
        logger.error(f"Celery health check failed: {e}")
    
    # Set overall status
    if not overall_healthy:
        health_status["status"] = "degraded"
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content=health_status
        )
    
    return health_status


@router.get("/health/ready", status_code=status.HTTP_200_OK)
async def readiness_check():
    """
    Readiness check for load balancers/orchestrators
    
    Returns 200 if service is ready to accept traffic.
    """
    # Perform basic dependency checks
    try:
        # Check Redis
        r = redis.Redis(
            host=settings.redis_host,
            port=settings.redis_port,
            db=settings.redis_db_cache,
            password=settings.redis_password,
            socket_connect_timeout=2
        )
        r.ping()
        
        # Check MinIO
        minio_client = Minio(
            settings.minio_endpoint,
            access_key=settings.minio_access_key,
            secret_key=settings.minio_secret_key,
            secure=settings.minio_secure
        )
        minio_client.list_buckets()
        
        return {"status": "ready"}
    
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "not_ready", "error": "dependency_check_failed"}
        )


@router.get("/health/live", status_code=status.HTTP_200_OK)
async def liveness_check():
    """
    Liveness check for orchestrators
    
    Returns 200 if process is alive (minimal check).
    """
    return {"status": "alive"}
