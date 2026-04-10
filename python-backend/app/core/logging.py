"""
Logging Configuration

Provides structured logging with JSON output support.
"""
import logging
import logging.handlers
import sys
from pathlib import Path
from typing import Optional

from pythonjsonlogger import jsonlogger

from .config import settings


def setup_logging(log_file: Optional[str] = None) -> logging.Logger:
    """
    Configure application logging
    
    Args:
        log_file: Optional path to log file (defaults to settings.log_file)
    
    Returns:
        Configured logger instance
    """
    log_file = log_file or settings.log_file
    log_level = getattr(logging, settings.log_level.upper(), logging.INFO)
    
    # Create logger
    logger = logging.getLogger("comparison_backend")
    logger.setLevel(log_level)
    logger.propagate = False
    
    # Remove existing handlers
    logger.handlers.clear()
    
    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(log_level)
    
    # File handler with rotation
    if log_file:
        log_path = Path(log_file)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        
        file_handler = logging.handlers.RotatingFileHandler(
            log_file,
            maxBytes=settings.log_max_size,
            backupCount=settings.log_backup_count
        )
        file_handler.setLevel(log_level)
    
    # Format
    if settings.log_format == "json":
        # JSON format for production
        json_formatter = jsonlogger.JsonFormatter(
            "%(asctime)s %(name)s %(levelname)s %(message)s",
            rename_fields={"asctime": "timestamp", "levelname": "level", "name": "logger"}
        )
        console_handler.setFormatter(json_formatter)
        if log_file:
            file_handler.setFormatter(json_formatter)
    else:
        # Text format for development
        text_formatter = logging.Formatter(
            "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        )
        console_handler.setFormatter(text_formatter)
        if log_file:
            file_handler.setFormatter(text_formatter)
    
    # Add handlers
    logger.addHandler(console_handler)
    if log_file:
        logger.addHandler(file_handler)
    
    return logger


# Global logger instance
logger = setup_logging()


def get_logger(name: str) -> logging.Logger:
    """
    Get a child logger with the specified name
    
    Args:
        name: Logger name (will be prefixed with comparison_backend)
    
    Returns:
        Child logger
    """
    return logging.getLogger(f"comparison_backend.{name}")
