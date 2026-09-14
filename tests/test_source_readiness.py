from __future__ import annotations

import base64
import io
import zipfile
from pathlib import Path

from tools.audit_source_readiness import audit


def _zip_bytes(files: dict[str, bytes]) -> bytes:
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    return stream.getvalue()


def test_present_app_is_authoritative(tmp_path: Path) -> None:
    (tmp_path / "app.py").write_text("print('ok')\n", encoding="utf-8")
    result = audit(tmp_path)
    assert result.status == "present"
    assert result.app_present is True
    assert result.recoverable is True
    assert result.candidates == ()


def test_clean_canonical_parts_are_recoverable_without_writing(tmp_path: Path) -> None:
    part_dir = tmp_path / "tools" / "source_restore_parts"
    part_dir.mkdir(parents=True)
    encoded = base64.b64encode(_zip_bytes({"app.py": b"print('safe')\n", "web/index.html": b"ok"}))
    chunk = (len(encoded) + 10) // 11
    parts = [encoded[index * chunk : (index + 1) * chunk] for index in range(11)]
    # Keep all canonical files non-empty; append any tail to the last part.
    if b"" in parts:
        raise AssertionError("test fixture unexpectedly produced an empty canonical part")
    for index, data in enumerate(parts):
        (part_dir / f"part_{index:02d}.b64").write_bytes(data)

    result = audit(tmp_path)
    assert result.status == "recoverable"
    assert result.app_present is False
    assert result.recoverable is True
    assert not (tmp_path / "app.py").exists(), "audit must never restore files"
    canonical = next(item for item in result.candidates if item.name == "canonical part_00..part_10")
    assert canonical.valid_zip is True
    assert canonical.app_present is True
    assert canonical.app_crc_ok is True


def test_corrupt_and_incomplete_candidates_report_blocked(tmp_path: Path) -> None:
    tools = tmp_path / "tools"
    tools.mkdir()
    (tools / "source_restore.zip").write_bytes(b"not a zip")
    part_dir = tools / "source_restore_parts"
    part_dir.mkdir()
    (part_dir / "part_00.b64").write_text("AAAA", encoding="ascii")

    result = audit(tmp_path)
    assert result.status == "blocked"
    assert result.app_present is False
    assert result.recoverable is False
    binary = next(item for item in result.candidates if item.name == "tools/source_restore.zip")
    assert binary.available is True
    assert binary.valid_zip is False
    canonical = next(item for item in result.candidates if item.name == "canonical part_00..part_10")
    assert canonical.available is False
    assert "incomplete" in canonical.detail


def test_clean_archive_without_app_is_not_recoverable(tmp_path: Path) -> None:
    tools = tmp_path / "tools"
    tools.mkdir()
    (tools / "source_restore.zip").write_bytes(_zip_bytes({"README.txt": b"no app"}))
    result = audit(tmp_path)
    assert result.status == "blocked"
    binary = next(item for item in result.candidates if item.name == "tools/source_restore.zip")
    assert binary.valid_zip is True
    assert binary.app_present is False
    assert binary.app_crc_ok is False
