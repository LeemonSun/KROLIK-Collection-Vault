from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from character_import import build_character_runtime_package
from import_integrity import validate_built_import
from runtime_package_integrity import seal_built_runtime_package, validate_runtime_package_receipt


CHARACTER_ID = "ci_dwpose_slice"


def build_dwpose_vertical_slice(source: Path, output_root: Path) -> dict[str, object]:
    output_root = output_root.resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    result = build_character_runtime_package(
        output_root,
        source.resolve(),
        CHARACTER_ID,
        name="CI DWPose Product Slice",
        cutout_mode="opaque",
        prefer_ai_rig=True,
        cell_id="ci-room",
    )

    if result.get("backend") != "dwpose-onnx":
        raise RuntimeError(f"AI product slice did not use DWPose: {result.get('backend')}")
    if bool(result.get("rig_review_required")):
        raise RuntimeError("successful DWPose rig was incorrectly marked for rig review")
    confidence = float(result.get("pose_confidence") or 0.0)
    if confidence < 0.30:
        raise RuntimeError(f"DWPose confidence is unexpectedly low: {confidence}")
    if not bool(result.get("runtime_ready")) or float(result.get("rig_score") or 0.0) < 99.0:
        raise RuntimeError(f"DWPose runtime package is not ready: {result}")
    if int(result.get("joints") or 0) != 15 or int(result.get("bones") or 0) != 14:
        raise RuntimeError(f"DWPose KROLIK mapping incomplete: {result}")
    if int(result.get("bone_weights") or 0) != 14 or int(result.get("collision_proxies") or 0) != 14:
        raise RuntimeError(f"DWPose package skin/physics incomplete: {result}")

    validate_built_import(result)
    sealed = seal_built_runtime_package(result)
    receipt = Path(str(sealed["package_receipt"]))
    validate_runtime_package_receipt(receipt)
    result["package_receipt"] = str(receipt)

    manifest = json.loads(Path(str(result["manifest"])).read_text(encoding="utf-8"))
    rig = manifest.get("rig", {})
    if rig.get("backend") != "dwpose-onnx":
        raise RuntimeError("DWPose backend provenance did not survive manifest write")
    if float(rig.get("pose_confidence", confidence) or confidence) < 0.30:
        raise RuntimeError("DWPose confidence provenance did not survive package build")

    return result


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a real DWPose -> runtime-package product vertical slice"
    )
    parser.add_argument("source", help="Real image used for DWPose product integration smoke")
    parser.add_argument("--output-root", default="runtime_godot/.ci_dwpose_slice")
    args = parser.parse_args()

    model = os.environ.get("KROLIK_DWPOSE_MODEL", "")
    if not model:
        raise RuntimeError("KROLIK_DWPOSE_MODEL must point to the verified ONNX model")

    metrics = build_dwpose_vertical_slice(Path(args.source), Path(args.output_root))
    ordered = [
        "character_id", "backend", "pose_confidence", "rig_review_required", "rig_score",
        "runtime_ready", "joints", "bones", "vertices", "triangles", "bone_weights",
        "collision_proxies", "manifest", "image", "package_receipt",
    ]
    print("KROLIK_DWPOSE_PRODUCT_SLICE " + " ".join(f"{key}={metrics.get(key)}" for key in ordered))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
