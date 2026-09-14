from __future__ import annotations

import json
from pathlib import Path

import pytest

from character_import import build_character_runtime_package
from runtime_package_integrity import (
    RUNTIME_PACKAGE_RECEIPT_SCHEMA,
    RuntimePackageIntegrityError,
    seal_built_runtime_package,
    validate_runtime_package_receipt,
)
from tools.build_core_vertical_slice import build_fixture_image


def _build(tmp_path: Path, name: str, *, edited: bool = False) -> tuple[dict, dict]:
    source = build_fixture_image(tmp_path / name / "source.png")
    result = build_character_runtime_package(
        tmp_path / name / "project",
        source,
        name,
        prefer_ai_rig=False,
        joint_overrides={"left_wrist": {"x": 0.16, "y": 0.49}} if edited else None,
    )
    report = seal_built_runtime_package(result)
    return result, report


def test_sealed_package_reopens_with_import_and_runtime_integrity(tmp_path: Path) -> None:
    result, sealed = _build(tmp_path, "plain")
    receipt = Path(str(sealed["package_receipt"]))
    document = json.loads(receipt.read_text(encoding="utf-8"))
    reopened = validate_runtime_package_receipt(receipt)

    assert document["schema"] == RUNTIME_PACKAGE_RECEIPT_SCHEMA
    assert reopened["ok"] is True
    assert reopened["character_id"] == "plain"
    assert reopened["source_sha256"] == result["source_sha256"]
    assert reopened["cutout_sha256"] == result["cutout_sha256"]
    assert reopened["rig_edit_verified"] is False
    assert Path(reopened["manifest"]).is_file()
    assert Path(reopened["image"]).is_file()


def test_sealed_package_reopens_with_rig_edit_provenance(tmp_path: Path) -> None:
    result, sealed = _build(tmp_path, "edited", edited=True)
    reopened = validate_runtime_package_receipt(sealed["package_receipt"])
    assert result["rig_edit"] is not None
    assert reopened["rig_edit_verified"] is True


def test_runtime_manifest_tamper_is_rejected(tmp_path: Path) -> None:
    result, sealed = _build(tmp_path, "manifest-tamper")
    manifest = Path(str(result["manifest"]))
    manifest.write_text(manifest.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    with pytest.raises(RuntimePackageIntegrityError, match="manifest hash mismatch"):
        validate_runtime_package_receipt(sealed["package_receipt"])


def test_runtime_image_tamper_is_rejected(tmp_path: Path) -> None:
    result, sealed = _build(tmp_path, "image-tamper")
    image = Path(str(result["image"]))
    image.write_bytes(image.read_bytes() + b"tamper")
    with pytest.raises(RuntimePackageIntegrityError, match="image hash mismatch"):
        validate_runtime_package_receipt(sealed["package_receipt"])


def test_import_receipt_tamper_is_rejected(tmp_path: Path) -> None:
    result, sealed = _build(tmp_path, "import-receipt-tamper")
    receipt = Path(str(result["receipt"]))
    receipt.write_text(receipt.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    with pytest.raises(RuntimePackageIntegrityError, match="import receipt hash mismatch"):
        validate_runtime_package_receipt(sealed["package_receipt"])


def test_rig_edit_tamper_is_rejected(tmp_path: Path) -> None:
    result, sealed = _build(tmp_path, "rig-edit-tamper", edited=True)
    edit = Path(str(result["rig_edit"]))
    edit.write_text(edit.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    with pytest.raises(RuntimePackageIntegrityError, match="rig edit provenance hash mismatch"):
        validate_runtime_package_receipt(sealed["package_receipt"])


def test_package_receipt_rejects_path_traversal(tmp_path: Path) -> None:
    _, sealed = _build(tmp_path, "traversal")
    receipt = Path(str(sealed["package_receipt"]))
    document = json.loads(receipt.read_text(encoding="utf-8"))
    document["package"]["manifest"] = "../manifest.json"
    receipt.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(RuntimePackageIntegrityError, match="escapes package directory"):
        validate_runtime_package_receipt(receipt)
