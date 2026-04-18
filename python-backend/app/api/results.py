"""
Results API Endpoints

Handles retrieval of job results from MinIO.
"""
from fastapi import APIRouter, HTTPException, status
from fastapi.responses import StreamingResponse
from io import BytesIO

from app.core.config import settings
from app.core.logging import get_logger
from app.services.minio_client import get_minio_client

logger = get_logger("api.results")
router = APIRouter()


@router.get("/results/{bucket}/{object_key:path}")
async def download_result_file(bucket: str, object_key: str):
    """
    Download a result file from MinIO
    
    Args:
        bucket: MinIO bucket name
        object_key: Object key/path (e.g., results/123/results.csv)
    
    Returns:
        Streaming file download
    """
    logger.info(f"Downloading result file: {bucket}/{object_key}")
    
    try:
        minio_client = get_minio_client()
        
        # Get object
        response = minio_client.get_object(bucket, object_key)
        
        # Determine content type and filename
        if object_key.endswith(".csv"):
            media_type = "text/csv"
            filename = object_key.split("/")[-1]
        elif object_key.endswith(".html"):
            media_type = "text/html"
            filename = object_key.split("/")[-1]
        else:
            media_type = "application/octet-stream"
            filename = object_key.split("/")[-1]
        
        # Read content
        content = response.read()
        response.close()
        response.release_conn()
        
        logger.info(f"Downloaded {len(content)} bytes from {bucket}/{object_key}")
        
        # Return streaming response
        return StreamingResponse(
            BytesIO(content),
            media_type=media_type,
            headers={
                "Content-Disposition": f"attachment; filename={filename}"
            }
        )
    
    except Exception as e:
        logger.error(f"Failed to download file {bucket}/{object_key}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"File not found or download failed: {str(e)}"
        )


@router.get("/results/{bucket}/{object_key:path}/presigned-url")
async def get_presigned_url(bucket: str, object_key: str, expires: int = 3600):
    """
    Get a presigned URL for downloading a result file
    
    Args:
        bucket: MinIO bucket name
        object_key: Object key/path
        expires: URL expiration in seconds (default: 1 hour)
    
    Returns:
        Presigned URL
    """
    logger.info(f"Generating presigned URL for: {bucket}/{object_key}")
    
    try:
        minio_client = get_minio_client()
        
        # Generate presigned URL
        url = minio_client.presigned_get_object(
            bucket,
            object_key,
            expires=expires
        )
        
        logger.info(f"Generated presigned URL (expires in {expires}s)")
        
        return {
            "url": url,
            "bucket": bucket,
            "object_key": object_key,
            "expires_in": expires
        }
    
    except Exception as e:
        logger.error(f"Failed to generate presigned URL: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate presigned URL: {str(e)}"
        )
