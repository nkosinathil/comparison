"""
Core Configuration for Python Backend

Loads settings from environment variables.
Uses pydantic-settings for validation and type safety.
"""
from typing import Optional
from pydantic_settings import BaseSettings
from pydantic import Field


class Settings(BaseSettings):
    """Application settings loaded from environment variables"""
    
    # Application
    app_name: str = Field(default="comparison-backend", env="APP_NAME")
    app_env: str = Field(default="production", env="APP_ENV")
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    
    # FastAPI
    fastapi_host: str = Field(default="0.0.0.0", env="FASTAPI_HOST")
    fastapi_port: int = Field(default=8000, env="FASTAPI_PORT")
    fastapi_workers: int = Field(default=4, env="FASTAPI_WORKERS")
    fastapi_reload: bool = Field(default=False, env="FASTAPI_RELOAD")
    
    # Redis
    redis_host: str = Field(default="localhost", env="REDIS_HOST")
    redis_port: int = Field(default=6379, env="REDIS_PORT")
    redis_db_broker: int = Field(default=0, env="REDIS_DB_BROKER")
    redis_db_result: int = Field(default=1, env="REDIS_DB_RESULT")
    redis_db_cache: int = Field(default=2, env="REDIS_DB_CACHE")
    redis_password: Optional[str] = Field(default=None, env="REDIS_PASSWORD")
    
    # MinIO
    minio_endpoint: str = Field(default="localhost:9000", env="MINIO_ENDPOINT")
    minio_access_key: str = Field(env="MINIO_ACCESS_KEY")
    minio_secret_key: str = Field(env="MINIO_SECRET_KEY")
    minio_secure: bool = Field(default=False, env="MINIO_SECURE")
    minio_bucket_uploads: str = Field(default="uploads", env="MINIO_BUCKET_UPLOADS")
    minio_bucket_results: str = Field(default="results", env="MINIO_BUCKET_RESULTS")
    minio_bucket_cache: str = Field(default="cache", env="MINIO_BUCKET_CACHE")
    minio_region: str = Field(default="us-east-1", env="MINIO_REGION")
    
    # Celery
    celery_task_always_eager: bool = Field(default=False, env="CELERY_TASK_ALWAYS_EAGER")
    celery_worker_concurrency: int = Field(default=4, env="CELERY_WORKER_CONCURRENCY")
    celery_task_time_limit: int = Field(default=3600, env="CELERY_TASK_TIME_LIMIT")
    celery_task_soft_time_limit: int = Field(default=3300, env="CELERY_TASK_SOFT_TIME_LIMIT")
    celery_result_expires: int = Field(default=86400, env="CELERY_RESULT_EXPIRES")
    
    # Processing Settings
    default_simhash_max_dist: int = Field(default=5, env="DEFAULT_SIMHASH_MAX_DIST")
    default_jaccard_near_dup: float = Field(default=0.50, env="DEFAULT_JACCARD_NEAR_DUP")
    default_semantic_threshold: float = Field(default=0.90, env="DEFAULT_SEMANTIC_THRESHOLD")
    default_semantic_review_threshold: float = Field(default=0.75, env="DEFAULT_SEMANTIC_REVIEW_THRESHOLD")
    default_cosine_near_dup: float = Field(default=0.85, env="DEFAULT_COSINE_NEAR_DUP")
    
    cache_fingerprints: bool = Field(default=True, env="CACHE_FINGERPRINTS")
    cache_ttl: int = Field(default=604800, env="CACHE_TTL")  # 7 days
    
    # Ollama
    ollama_enabled: bool = Field(default=False, env="OLLAMA_ENABLED")
    ollama_url: str = Field(default="http://localhost:11434", env="OLLAMA_URL")
    ollama_model: str = Field(default="nomic-embed-text", env="OLLAMA_MODEL")
    ollama_timeout: int = Field(default=60, env="OLLAMA_TIMEOUT")
    
    # File Processing
    max_file_size: int = Field(default=524288000, env="MAX_FILE_SIZE")  # 500MB
    temp_dir: str = Field(default="/tmp/comparison_processing", env="TEMP_DIR")
    
    tesseract_enabled: bool = Field(default=True, env="TESSERACT_ENABLED")
    tesseract_lang: str = Field(default="eng", env="TESSERACT_LANG")
    
    # Logging
    log_file: str = Field(default="/var/log/comparison-backend/app.log", env="LOG_FILE")
    log_max_size: int = Field(default=10485760, env="LOG_MAX_SIZE")  # 10MB
    log_backup_count: int = Field(default=5, env="LOG_BACKUP_COUNT")
    log_format: str = Field(default="json", env="LOG_FORMAT")
    
    @property
    def redis_url(self) -> str:
        """Construct Redis URL for Celery broker"""
        password_part = f":{self.redis_password}@" if self.redis_password else ""
        return f"redis://{password_part}{self.redis_host}:{self.redis_port}/{self.redis_db_broker}"
    
    @property
    def redis_result_url(self) -> str:
        """Construct Redis URL for Celery result backend"""
        password_part = f":{self.redis_password}@" if self.redis_password else ""
        return f"redis://{password_part}{self.redis_host}:{self.redis_port}/{self.redis_db_result}"
    
    @property
    def redis_cache_url(self) -> str:
        """Construct Redis URL for application cache"""
        password_part = f":{self.redis_password}@" if self.redis_password else ""
        return f"redis://{password_part}{self.redis_host}:{self.redis_port}/{self.redis_db_cache}"
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


# Global settings instance
settings = Settings()
