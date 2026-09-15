from __future__ import annotations

"""Run the production character pipeline against a mandatory gold character.

This tool intentionally does not hard-code landmark coordinates before the first
real model run. It proves structural/geometry invariants, records the actual
DWPose result, and emits a human-inspectable skeleton overlay + JSON report.
Once a verified baseline exists, CI can additionally compare landmark drift.
"""

import argparse
from hashlib import sha256
import json
import math
from pathlib import Path
import sys
from typing import Any

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from character_import import build_character_runtime_package
from import_integrity import ImportIntegrityError, validate_built_import
from rig_tools import DEFAULT_BONES, JOINT_ORDER
from runtime_package_integrity import RuntimePackageIntegrityError, seal_built_runtime_package
from tools.materialize_gold_character import DEFAULT_SPEC, materialize


def _finite_unit(value: Any) -> bool:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return False
    return math.isfinite(number) and 0.0 <= number <= 1.0


def _joint_map(manifest: dict[str, Any]) -> dict[str, dict[str, float]]:
    raw = manifest.get("rig", {}).get("joints", {})
    if not isinstance(raw, dict):
        return {}
    out: dict[str, dict[str, float]] = {}
    for name, point in raw.items():
        if isinstance(point, dict) and _finite_unit(point.get("x")) and _finite_unit(point.get("y")):
            out[str(name)] = {"x": float(point["x"]), "y": float(point["y"])}
    return out


def _distance(a: dict[str, float], b: dict[str, float]) -> float:
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def _geometry_checks(joints: dict[str, dict[str, float]]) -> list[str]:
    errors: list[str] = []
    missing = [name for name in JOINT_ORDER if name not in joints]
    if missing:
        return [f"missing joints: {','.join(missing)}"]

    # Broad body-order invariants only. This reference has close/crossed legs
    # and partially occluded arms, so we do not fake brittle left/right X gates.
    if not joints["head"]["y"] < joints["neck"]["y"] < joints["pelvis"]["y"]:
        errors.append("head/neck/pelvis vertical order is invalid")
    for side in ("left", "right"):
        if joints[f"{side}_knee"]["y"] <= joints[f"{side}_hip"]["y"]:
            errors.append(f"{side} knee is not below hip")
        if joints[f"{side}_ankle"]["y"] <= joints[f"{side}_knee"]["y"]:
            errors.append(f"{side} ankle is not below knee")

    for a, b in DEFAULT_BONES:
        length = _distance(joints[a], joints[b])
        if length < 0.008:
            errors.append(f"degenerate bone {a}->{b}: {length:.6f}")
        if length > 0.65:
            errors.append(f"implausibly long bone {a}->{b}: {length:.6f}")
    return errors


def _draw_overlay(image_path: Path, joints: dict[str, dict[str, float]], output: Path) -> None:
    with Image.open(image_path) as opened:
        image = opened.convert("RGB")
    draw = ImageDraw.Draw(image)
    w, h = image.size

    def px(point: dict[str, float]) -> tuple[int, int]:
        return (int(round(point["x"] * (w - 1))), int(round(point["y"] * (h - 1))))

    for a, b in DEFAULT_BONES:
        if a in joints and b in joints:
            draw.line([px(joints[a]), px(joints[b])], fill=(255, 64, 64), width=max(2, w // 280))
    radius = max(4, w // 180)
    for name in JOINT_ORDER:
        if name not in joints:
            continue
        x, y = px(joints[name])
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(32, 255, 128), outline=(0, 0, 0), width=2)
        draw.text((x + radius + 2, y - radius), name, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, "PNG", optimize=True)


def run_probe(spec_path: Path, output_root: Path, require_dwpose: bool) -> tuple[dict[str, Any], list[str]]:
    output_root.mkdir(parents=True, exist_ok=True)
    source = output_root / "gold_elf_v1.webp"
    materialized = materialize(spec_path, source)
    workspace = output_root / "workspace"
    result = build_character_runtime_package(
        workspace,
        source,
        "gold-elf-v1",
        name="Gold Elf V1",
        cutout_mode="auto",
        prefer_ai_rig=True,
    )

    failures: list[str] = []
    try:
        import_integrity = validate_built_import(result)
    except ImportIntegrityError as exc:
        import_integrity = {"error": str(exc)}
        failures.append(f"import integrity: {exc}")
    try:
        package_integrity = seal_built_runtime_package(result)
    except RuntimePackageIntegrityError as exc:
        package_integrity = {"error": str(exc)}
        failures.append(f"runtime package integrity: {exc}")

    manifest_path = Path(result["manifest"])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    joints = _joint_map(manifest)
    failures.extend(_geometry_checks(joints))
    rig_confidence = manifest.get("rig", {}).get("confidence", {})
    if not isinstance(rig_confidence, dict):
        rig_confidence = {}
    joint_confidence = rig_confidence.get("joints", {})
    if not isinstance(joint_confidence, dict):
        joint_confidence = {}
    low_confidence_joints = rig_confidence.get("low_confidence_joints", [])
    if not isinstance(low_confidence_joints, list):
        low_confidence_joints = []
    guarded_joints = rig_confidence.get("guarded_joints", [])
    if not isinstance(guarded_joints, list):
        guarded_joints = []
    uncertain_limbs = rig_confidence.get("uncertain_limbs", [])
    if not isinstance(uncertain_limbs, list):
        uncertain_limbs = []
    exact_anchor_joints = rig_confidence.get("exact_anchor_joints", [])
    if not isinstance(exact_anchor_joints, list):
        exact_anchor_joints = []
    spec_doc = json.loads(spec_path.read_text(encoding="utf-8"))
    baseline = spec_doc.get("baseline", {}) if isinstance(spec_doc, dict) else {}
    if not isinstance(baseline, dict):
        baseline = {}

    backend = str(result.get("backend") or "none")
    if require_dwpose and backend != "dwpose-onnx":
        failures.append(f"gold character must use dwpose-onnx, actual={backend}")
    if not bool(result.get("runtime_ready")):
        failures.append("runtime_ready=false")
    if int(result.get("joints", 0)) != 15:
        failures.append(f"joint_count={result.get('joints')} expected=15")
    if int(result.get("bones", 0)) != 14:
        failures.append(f"bone_count={result.get('bones')} expected=14")
    if int(result.get("bone_weights", 0)) != 14:
        failures.append(f"bone_weights={result.get('bone_weights')} expected=14")
    if int(result.get("collision_proxies", 0)) != 14:
        failures.append(f"collision_proxies={result.get('collision_proxies')} expected=14")
    if bool(result.get("review_required")):
        failures.append("gold cutout still requires manual review")
    cutout_confidence_min = float(baseline.get("cutout_confidence_min", 0.75))
    if float(result.get("cutout_confidence", 0.0)) < cutout_confidence_min:
        failures.append(f"gold cutout confidence too low: {result.get('cutout_confidence')} < {cutout_confidence_min}")
    alpha_coverage = float(result.get("alpha_coverage", 0.0))
    alpha_range = baseline.get("alpha_coverage_range", [0.12, 0.50])
    if not isinstance(alpha_range, list) or len(alpha_range) != 2:
        alpha_range = [0.12, 0.50]
    if not float(alpha_range[0]) <= alpha_coverage <= float(alpha_range[1]):
        failures.append(f"gold alpha coverage out of expected subject range: {alpha_coverage:.6f}")
    if backend == "dwpose-onnx" and len(joint_confidence) != len(JOINT_ORDER):
        failures.append(f"per-joint confidence missing/incomplete: {len(joint_confidence)} != {len(JOINT_ORDER)}")
    pose_confidence = float(rig_confidence.get("pose", 0.0) or 0.0)
    if pose_confidence < float(baseline.get("pose_confidence_min", 0.0)):
        failures.append(f"gold pose confidence too low: {pose_confidence:.6f}")
    expected_uncertain = set(str(name) for name in baseline.get("expected_uncertain_joints", []))
    missing_uncertain = sorted(expected_uncertain.difference(str(name) for name in low_confidence_joints))
    if missing_uncertain:
        failures.append("gold occluded joints were silently trusted: " + ",".join(missing_uncertain))
    expected_limbs = set(str(name) for name in baseline.get("expected_uncertain_limbs", []))
    missing_limbs = sorted(expected_limbs.difference(str(name) for name in uncertain_limbs))
    if missing_limbs:
        failures.append("gold occluded limbs were not classified uncertain: " + ",".join(missing_limbs))

    overlay = output_root / "gold_elf_v1_skeleton_overlay.png"
    _draw_overlay(source, joints, overlay)
    cutout_path = Path(result["cutout"])
    cutout_copy = output_root / "gold_elf_v1_cutout.png"
    cutout_copy.write_bytes(cutout_path.read_bytes())
    manifest_copy = output_root / "gold_elf_v1_manifest.json"
    manifest_copy.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    report = {
        "schema": "krolik.gold-character-report/1",
        "status": "ok" if not failures else "failed",
        "id": "gold-elf-v1",
        "fixture": materialized,
        "pipeline": {
            "backend": backend,
            "rig_review_required": bool(result.get("rig_review_required")),
            "rig_score": float(result.get("rig_score", 0.0)),
            "runtime_ready": bool(result.get("runtime_ready")),
            "cutout_method": str(result.get("cutout_method")),
            "cutout_confidence": float(result.get("cutout_confidence", 0.0)),
            "cutout_review_required": bool(result.get("review_required")),
            "alpha_coverage": float(result.get("alpha_coverage", 0.0)),
            "joints": int(result.get("joints", 0)),
            "bones": int(result.get("bones", 0)),
            "vertices": int(result.get("vertices", 0)),
            "triangles": int(result.get("triangles", 0)),
            "bone_weights": int(result.get("bone_weights", 0)),
            "collision_proxies": int(result.get("collision_proxies", 0)),
        },
        "joints": joints,
        "joint_confidence": joint_confidence,
        "joint_confidence_status": rig_confidence.get("status", {}),
        "low_confidence_joints": low_confidence_joints,
        "guarded_joints": guarded_joints,
        "uncertain_limbs": uncertain_limbs,
        "exact_anchor_joints": exact_anchor_joints,
        "pose_confidence": float(rig_confidence.get("pose", 0.0) or 0.0),
        "bones": DEFAULT_BONES,
        "integrity": {
            "import": import_integrity,
            "runtime_package": package_integrity,
            "manifest_sha256": sha256(manifest_path.read_bytes()).hexdigest(),
        },
        "artifacts": {
            "manifest": str(manifest_copy.resolve()),
            "cutout": str(cutout_copy.resolve()),
            "overlay": str(overlay.resolve()),
            "runtime_manifest": str(manifest_path.resolve()),
            "runtime_image": str(Path(result["image"]).resolve()),
        },
        "failures": failures,
    }
    (output_root / "gold_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report, failures


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Probe the production pipeline with KROLIK gold character art")
    parser.add_argument("--spec", default=str(DEFAULT_SPEC))
    parser.add_argument("--output-root", default=str(ROOT / ".gold_character" / "probe"))
    parser.add_argument("--require-dwpose", action="store_true")
    args = parser.parse_args(argv)

    try:
        report, failures = run_probe(Path(args.spec).resolve(), Path(args.output_root).resolve(), args.require_dwpose)
    except Exception as exc:
        print(f"KROLIK_GOLD_PROBE status=failed fatal={exc}", file=sys.stderr)
        return 2

    pipeline = report["pipeline"]
    print(
        "KROLIK_GOLD_PROBE "
        f"status={report['status']} backend={pipeline['backend']} runtime_ready={str(pipeline['runtime_ready']).lower()} "
        f"rig_score={pipeline['rig_score']:.3f} joints={pipeline['joints']} bones={pipeline['bones']} "
        f"weights={pipeline['bone_weights']} collisions={pipeline['collision_proxies']} "
        f"vertices={pipeline['vertices']} triangles={pipeline['triangles']} failures={len(failures)} "
        f"low_confidence={','.join(report.get('low_confidence_joints', [])) or 'none'} "
        f"uncertain_limbs={','.join(report.get('uncertain_limbs', [])) or 'none'}"
    )
    for failure in failures:
        print(f"KROLIK_GOLD_PROBE_FAIL {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
