"""
MinIO Client Service

Provides MinIO object storage operations.
"""
from minio import Minio
from minio.error import S3Error
from io import BytesIO
from typing import Optional

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("services.minio")


def get_minio_client() -> Minio:
    """
    Get configured MinIO client
    
    Returns:
        Minio client instance
    """
    client = Minio(
        settings.minio_endpoint,
        access_key=settings.minio_access_key,
        secret_key=settings.minio_secret_key,
        secure=settings.minio_secure
    )
    return client


def ensure_bucket_exists(client: Minio, bucket_name: str) -> None:
    """
    Ensure a bucket exists, create if it doesn't
    
    Args:
        client: MinIO client
        bucket_name: Bucket name to check/create
    """
    try:
        if not client.bucket_exists(bucket_name):
            client.make_bucket(bucket_name, location=settings.minio_region)
            logger.info(f"Created MinIO bucket: {bucket_name}")
        else:
            logger.debug(f"MinIO bucket exists: {bucket_name}")
    except S3Error as e:
        logger.error(f"Failed to ensure bucket {bucket_name}: {e}", exc_info=True)
        raise


def upload_file_to_minio(
    client: Minio,
    bucket: str,
    object_key: str,
    data: bytes,
    content_type: Optional[str] = None
) -> None:
    """
    Upload a file to MinIO
    
    Args:
        client: MinIO client
        bucket: Target bucket name
        object_key: Object key/path
        data: File content as bytes
        content_type: MIME type (optional)
    """
    try:
        ensure_bucket_exists(client, bucket)
        
        data_stream = BytesIO(data)
        client.put_object(
            bucket,
            object_key,
            data_stream,
            length=len(data),
            content_type=content_type or "application/octet-stream"
        )
        logger.info(f"Uploaded {len(data)} bytes to {bucket}/{object_key}")
    except S3Error as e:
        logger.error(f"Failed to upload to MinIO: {e}", exc_info=True)
        raise


def download_file_from_minio(client: Minio, bucket: str, object_key: str) -> bytes:
    """
    Download a file from MinIO
    
    Args:
        client: MinIO client
        bucket: Source bucket name
        object_key: Object key/path
    
    Returns:
        File content as bytes
    """
    try:
        response = client.get_object(bucket, object_key)
        data = response.read()
        response.close()
        response.release_conn()
        logger.info(f"Downloaded {len(data)} bytes from {bucket}/{object_key}")
        return data
    except S3Error as e:
        logger.error(f"Failed to download from MinIO: {e}", exc_info=True)
        raise


def delete_file_from_minio(client: Minio, bucket: str, object_key: str) -> None:
    """
    Delete a file from MinIO
    
    Args:
        client: MinIO client
        bucket: Bucket name
        object_key: Object key/path
    """
    try:
        client.remove_object(bucket, object_key)
        logger.info(f"Deleted {bucket}/{object_key}")
    except S3Error as e:
        logger.error(f"Failed to delete from MinIO: {e}", exc_info=True)
        raise


def list_objects(client: Minio, bucket: str, prefix: Optional[str] = None) -> list:
    """
    List objects in a bucket with optional prefix
    
    Args:
        client: MinIO client
        bucket: Bucket name
        prefix: Optional prefix to filter objects
    
    Returns:
        List of object keys
    """
    try:
        objects = client.list_objects(bucket, prefix=prefix or "", recursive=True)
        object_keys = [obj.object_name for obj in objects]
        logger.info(f"Listed {len(object_keys)} objects in {bucket} (prefix: {prefix})")
        return object_keys
    except S3Error as e:
        logger.error(f"Failed to list objects in MinIO: {e}", exc_info=True)
        raise


def get_presigned_url(
    client: Minio,
    bucket: str,
    object_key: str,
    expires: int = 3600
) -> str:
    """
    Generate a presigned URL for temporary download access
    
    Args:
        client: MinIO client
        bucket: Bucket name
        object_key: Object key/path
        expires: Expiration time in seconds (default: 1 hour)
    
    Returns:
        Presigned URL
    """
    try:
        url = client.presigned_get_object(bucket, object_key, expires=expires)
        logger.info(f"Generated presigned URL for {bucket}/{object_key} (expires in {expires}s)")
        return url
    except S3Error as e:
        logger.error(f"Failed to generate presigned URL: {e}", exc_info=True)
        raise
