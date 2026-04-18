"""Tests for API key authentication middleware."""
import os


def test_no_key_required_when_unset(client):
    """When API_KEY env is empty, all routes are accessible."""
    resp = client.get("/health")
    assert resp.status_code == 200


def test_health_always_public(authed_client):
    """Health endpoints are accessible without API key even when enforced."""
    client, _ = authed_client
    resp = client.get("/health")
    assert resp.status_code == 200
    resp = client.get("/health/live")
    assert resp.status_code == 200


def test_protected_route_rejected_without_key(authed_client):
    """API routes reject requests without the key."""
    client, key = authed_client
    resp = client.post("/api/process", json={
        "job_id": 1,
        "source_minio_key": "x",
        "target_minio_keys": ["y"],
    })
    assert resp.status_code == 401


def test_protected_route_accepted_with_key(authed_client):
    """API routes accept requests with the correct key (may still fail on
    missing Celery, but should not be 401)."""
    client, key = authed_client
    resp = client.post(
        "/api/process",
        json={
            "job_id": 1,
            "source_minio_key": "x",
            "target_minio_keys": ["y"],
        },
        headers={"X-API-Key": key},
    )
    assert resp.status_code != 401
