from __future__ import annotations

"""Filesystem-first character image import for the source-independent KROLIK core.

The legacy graphical/backend source is currently unavailable, so this module is
intentionally independent of app.py/database code. It establishes the product
invariants that recovered UI code must call into later:

- source bytes are immutable and content-addressed;
- all image processing creates derived assets;
- cutout preparation is deterministic and versioned;
- auto-rig may be corrected through a versioned authoring document;
- the existing rig/runtime-package contracts remain the only runtime path.
"""

from hashlib import sha256
from pathlib import Path
from typing import Any
import json
import os
import shutil
import tempfile

import numpy as np
from PIL import Image, ImageOps

from rig_edit import apply_joint_overrides
from rig_tools import detect_rig
from runtime_package import build_manifest, write_package


ASSET_IMPORT_SCHEMA = "krolik.asset-import/1"
ASSET_IMPORT_FORMAT_VERSION = 1
CUTOUT_ALGORITHM_VERSION = 1
MAX_IMAGE_PIXELS = 40_000_000
SUPPORTED_FORMATS = {"PNG", "JPEG", "WEBP", "BMP"}
CUTOUT_MODES = {"auto", "alpha-only", "opaque"}


def _safe_id(value: str) -> str:
    safe = "".join(ch if (ch.isalnum() or ch in "-_.") else "_" for ch in str(value)).strip("._")
    return safe or "character"


def _normalize_cutout_mode(mode: str) -> str:
    normalized = str(mode or "auto").strip().lower()
    if normalized not in CUTOUT_MODES:
        raise ValueError("cutout_mode must be one of: auto, alpha-only, opaque")
    return normalized


def _sha256_bytes(data: bytes) -> str:
    return sha256(data).hexdigest()


def _atomic_write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass


def _atomic_write_text(path: Path, text: str) -> None:
    _atomic_write_bytes(path, text.encode("utf-8"))


def _normalized_image(source: Path) -> tuple[Image.Image, str]:
    try:
        with Image.open(source) as opened:
            fmt = str(opened.format or "").upper()
            if fmt not in SUPPORTED_FORMATS:
                raise ValueError(f"unsupported image format: {fmt or 'unknown'}")
            width, height = opened.size
            if width <= 0 or height <= 0:
                raise ValueError("image has invalid dimensions")
            if width * height > MAX_IMAGE_PIXELS:
                raise ValueError(f"image exceeds {MAX_IMAGE_PIXELS} pixel safety limit")
            normalized = ImageOps.exif_transpose(opened).convert("RGBA")
    except (OSError, Image.DecompressionBombError) as exc:
        raise ValueError(f"unable to decode image: {exc}") from exc
    return normalized, fmt


def _alpha_coverage(image: Image.Image) -> float:
    alpha = np.asarray(image.getchannel("A"), dtype=np.uint8)
    return float(np.mean(alpha > 16))


def _has_meaningful_alpha(image: Image.Image) -> bool:
    alpha = np.asarray(image.getchannel("A"), dtype=np.uint8)
    return bool(int(alpha.min()) < 245 and float(np.mean(alpha < 245)) >= 0.001)


def _uniform_border_cutout(image: Image.Image) -> tuple[Image.Image, dict[str, Any]]:
    """Remove a near-uniform border background without pretending to solve matting.

    This deliberately handles the reliable subset (plain/studio-like borders).
    Busy photographic backgrounds are retained and marked for review rather than
    being destructively over-segmented. The algorithm is offline/import-time.
    """
    rgb = np.asarray(image.convert("RGB"), dtype=np.int16)
    height, width = rgb.shape[:2]
    border = np.concatenate((rgb[0, :, :], rgb[-1, :, :], rgb[:, 0, :], rgb[:, -1, :]), axis=0)
    background = np.median(border, axis=0)
    border_distance = np.sqrt(np.sum((border.astype(np.float32) - background) ** 2, axis=1))
    border_p90 = float(np.percentile(border_distance, 90.0))

    threshold = float(np.clip(26.0 + border_p90 * 2.2, 26.0, 88.0))
    distance = np.sqrt(np.sum((rgb.astype(np.float32) - background) ** 2, axis=2))
    alpha = np.clip(
        (distance - threshold * 0.45) * (255.0 / max(1.0, threshold * 0.70)),
        0.0,
        255.0,
    ).astype(np.uint8)

    foreground_share = float(np.mean(alpha > 24))
    border_stability = max(0.0, min(1.0, 1.0 - border_p90 / 64.0))
    coverage_quality = 1.0 if 0.025 <= foreground_share <= 0.92 else 0.25
    confidence = round(border_stability * coverage_quality, 4)
    warnings: list[str] = []

    fallback_opaque = foreground_share < 0.015 or foreground_share > 0.965
    if fallback_opaque:
        alpha = np.full((height, width), 255, dtype=np.uint8)
        confidence = 0.0
        warnings.append("auto_cutout_fallback_opaque")
    elif border_p90 > 18.0:
        warnings.append("background_border_is_not_uniform")

    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()
    rgba[:, :, 3] = alpha
    result = Image.fromarray(rgba, mode="RGBA")
    return result, {
        "method": "uniform-border-v1" if not fallback_opaque else "opaque-fallback-v1",
        "confidence": confidence,
        "review_required": bool(fallback_opaque or confidence < 0.72),
        "foreground_share": round(float(np.mean(alpha > 16)), 6),
        "background_rgb": [int(round(float(v))) for v in background],
        "border_p90": round(border_p90, 4),
        "threshold": round(threshold, 4),
        "warnings": warnings,
    }


def _prepare_cutout(image: Image.Image, mode: str) -> tuple[Image.Image, dict[str, Any]]:
    normalized_mode = _normalize_cutout_mode(mode)
    if _has_meaningful_alpha(image):
        return image.copy(), {
            "method": "embedded-alpha",
            "confidence": 1.0,
            "review_required": False,
            "foreground_share": round(_alpha_coverage(image), 6),
            "warnings": [],
        }
    if normalized_mode == "auto":
        return _uniform_border_cutout(image)

    opaque = image.copy()
    opaque.putalpha(255)
    return opaque, {
        "method": "opaque-preserve",
        "confidence": 0.0,
        "review_required": True,
        "foreground_share": 1.0,
        "warnings": ["source_has_no_embedded_alpha"],
    }


def prepare_character_asset(
    project_root: str | Path,
    source_image: str | Path,
    character_id: str,
    *,
    cutout_mode: str = "auto",
) -> dict[str, Any]:
    """Store immutable source bytes and create a versioned derived cutout PNG."""
    root = Path(project_root).resolve()
    source = Path(source_image).resolve()
    if not source.is_file():
        raise FileNotFoundError(source)

    mode_key = _normalize_cutout_mode(cutout_mode)
    original_bytes = source.read_bytes()
    source_sha = _sha256_bytes(original_bytes)
    normalized, source_format = _normalized_image(source)
    safe_id = _safe_id(character_id)

    extension = source.suffix.lower()
    if extension not in {".png", ".jpg", ".jpeg", ".webp", ".bmp"}:
        extension = ".img"
    import_root = root / "imports" / safe_id
    original_path = import_root / "originals" / f"{source_sha}{extension}"
    if original_path.exists():
        existing = original_path.read_bytes()
        if _sha256_bytes(existing) != source_sha:
            raise RuntimeError("immutable original store hash mismatch")
    else:
        original_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, original_path)
        if original_path.read_bytes() != original_bytes:
            raise RuntimeError("immutable original copy differs from source bytes")

    cutout, cutout_info = _prepare_cutout(normalized, mode_key)
    cutout_path = (
        import_root
        / "derived"
        / "cutout"
        / f"v{CUTOUT_ALGORITHM_VERSION}"
        / mode_key
        / f"{source_sha}.png"
    )
    cutout_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=cutout_path.stem + ".", suffix=".png", dir=str(cutout_path.parent))
    os.close(fd)
    try:
        cutout.save(temp_name, "PNG", optimize=True)
        os.replace(temp_name, cutout_path)
    finally:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
    cutout_sha = _sha256_bytes(cutout_path.read_bytes())

    receipt = {
        "schema": ASSET_IMPORT_SCHEMA,
        "format_version": ASSET_IMPORT_FORMAT_VERSION,
        "cutout_algorithm_version": CUTOUT_ALGORITHM_VERSION,
        "character_id": str(character_id),
        "source": {
            "sha256": source_sha,
            "format": source_format,
            "original_path": str(original_path),
            "original_bytes": len(original_bytes),
        },
        "derived": {
            "requested_mode": mode_key,
            "cutout_path": str(cutout_path),
            "cutout_sha256": cutout_sha,
            "width": int(cutout.width),
            "height": int(cutout.height),
            "alpha_coverage": round(_alpha_coverage(cutout), 6),
            **cutout_info,
        },
    }
    receipt_path = (
        import_root
        / "receipts"
        / f"v{ASSET_IMPORT_FORMAT_VERSION}"
        / mode_key
        / f"{source_sha}.json"
    )
    _atomic_write_text(receipt_path, json.dumps(receipt, ensure_ascii=False, indent=2))

    return {
        "character_id": str(character_id),
        "source_sha256": source_sha,
        "original": str(original_path),
        "cutout": str(cutout_path),
        "cutout_sha256": cutout_sha,
        "receipt": str(receipt_path),
        "width": int(cutout.width),
        "height": int(cutout.height),
        "cutout_mode": mode_key,
        "cutout_method": str(cutout_info["method"]),
        "cutout_confidence": float(cutout_info["confidence"]),
        "review_required": bool(cutout_info["review_required"]),
        "alpha_coverage": round(_alpha_coverage(cutout), 6),
        "warnings": list(cutout_info.get("warnings", [])),
    }


def _default_mind() -> dict[str, Any]:
    return {
        "enabled": 1,
        "state": "idle",
        "home_cell_id": "default-room",
        "profile_json": json.dumps({
            "mobility": "auto",
            "routine": "explorer",
            "autonomy": 0.90,
            "wander": 0.90,
            "social": 0.20,
            "rest_threshold": 0.20,
            "curiosity_threshold": 0.60,
            "home_bias": 0.25,
            "walk_speed": 1.0,
        }),
        "needs_json": json.dumps({
            "energy": 0.95,
            "comfort": 0.80,
            "curiosity": 0.65,
            "social": 0.20,
        }),
        "runtime_json": "{}",
    }


def _persist_rig_edit(
    root: Path,
    asset: dict[str, Any],
    character_id: str,
    backend: str,
    report: dict[str, Any],
) -> str | None:
    if int(report.get("override_count", 0)) <= 0:
        return None
    document = {
        **report,
        "character_id": str(character_id),
        "source_sha256": str(asset["source_sha256"]),
        "cutout_sha256": str(asset["cutout_sha256"]),
        "detector_backend": str(backend),
    }
    canonical = json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    edit_sha = _sha256_bytes(canonical)
    edit_path = (
        root
        / "imports"
        / _safe_id(character_id)
        / "derived"
        / "rig_edits"
        / "v1"
        / str(asset["source_sha256"])
        / f"{edit_sha}.json"
    )
    _atomic_write_text(edit_path, json.dumps(document, ensure_ascii=False, indent=2))
    return str(edit_path)


def build_character_runtime_package(
    project_root: str | Path,
    source_image: str | Path,
    character_id: str,
    *,
    name: str | None = None,
    cutout_mode: str = "auto",
    prefer_ai_rig: bool = True,
    joint_overrides: dict[str, Any] | None = None,
    mind: dict[str, Any] | None = None,
    cell_id: str | None = None,
) -> dict[str, Any]:
    """End-to-end headless import using the existing production runtime contracts."""
    root = Path(project_root).resolve()
    asset = prepare_character_asset(root, source_image, character_id, cutout_mode=cutout_mode)
    detection = detect_rig(asset["cutout"], prefer_ai=prefer_ai_rig)
    settings = dict(detection.settings)
    joints, edit_report = apply_joint_overrides(detection.joints, joint_overrides)
    rig_edit_path = _persist_rig_edit(
        root,
        asset,
        str(character_id),
        str(settings.get("backend") or "none"),
        edit_report,
    )

    character = {
        "id": str(character_id),
        "name": str(name or character_id),
        "status": "imported",
    }
    image_version = {
        "id": 0,
        "width": int(asset["width"]),
        "height": int(asset["height"]),
        "kind": "derived-cutout",
    }
    rig = {
        "id": 0,
        "rest_json": json.dumps({"joints": joints}, ensure_ascii=False),
        "settings_json": json.dumps(settings, ensure_ascii=False),
    }
    mind_doc = dict(mind) if mind is not None else _default_mind()
    effective_cell = cell_id or str(mind_doc.get("home_cell_id") or "default-room")

    manifest = build_manifest(
        character=character,
        image_version=image_version,
        rig=rig,
        mind=mind_doc,
        cell_id=effective_cell,
    )
    package = write_package(root, str(character_id), asset["cutout"], manifest)
    manifest_path = Path(str(package["manifest"]))
    written = json.loads(manifest_path.read_text(encoding="utf-8"))
    skin = written.get("rig", {}).get("skinning", {})

    return {
        **asset,
        "backend": str(written.get("rig", {}).get("backend") or "none"),
        "rig_score": float(written.get("quality", {}).get("rig_score", 0.0)),
        "runtime_ready": bool(written.get("quality", {}).get("runtime_ready")),
        "joints": len(written.get("rig", {}).get("joints", {})),
        "bones": len(written.get("rig", {}).get("bones", [])),
        "vertices": len(skin.get("vertices", [])),
        "triangles": len(skin.get("triangles", [])) // 3,
        "bone_weights": len(skin.get("bone_weights", [])),
        "collision_proxies": len(written.get("physics", {}).get("collision", [])),
        "joint_override_count": int(edit_report.get("override_count", 0)),
        "joint_changed_count": int(edit_report.get("changed_count", 0)),
        "joint_changed": list(edit_report.get("changed_joints", [])),
        "joint_max_delta": float(edit_report.get("max_delta", 0.0)),
        "rig_edit": rig_edit_path,
        "manifest": str(manifest_path),
        "image": str(package["image"]),
    }
