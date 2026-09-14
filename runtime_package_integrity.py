from __future__ import annotations

"""Durable, non-destructive validation for reusable runtime character packages.

A runtime package is intentionally kept separate from the immutable import
receipt and the existing krolik.runtime-character/1 manifest.  This module adds
a sidecar integrity contract that links those existing artifacts without
silently changing either versioned schema.
"""

from hashlib import sha256
from pathlib import Path
from typing import Any
import json

from import_integrity import ImportIntegrityError, validate_import_receipt


RUNTIME_PACKAGE_RECEIPT_SCHEMA = "krolik.runtime-package-receipt/1"
RUNTIME_PACKAGE_RECEIPT_FORMAT_VERSION = 1


class RuntimePackageIntegrityError(ValueError):
    pass


def digest_file(path: str | Path) -> str:
    source = Path(path)
    h = sha256()
    with source.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _require_file(value: Any, label: str) -> Path:
    path = Path(str(value or ""))
    if not path.is_file():
        raise RuntimePackageIntegrityError(f"missing {label}: {path}")
    return path


def _read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimePackageIntegrityError(f"invalid {label}: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimePackageIntegrityError(f"{label} must be a JSON object")
    return value


def _contained_file(base: Path, relative_name: Any, label: str) -> Path:
    raw = str(relative_name or "")
    if not raw:
        raise RuntimePackageIntegrityError(f"missing {label} path")
    candidate = (base / raw).resolve()
    try:
        candidate.relative_to(base.resolve())
    except ValueError as exc:
        raise RuntimePackageIntegrityError(f"{label} escapes package directory") from exc
    if not candidate.is_file():
        raise RuntimePackageIntegrityError(f"missing {label}: {candidate}")
    return candidate


def build_runtime_package_receipt(
    *,
    package_folder: str | Path,
    manifest_path: str | Path,
    image_path: str | Path,
    import_receipt_path: str | Path,
    rig_edit_path: str | Path | None = None,
) -> dict[str, Any]:
    """Build a sidecar receipt from already-created package/import artifacts."""
    folder = Path(package_folder).resolve()
    manifest = _require_file(manifest_path, "runtime manifest").resolve()
    image = _require_file(image_path, "runtime image").resolve()
    import_receipt = _require_file(import_receipt_path, "import receipt").resolve()
    try:
        manifest_rel = manifest.relative_to(folder).as_posix()
        image_rel = image.relative_to(folder).as_posix()
    except ValueError as exc:
        raise RuntimePackageIntegrityError("runtime package files must stay inside package folder") from exc

    manifest_doc = _read_json(manifest, "runtime manifest")
    if manifest_doc.get("schema") != "krolik.runtime-character/1":
        raise RuntimePackageIntegrityError("unsupported runtime manifest schema")
    character = manifest_doc.get("character")
    visual = manifest_doc.get("visual")
    rig = manifest_doc.get("rig")
    if not isinstance(character, dict) or not isinstance(visual, dict) or not isinstance(rig, dict):
        raise RuntimePackageIntegrityError("runtime manifest is missing character/visual/rig records")
    character_id = str(character.get("id") or "")
    if not character_id:
        raise RuntimePackageIntegrityError("runtime manifest character id is empty")

    image_sha = digest_file(image)
    visual_sha = str(visual.get("sha256") or "")
    if len(visual_sha) != 64 or visual_sha != image_sha:
        raise RuntimePackageIntegrityError("runtime image hash does not match manifest visual.sha256")

    import_report = validate_import_receipt(import_receipt)
    if str(import_report.get("character_id") or "") != character_id:
        raise RuntimePackageIntegrityError("runtime/import character id mismatch")

    rig_edit: dict[str, Any] | None = None
    if rig_edit_path:
        edit_path = _require_file(rig_edit_path, "rig edit provenance").resolve()
        edit_doc = _read_json(edit_path, "rig edit provenance")
        if edit_doc.get("schema") != "krolik.rig-joint-overrides/1":
            raise RuntimePackageIntegrityError("unsupported rig edit provenance schema")
        if str(edit_doc.get("character_id") or "") != character_id:
            raise RuntimePackageIntegrityError("rig edit/runtime character id mismatch")
        if str(edit_doc.get("source_sha256") or "") != str(import_report.get("source_sha256") or ""):
            raise RuntimePackageIntegrityError("rig edit/import source hash mismatch")
        if str(edit_doc.get("cutout_sha256") or "") != str(import_report.get("cutout_sha256") or ""):
            raise RuntimePackageIntegrityError("rig edit/import cutout hash mismatch")
        rig_edit = {
            "path": str(edit_path),
            "sha256": digest_file(edit_path),
        }

    return {
        "schema": RUNTIME_PACKAGE_RECEIPT_SCHEMA,
        "format_version": RUNTIME_PACKAGE_RECEIPT_FORMAT_VERSION,
        "character_id": character_id,
        "package": {
            "folder": str(folder),
            "manifest": manifest_rel,
            "manifest_sha256": digest_file(manifest),
            "image": image_rel,
            "image_sha256": image_sha,
        },
        "import": {
            "receipt": str(import_receipt),
            "receipt_sha256": digest_file(import_receipt),
            "source_sha256": str(import_report["source_sha256"]),
            "cutout_sha256": str(import_report["cutout_sha256"]),
        },
        "rig_edit": rig_edit,
    }


def write_runtime_package_receipt(document: dict[str, Any], path: str | Path) -> str:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(document, ensure_ascii=False, indent=2), encoding="utf-8")
    return str(target)


def validate_runtime_package_receipt(receipt_path: str | Path) -> dict[str, Any]:
    """Validate a package before reusing/reopening it in Godot or future UI."""
    receipt = _require_file(receipt_path, "runtime package receipt").resolve()
    document = _read_json(receipt, "runtime package receipt")
    if (
        document.get("schema") != RUNTIME_PACKAGE_RECEIPT_SCHEMA
        or int(document.get("format_version", 0)) != RUNTIME_PACKAGE_RECEIPT_FORMAT_VERSION
    ):
        raise RuntimePackageIntegrityError("unsupported runtime package receipt schema/version")

    package = document.get("package")
    imported = document.get("import")
    if not isinstance(package, dict) or not isinstance(imported, dict):
        raise RuntimePackageIntegrityError("runtime package receipt is missing package/import records")

    folder = Path(str(package.get("folder") or "")).resolve()
    if not folder.is_dir():
        raise RuntimePackageIntegrityError(f"missing runtime package folder: {folder}")
    manifest = _contained_file(folder, package.get("manifest"), "runtime manifest")
    image = _contained_file(folder, package.get("image"), "runtime image")

    expected_manifest_sha = str(package.get("manifest_sha256") or "")
    expected_image_sha = str(package.get("image_sha256") or "")
    if len(expected_manifest_sha) != 64 or digest_file(manifest) != expected_manifest_sha:
        raise RuntimePackageIntegrityError("runtime manifest hash mismatch")
    if len(expected_image_sha) != 64 or digest_file(image) != expected_image_sha:
        raise RuntimePackageIntegrityError("runtime image hash mismatch")

    manifest_doc = _read_json(manifest, "runtime manifest")
    if manifest_doc.get("schema") != "krolik.runtime-character/1":
        raise RuntimePackageIntegrityError("unsupported runtime manifest schema")
    character = manifest_doc.get("character")
    visual = manifest_doc.get("visual")
    rig = manifest_doc.get("rig")
    if not isinstance(character, dict) or not isinstance(visual, dict) or not isinstance(rig, dict):
        raise RuntimePackageIntegrityError("runtime manifest is missing character/visual/rig records")
    character_id = str(character.get("id") or "")
    if not character_id or character_id != str(document.get("character_id") or ""):
        raise RuntimePackageIntegrityError("runtime package character id mismatch")
    if str(visual.get("file") or "") != str(package.get("image") or ""):
        raise RuntimePackageIntegrityError("runtime manifest image path differs from package receipt")
    if str(visual.get("sha256") or "") != expected_image_sha:
        raise RuntimePackageIntegrityError("runtime manifest image hash differs from package receipt")

    skinning = rig.get("skinning")
    if not isinstance(skinning, dict) or int(skinning.get("format_version", 0)) != 1:
        raise RuntimePackageIntegrityError("runtime skinning recipe missing/unsupported")
    if str(skinning.get("backend") or "") != "godot_polygon2d_grid_v1":
        raise RuntimePackageIntegrityError("runtime skinning backend unsupported")
    joints = rig.get("joints")
    bones = rig.get("bones")
    if not isinstance(joints, dict) or not joints or not isinstance(bones, list) or not bones:
        raise RuntimePackageIntegrityError("runtime rig is empty")

    import_receipt = _require_file(imported.get("receipt"), "import receipt").resolve()
    expected_import_receipt_sha = str(imported.get("receipt_sha256") or "")
    if len(expected_import_receipt_sha) != 64 or digest_file(import_receipt) != expected_import_receipt_sha:
        raise RuntimePackageIntegrityError("import receipt hash mismatch")
    try:
        import_report = validate_import_receipt(import_receipt)
    except ImportIntegrityError as exc:
        raise RuntimePackageIntegrityError(str(exc)) from exc
    if str(import_report.get("character_id") or "") != character_id:
        raise RuntimePackageIntegrityError("runtime/import character id mismatch")
    if str(import_report.get("source_sha256") or "") != str(imported.get("source_sha256") or ""):
        raise RuntimePackageIntegrityError("runtime/import source hash mismatch")
    if str(import_report.get("cutout_sha256") or "") != str(imported.get("cutout_sha256") or ""):
        raise RuntimePackageIntegrityError("runtime/import cutout hash mismatch")

    rig_edit = document.get("rig_edit")
    if rig_edit is not None:
        if not isinstance(rig_edit, dict):
            raise RuntimePackageIntegrityError("rig edit receipt must be null or object")
        edit_path = _require_file(rig_edit.get("path"), "rig edit provenance").resolve()
        expected_edit_sha = str(rig_edit.get("sha256") or "")
        if len(expected_edit_sha) != 64 or digest_file(edit_path) != expected_edit_sha:
            raise RuntimePackageIntegrityError("rig edit provenance hash mismatch")
        edit_doc = _read_json(edit_path, "rig edit provenance")
        if edit_doc.get("schema") != "krolik.rig-joint-overrides/1":
            raise RuntimePackageIntegrityError("unsupported rig edit provenance schema")
        if str(edit_doc.get("character_id") or "") != character_id:
            raise RuntimePackageIntegrityError("rig edit/runtime character id mismatch")
        if str(edit_doc.get("source_sha256") or "") != str(import_report.get("source_sha256") or ""):
            raise RuntimePackageIntegrityError("rig edit/import source hash mismatch")
        if str(edit_doc.get("cutout_sha256") or "") != str(import_report.get("cutout_sha256") or ""):
            raise RuntimePackageIntegrityError("rig edit/import cutout hash mismatch")

    return {
        "ok": True,
        "schema": document["schema"],
        "character_id": character_id,
        "receipt": str(receipt),
        "package_folder": str(folder),
        "manifest": str(manifest),
        "image": str(image),
        "manifest_sha256": expected_manifest_sha,
        "image_sha256": expected_image_sha,
        "source_sha256": str(import_report["source_sha256"]),
        "cutout_sha256": str(import_report["cutout_sha256"]),
        "rig_edit_verified": rig_edit is not None,
    }
