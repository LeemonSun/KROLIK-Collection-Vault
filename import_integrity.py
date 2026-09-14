from __future__ import annotations

"""Non-destructive integrity validation for imported character assets.

This is deliberately separate from the versioned import/runtime schemas: it
verifies their current on-disk claims without mutating originals or derived
assets. It is suitable for save/reload, CLI and future graphical UI gates.
"""

from hashlib import sha256
from pathlib import Path
from typing import Any
import json


class ImportIntegrityError(ValueError):
    pass


def _digest(path: Path) -> str:
    h = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _require_file(path_value: Any, label: str) -> Path:
    path = Path(str(path_value or ""))
    if not path.is_file():
        raise ImportIntegrityError(f"missing {label}: {path}")
    return path


def validate_import_receipt(receipt_path: str | Path) -> dict[str, Any]:
    """Validate receipt schema plus original/cutout hashes and dimensions."""
    path = _require_file(receipt_path, "import receipt")
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ImportIntegrityError(f"invalid import receipt: {exc}") from exc

    if doc.get("schema") != "krolik.asset-import/1" or int(doc.get("format_version", 0)) != 1:
        raise ImportIntegrityError("unsupported import receipt schema/version")
    source = doc.get("source")
    derived = doc.get("derived")
    if not isinstance(source, dict) or not isinstance(derived, dict):
        raise ImportIntegrityError("import receipt is missing source/derived records")

    original = _require_file(source.get("original_path"), "immutable original")
    cutout = _require_file(derived.get("cutout_path"), "derived cutout")
    source_sha = str(source.get("sha256") or "")
    cutout_sha = str(derived.get("cutout_sha256") or "")
    if len(source_sha) != 64 or _digest(original) != source_sha:
        raise ImportIntegrityError("immutable original hash mismatch")
    if len(cutout_sha) != 64 or _digest(cutout) != cutout_sha:
        raise ImportIntegrityError("derived cutout hash mismatch")

    return {
        "schema": doc["schema"],
        "character_id": str(doc.get("character_id") or ""),
        "source_sha256": source_sha,
        "cutout_sha256": cutout_sha,
        "original": str(original),
        "cutout": str(cutout),
        "width": int(derived.get("width", 0)),
        "height": int(derived.get("height", 0)),
        "review_required": bool(derived.get("review_required", False)),
        "ok": True,
    }


def validate_built_import(result: dict[str, Any]) -> dict[str, Any]:
    """Cross-check a build result against its durable import receipt."""
    if not isinstance(result, dict):
        raise ImportIntegrityError("build result must be a dictionary")
    report = validate_import_receipt(result.get("receipt"))
    expected = {
        "character_id": str(result.get("character_id") or ""),
        "source_sha256": str(result.get("source_sha256") or ""),
        "cutout_sha256": str(result.get("cutout_sha256") or ""),
    }
    for key, value in expected.items():
        if value and str(report.get(key)) != value:
            raise ImportIntegrityError(f"build result/receipt mismatch: {key}")
    return report
