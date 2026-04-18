"""
Main FastAPI Application

Entry point for the file comparison backend API.
"""
from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import time

from app.core.config import settings
from app.core.logging import get_logger
from app.api import health, upload, process, tasks, results

logger = get_logger("main")

# Create FastAPI app
app = FastAPI(
    title="File Comparison Backend API",
    description="Processing engine for file comparison operations",
    version="1.0.0",
    docs_url="/docs" if settings.app_env == "development" else None,  # Disable docs in production
    redoc_url="/redoc" if settings.app_env == "development" else None,
)

# CORS middleware (if needed for direct browser access)
# In production, PHP app will proxy requests, so CORS may not be needed
if settings.app_env == "development":
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # Configure properly in production
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )


_PUBLIC_PATHS = {"/", "/health", "/health/live", "/health/ready", "/docs", "/redoc", "/openapi.json"}


@app.middleware("http")
async def authenticate_and_log(request: Request, call_next):
    """Validate API key on protected routes and log all requests."""
    start_time = time.time()
    path = request.url.path

    # API key enforcement (skip health/docs endpoints)
    if settings.api_key and path not in _PUBLIC_PATHS:
        provided = request.headers.get("X-API-Key", "")
        if provided != settings.api_key:
            return JSONResponse(
                status_code=status.HTTP_401_UNAUTHORIZED,
                content={"error": "Invalid or missing API key"},
            )

    logger.info(
        "Request started",
        extra={
            "method": request.method,
            "url": str(request.url),
            "client": request.client.host if request.client else None,
        },
    )

    try:
        response = await call_next(request)
        process_time = time.time() - start_time

        logger.info(
            "Request completed",
            extra={
                "method": request.method,
                "url": str(request.url),
                "status_code": response.status_code,
                "process_time": f"{process_time:.3f}s",
            },
        )

        response.headers["X-Process-Time"] = str(process_time)
        return response

    except Exception as e:
        process_time = time.time() - start_time
        logger.error(
            "Request failed",
            extra={
                "method": request.method,
                "url": str(request.url),
                "error": str(e),
                "process_time": f"{process_time:.3f}s",
            },
            exc_info=True,
        )
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"error": "Internal server error", "detail": str(e)},
        )


# Include routers
app.include_router(health.router, tags=["health"])
app.include_router(upload.router, prefix="/api", tags=["upload"])
app.include_router(process.router, prefix="/api", tags=["process"])
app.include_router(tasks.router, prefix="/api", tags=["tasks"])
app.include_router(results.router, prefix="/api", tags=["results"])


@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    logger.info(
        "Application starting",
        extra={
            "app_name": settings.app_name,
            "environment": settings.app_env,
            "version": "1.0.0"
        }
    )
    
    # TODO: Initialize MinIO buckets if they don't exist
    # TODO: Test Redis connection
    # TODO: Test MinIO connection


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("Application shutting down")


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "File Comparison Backend API",
        "version": "1.0.0",
        "status": "running",
        "environment": settings.app_env
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.fastapi_host,
        port=settings.fastapi_port,
        reload=settings.fastapi_reload,
        log_level=settings.log_level.lower()
    )
