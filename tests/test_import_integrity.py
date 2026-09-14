from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw
import pytest

from character_import import prepare_character_asset
from import_integrity import ImportIntegrityError, validate_built_import, validate_import_receipt


def _asset(tmp_path: Path):
    source = tmp_path / "source.png"
    image = Image.new("RGBA", (64, 96), (0, 0, 0, 0))
    ImageDraw.Draw(image).rectangle((20, 8, 44, 88), fill=(80, 90, 100, 255))
    image.save(source, "PNG")
    return prepare_character_asset(tmp_path / "project", source, "integrity-char")


def test_receipt_integrity_accepts_untouched_assets(tmp_path: Path) -> None:
    asset = _asset(tmp_path)
    report = validate_import_receipt(asset["receipt"])
    assert report["ok"] is True
    assert report["character_id"] == "integrity-char"
    assert report["source_sha256"] == asset["source_sha256"]
    assert report["cutout_sha256"] == asset["cutout_sha256"]


def test_integrity_detects_original_tampering(tmp_path: Path) -> None:
    asset = _asset(tmp_path)
    Path(asset["original"]).write_bytes(b"tampered")
    with pytest.raises(ImportIntegrityError, match="original hash mismatch"):
        validate_import_receipt(asset["receipt"])


def test_integrity_detects_derived_cutout_tampering(tmp_path: Path) -> None:
    asset = _asset(tmp_path)
    Path(asset["cutout"]).write_bytes(b"tampered")
    with pytest.raises(ImportIntegrityError, match="cutout hash mismatch"):
        validate_import_receipt(asset["receipt"])


def test_build_result_cross_check_rejects_receipt_mismatch(tmp_path: Path) -> None:
    asset = _asset(tmp_path)
    forged = dict(asset)
    forged["source_sha256"] = "0" * 64
    with pytest.raises(ImportIntegrityError, match="source_sha256"):
        validate_built_import(forged)
