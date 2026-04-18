"""Tests for Pydantic schemas."""
from app.models.schemas import (
    FileType, JobStatus, Verdict, JobSettings, ProcessRequest,
    UploadResponse, ResultSummary, HealthResponse,
)


def test_file_type_enum():
    assert FileType.ALL.value == "all"
    assert FileType.EMAIL.value == "email"


def test_job_settings_defaults():
    s = JobSettings()
    assert s.compare_types == [FileType.ALL]
    assert s.use_semantic is False
    assert s.simhash_max_dist == 5
    assert s.jaccard_near_dup == 0.50
    assert s.cosine_near_dup == 0.85


def test_process_request_round_trip():
    req = ProcessRequest(
        job_id=42,
        source_minio_key="1/abc/test.txt",
        target_minio_keys=["1/def/t1.txt", "1/ghi/t2.pdf"],
    )
    d = req.model_dump()
    assert d["job_id"] == 42
    assert len(d["target_minio_keys"]) == 2
    assert d["settings"]["compare_types"] == [FileType.ALL]


def test_upload_response():
    u = UploadResponse(
        object_key="1/abc/test.txt",
        bucket="uploads",
        sha256="a" * 64,
        filename="test.txt",
        file_size=1024,
    )
    assert u.file_size == 1024


def test_result_summary():
    s = ResultSummary(total_targets=100, identical=10, unrelated=90)
    assert s.near_duplicate == 0
    assert s.errors == 0


def test_verdict_values():
    assert Verdict.IDENTICAL.value == "IDENTICAL"
    assert Verdict.UNRELATED.value == "UNRELATED"
    assert Verdict.ERROR.value == "ERROR"
