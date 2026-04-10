"""
Redis Client Service

Provides Redis caching operations.
"""
import redis
import json
from typing import Optional, Any

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("services.redis")


def get_redis_client() -> redis.Redis:
    """
    Get configured Redis client for caching
    
    Returns:
        Redis client instance
    """
    client = redis.Redis(
        host=settings.redis_host,
        port=settings.redis_port,
        db=settings.redis_db_cache,
        password=settings.redis_password,
        decode_responses=False  # We'll handle encoding ourselves
    )
    return client


def cache_get(key: str) -> Optional[Any]:
    """
    Get a value from cache
    
    Args:
        key: Cache key
    
    Returns:
        Cached value (deserialized from JSON) or None if not found
    """
    try:
        client = get_redis_client()
        value = client.get(key)
        if value:
            logger.debug(f"Cache hit: {key}")
            return json.loads(value)
        else:
            logger.debug(f"Cache miss: {key}")
            return None
    except Exception as e:
        logger.error(f"Cache get failed for {key}: {e}", exc_info=True)
        return None


def cache_set(key: str, value: Any, ttl: Optional[int] = None) -> bool:
    """
    Set a value in cache
    
    Args:
        key: Cache key
        value: Value to cache (will be JSON-serialized)
        ttl: Time-to-live in seconds (default: from settings)
    
    Returns:
        True if successful, False otherwise
    """
    try:
        client = get_redis_client()
        ttl = ttl or settings.cache_ttl
        serialized = json.dumps(value)
        client.setex(key, ttl, serialized)
        logger.debug(f"Cache set: {key} (TTL: {ttl}s)")
        return True
    except Exception as e:
        logger.error(f"Cache set failed for {key}: {e}", exc_info=True)
        return False


def cache_delete(key: str) -> bool:
    """
    Delete a value from cache
    
    Args:
        key: Cache key
    
    Returns:
        True if deleted, False if not found or error
    """
    try:
        client = get_redis_client()
        result = client.delete(key)
        if result:
            logger.debug(f"Cache delete: {key}")
            return True
        else:
            logger.debug(f"Cache delete failed (not found): {key}")
            return False
    except Exception as e:
        logger.error(f"Cache delete failed for {key}: {e}", exc_info=True)
        return False


def cache_exists(key: str) -> bool:
    """
    Check if a key exists in cache
    
    Args:
        key: Cache key
    
    Returns:
        True if exists, False otherwise
    """
    try:
        client = get_redis_client()
        return client.exists(key) > 0
    except Exception as e:
        logger.error(f"Cache exists check failed for {key}: {e}", exc_info=True)
        return False


def cache_get_fingerprints(sha256: str) -> Optional[dict]:
    """
    Get cached file fingerprints by SHA-256
    
    Args:
        sha256: File SHA-256 hash
    
    Returns:
        Fingerprints dict or None if not cached
    """
    key = f"fp:{sha256}"
    return cache_get(key)


def cache_set_fingerprints(sha256: str, fingerprints: dict, ttl: Optional[int] = None) -> bool:
    """
    Cache file fingerprints by SHA-256
    
    Args:
        sha256: File SHA-256 hash
        fingerprints: Fingerprints dict to cache
        ttl: Time-to-live in seconds (default: from settings)
    
    Returns:
        True if successful
    """
    key = f"fp:{sha256}"
    return cache_set(key, fingerprints, ttl)
