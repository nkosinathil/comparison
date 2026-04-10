"""
File Upload API Endpoints

Handles file uploads to MinIO object storage.
"""
from fastapi import APIRouter, UploadFile, File, Form, HTTPException, status
from pathlib import Path
import hashlib
from typing import Optional

from app.core.config import settings
from app.core.logging import get_logger
from app.models.schemas import UploadResponse
from app.services.minio_client import get_minio_client, upload_file_to_minio

logger = get_logger("api.upload")
router = APIRouter()


@router.post("/upload", response_model=UploadResponse, status_code=status.HTTP_201_CREATED)
async def upload_file(
    file: UploadFile = File(...),
    case_id: Optional[str] = Form(None),
    bucket: str = Form(default="uploads")
):
    """
    Upload a file to MinIO
    
    Args:
        file: File to upload (multipart/form-data)
        case_id: Optional case ID for organizing files
        bucket: Target bucket (default: uploads)
    
    Returns:
        UploadResponse with object key, bucket, SHA-256, etc.
    
    Raises:
        HTTPException: If file is too large or upload fails
    """
    logger.info(f"Uploading file: {file.filename}, case_id: {case_id}")
    
    # Read file content
    try:
        content = await file.read()
    except Exception as e:
        logger.error(f"Failed to read uploaded file: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Failed to read file: {str(e)}"
        )
    
    # Check file size
    file_size = len(content)
    if file_size > settings.max_file_size:
        logger.warning(f"File too large: {file_size} bytes (max: {settings.max_file_size})")
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File too large. Maximum size is {settings.max_file_size} bytes."
        )
    
    # Compute SHA-256
    sha256 = hashlib.sha256(content).hexdigest()
    logger.info(f"File SHA-256: {sha256}")
    
    # Generate object key
    # Format: {case_id}/{sha256}/{filename} or {sha256}/{filename} if no case_id
    filename = file.filename or "unnamed"
    if case_id:
        object_key = f"{case_id}/{sha256}/{filename}"
    else:
        object_key = f"{sha256}/{filename}"
    
    # Upload to MinIO
    try:
        minio_client = get_minio_client()
        upload_file_to_minio(
            minio_client,
            bucket=bucket,
            object_key=object_key,
            data=content,
            content_type=file.content_type
        )
        logger.info(f"File uploaded to MinIO: {bucket}/{object_key}")
    except Exception as e:
        logger.error(f"MinIO upload failed: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to upload file to storage: {str(e)}"
        )
    
    return UploadResponse(
        object_key=object_key,
        bucket=bucket,
        sha256=sha256,
        filename=filename,
        file_size=file_size
    )


@router.delete("/upload/{bucket}/{object_key:path}")
async def delete_file(bucket: str, object_key: str):
    """
    Delete a file from MinIO
    
    Args:
        bucket: MinIO bucket name
        object_key: Object key/path
    
    Returns:
        Success message
    """
    logger.info(f"Deleting file: {bucket}/{object_key}")
    
    try:
        minio_client = get_minio_client()
        minio_client.remove_object(bucket, object_key)
        logger.info(f"File deleted: {bucket}/{object_key}")
        return {"message": "File deleted successfully", "object_key": object_key}
    except Exception as e:
        logger.error(f"Failed to delete file: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete file: {str(e)}"
        )
