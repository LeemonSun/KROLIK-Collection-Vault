from __future__ import annotations

from hashlib import sha256
from pathlib import Path

from tools.fetch_dwpose_model import MODEL_NAME, MODEL_SHA256, DEFAULT_OUTPUT, sha256_file, verify_file


def test_bootstrap_targets_runtime_candidate_path() -> None:
    normalized = str(DEFAULT_OUTPUT).replace('\\', '/')
    assert normalized.endswith(f"/models/dwpose/{MODEL_NAME}")
    assert len(MODEL_SHA256) == 64
    int(MODEL_SHA256, 16)


def test_verify_file_accepts_exact_hash_and_size(tmp_path: Path) -> None:
    payload = b"krolik-dwpose-test-payload"
    path = tmp_path / "model.onnx"
    path.write_bytes(payload)
    digest = sha256(payload).hexdigest()

    ok, reason = verify_file(path, expected_sha256=digest, expected_size=len(payload))
    assert ok is True
    assert reason == digest
    assert sha256_file(path) == digest


def test_verify_file_rejects_size_or_hash_mismatch(tmp_path: Path) -> None:
    path = tmp_path / "model.onnx"
    path.write_bytes(b"valid-bytes")
    digest = sha256(b"valid-bytes").hexdigest()

    ok, reason = verify_file(path, expected_sha256=digest, expected_size=999)
    assert ok is False
    assert reason.startswith("size_mismatch:")

    ok, reason = verify_file(path, expected_sha256="0" * 64, expected_size=len(b"valid-bytes"))
    assert ok is False
    assert reason.startswith("sha256_mismatch:")


def test_verify_file_reports_missing_without_network(tmp_path: Path) -> None:
    ok, reason = verify_file(tmp_path / "missing.onnx", expected_size=None)
    assert ok is False
    assert reason == "missing"
