"""
Pydantic Models/Schemas for API Request/Response Validation
"""
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field
from enum import Enum
from datetime import datetime


# ========================================
# Enums
# ========================================

class FileType(str, Enum):
    """Supported file types for comparison"""
    EMAIL = "email"
    PDF = "pdf"
    EXCEL = "excel"
    WORD = "word"
    TEXT = "text"
    TIFF = "tiff"
    ALL = "all"


class JobStatus(str, Enum):
    """Job status values"""
    PENDING = "pending"
    QUEUED = "queued"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class TaskState(str, Enum):
    """Celery task states"""
    PENDING = "PENDING"
    STARTED = "STARTED"
    PROGRESS = "PROGRESS"
    SUCCESS = "SUCCESS"
    FAILURE = "FAILURE"
    RETRY = "RETRY"
    REVOKED = "REVOKED"


class Verdict(str, Enum):
    """Comparison verdict types"""
    IDENTICAL = "IDENTICAL"
    CONTENT_DUPLICATE = "CONTENT_DUPLICATE"
    ATTACHMENT_MATCH = "ATTACHMENT_MATCH"
    NEAR_DUPLICATE = "NEAR_DUPLICATE"
    SEMANTICALLY_SIMILAR = "SEMANTICALLY_SIMILAR"
    REVIEW_SEMANTIC = "REVIEW_SEMANTIC"
    UNRELATED = "UNRELATED"
    ERROR = "ERROR"


# ========================================
# Upload API
# ========================================

class UploadResponse(BaseModel):
    """Response after successful file upload"""
    object_key: str = Field(..., description="MinIO object key")
    bucket: str = Field(..., description="MinIO bucket name")
    sha256: str = Field(..., description="File SHA-256 hash")
    filename: str = Field(..., description="Original filename")
    file_size: int = Field(..., description="File size in bytes")
    upload_id: Optional[str] = Field(None, description="Upload ID if tracked")


# ========================================
# Process API
# ========================================

class JobSettings(BaseModel):
    """Settings for a comparison job"""
    compare_types: List[FileType] = Field(default=[FileType.ALL], description="File types to compare")
    use_semantic: bool = Field(default=False, description="Enable semantic similarity")
    simhash_max_dist: int = Field(default=5, description="Simhash distance threshold")
    jaccard_near_dup: float = Field(default=0.50, description="Jaccard similarity threshold")
    semantic_threshold: float = Field(default=0.90, description="Semantic similarity threshold")
    semantic_review_threshold: float = Field(default=0.75, description="Semantic review threshold")
    cosine_near_dup: float = Field(default=0.85, description="Cosine similarity threshold")
    ollama_url: Optional[str] = Field(None, description="Custom Ollama URL")
    ollama_model: Optional[str] = Field(None, description="Custom Ollama model")


class ProcessRequest(BaseModel):
    """Request to process a comparison job"""
    job_id: int = Field(..., description="Job ID from database")
    source_minio_key: str = Field(..., description="MinIO key for source file")
    source_bucket: str = Field(default="uploads", description="Source bucket")
    target_minio_keys: List[str] = Field(..., description="List of target file MinIO keys")
    target_bucket: str = Field(default="uploads", description="Target bucket")
    settings: JobSettings = Field(default_factory=JobSettings, description="Job settings")


class ProcessResponse(BaseModel):
    """Response after submitting a processing job"""
    task_id: str = Field(..., description="Celery task ID")
    job_id: int = Field(..., description="Job ID")
    status: str = Field(default="queued", description="Initial status")
    message: str = Field(default="Job queued successfully")


# ========================================
# Task Status API
# ========================================

class TaskProgress(BaseModel):
    """Task progress information"""
    current: Optional[str] = Field(None, description="Current processing step")
    total: Optional[int] = Field(None, description="Total items to process")
    processed: Optional[int] = Field(None, description="Items processed so far")
    percent: Optional[int] = Field(None, description="Progress percentage (0-100)")


class TaskStatusResponse(BaseModel):
    """Response for task status query"""
    task_id: str = Field(..., description="Celery task ID")
    state: TaskState = Field(..., description="Current task state")
    progress: Optional[TaskProgress] = Field(None, description="Progress info if available")
    result: Optional[Dict[str, Any]] = Field(None, description="Result if completed")
    error: Optional[str] = Field(None, description="Error message if failed")


# ========================================
# Results API
# ========================================

class ComparisonResult(BaseModel):
    """Single comparison result"""
    target_filename: str
    target_path: str
    verdict: Verdict
    reasons: List[str]
    scores: Dict[str, float]


class ResultSummary(BaseModel):
    """Summary statistics for a job"""
    total_targets: int
    identical: int = 0
    content_duplicate: int = 0
    attachment_match: int = 0
    near_duplicate: int = 0
    semantically_similar: int = 0
    review_semantic: int = 0
    unrelated: int = 0
    errors: int = 0


class JobResultResponse(BaseModel):
    """Response containing job results"""
    job_id: int
    task_id: str
    status: JobStatus
    csv_minio_key: Optional[str] = None
    html_minio_key: Optional[str] = None
    summary: Optional[ResultSummary] = None
    results: Optional[List[ComparisonResult]] = None
    completed_at: Optional[datetime] = None


# ========================================
# Error Responses
# ========================================

class ErrorResponse(BaseModel):
    """Standard error response"""
    error: str = Field(..., description="Error type/code")
    detail: str = Field(..., description="Detailed error message")
    request_id: Optional[str] = Field(None, description="Request ID for tracking")


# ========================================
# Health Check
# ========================================

class DependencyStatus(BaseModel):
    """Status of a dependency"""
    status: str = Field(..., description="healthy, degraded, or unhealthy")
    message: Optional[str] = Field(None, description="Status message")
    error: Optional[str] = Field(None, description="Error if unhealthy")


class HealthResponse(BaseModel):
    """Health check response"""
    status: str = Field(..., description="Overall health status")
    service: str = Field(default="comparison-backend")
    version: str = Field(default="1.0.0")
    dependencies: Optional[Dict[str, DependencyStatus]] = None
