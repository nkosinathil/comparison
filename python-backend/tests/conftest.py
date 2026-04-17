"""Shared pytest fixtures."""
import os
import pytest

os.environ.setdefault("APP_ENV", "development")
os.environ.setdefault("APP_NAME", "test")
os.environ.setdefault("REDIS_HOST", "localhost")
os.environ.setdefault("MINIO_ENDPOINT", "localhost:9000")
os.environ.setdefault("MINIO_ACCESS_KEY", "minioadmin")
os.environ.setdefault("MINIO_SECRET_KEY", "minioadmin")
os.environ.setdefault("API_KEY", "")
os.environ.setdefault("LOG_FILE", "")

from fastapi.testclient import TestClient
from app.main import app


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def authed_client():
    """Client with a valid API key when API_KEY is set."""
    os.environ["API_KEY"] = "test-key-12345"
    from app.core.config import Settings
    import app.core.config as cfg
    cfg.settings = Settings()
    import importlib, app.main
    importlib.reload(app.main)
    c = TestClient(app.main.app)
    yield c, "test-key-12345"
    os.environ["API_KEY"] = ""
    cfg.settings = Settings()
    importlib.reload(app.main)
