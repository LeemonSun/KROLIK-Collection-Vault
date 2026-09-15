from __future__ import annotations

"""One-shot branch patch used to harden DWPose confidence policy.

This script is intentionally deterministic and refuses to edit unexpected source
text. It is deleted after the branch is verified.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one match in {path}: found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def patch_rig_tools() -> None:
    path = ROOT / "rig_tools.py"
    marker = "\n\n\n@dataclass\nclass RigDetection:"
    policy = r'''

JOINT_CONFIDENCE_THRESHOLDS = {
    "head": 0.35,
    "neck": 0.40,
    "left_shoulder": 0.45,
    "right_shoulder": 0.45,
    "left_elbow": 0.45,
    "right_elbow": 0.45,
    "left_wrist": 0.45,
    "right_wrist": 0.45,
    "pelvis": 0.45,
    "left_hip": 0.45,
    "right_hip": 0.45,
    "left_knee": 0.40,
    "right_knee": 0.40,
    "left_ankle": 0.40,
    "right_ankle": 0.40,
}

EXACT_ANCHOR_THRESHOLDS = {
    "head": 0.50,
    "left_wrist": 0.60,
    "right_wrist": 0.60,
    "left_ankle": 0.55,
    "right_ankle": 0.55,
}


def classify_joint_confidence(
    joint_confidence: dict[str, float],
    fallback: float = 0.18,
) -> dict[str, Any]:
    """Turn raw detector scores into conservative runtime confidence policy.

    DWPose's low detection floor answers "did the model find enough of a body?".
    It is intentionally not the same as "is this joint precise enough for IK or
    an exact interaction anchor?". Distal joints need stricter thresholds.
    """
    thresholds: dict[str, float] = {}
    status: dict[str, str] = {}
    low: list[str] = []
    guarded: list[str] = []
    exact_anchors: list[str] = []

    for name in JOINT_ORDER:
        raw = joint_confidence.get(name, 0.0)
        try:
            value = max(0.0, min(1.0, float(raw)))
        except (TypeError, ValueError):
            value = 0.0
        threshold = max(float(fallback), float(JOINT_CONFIDENCE_THRESHOLDS.get(name, fallback)))
        thresholds[name] = round(threshold, 6)
        if value < threshold:
            status[name] = "uncertain"
            low.append(name)
        elif value < min(1.0, threshold + 0.15):
            status[name] = "guarded"
            guarded.append(name)
        else:
            status[name] = "reliable"

        anchor_threshold = EXACT_ANCHOR_THRESHOLDS.get(name)
        if anchor_threshold is not None and value >= max(threshold, float(anchor_threshold)):
            exact_anchors.append(name)

    uncertain_limbs: list[str] = []
    chains = {
        "left_arm": ("left_elbow", "left_wrist"),
        "right_arm": ("right_elbow", "right_wrist"),
        "left_leg": ("left_knee", "left_ankle"),
        "right_leg": ("right_knee", "right_ankle"),
    }
    for limb, names in chains.items():
        if any(status.get(name) == "uncertain" for name in names):
            uncertain_limbs.append(limb)

    return {
        "thresholds": thresholds,
        "status": status,
        "low_confidence_joints": sorted(low),
        "guarded_joints": sorted(guarded),
        "uncertain_limbs": sorted(uncertain_limbs),
        "exact_anchor_joints": sorted(exact_anchors),
    }
'''
    text = path.read_text(encoding="utf-8")
    if "JOINT_CONFIDENCE_THRESHOLDS" not in text:
        if marker not in text:
            raise SystemExit("rig_tools dataclass marker not found")
        text = text.replace(marker, policy + marker, 1)
        path.write_text(text, encoding="utf-8")

    old = '''    return RigDetection(joints=joints, settings={
        "backend": "dwpose-onnx",
        "rig_format_version": RIG_FORMAT_VERSION,
        "bones": DEFAULT_BONES,
        "mesh_cols": 16,
        "mesh_rows": 30,
        "influence_radius": .155,
        "preserve_volume": .68,
        "pose_confidence": round(float(quality), 5),
        "joint_confidence": joint_confidence,
        "low_confidence_joints": sorted(
            name for name, value in joint_confidence.items() if float(value) < min_conf
        ),
    })'''
    new = '''    confidence_policy = classify_joint_confidence(joint_confidence, fallback=min_conf)
    return RigDetection(joints=joints, settings={
        "backend": "dwpose-onnx",
        "rig_format_version": RIG_FORMAT_VERSION,
        "bones": DEFAULT_BONES,
        "mesh_cols": 16,
        "mesh_rows": 30,
        "influence_radius": .155,
        "preserve_volume": .68,
        "pose_confidence": round(float(quality), 5),
        "joint_confidence": joint_confidence,
        "joint_confidence_thresholds": confidence_policy["thresholds"],
        "joint_confidence_status": confidence_policy["status"],
        "low_confidence_joints": confidence_policy["low_confidence_joints"],
        "guarded_joints": confidence_policy["guarded_joints"],
        "uncertain_limbs": confidence_policy["uncertain_limbs"],
        "exact_anchor_joints": confidence_policy["exact_anchor_joints"],
    })'''
    text = path.read_text(encoding="utf-8")
    if old in text:
        replace_once(path, old, new)
    elif '"joint_confidence_thresholds": confidence_policy["thresholds"]' not in text:
        raise SystemExit("rig confidence settings block not found")


def patch_runtime_package() -> None:
    path = ROOT / "runtime_package.py"
    old = '''            "confidence": {
                "pose": float(settings.get("pose_confidence", 0.0)),
                "joints": dict(settings.get("joint_confidence", {})) if isinstance(settings.get("joint_confidence", {}), dict) else {},
                "low_confidence_joints": list(settings.get("low_confidence_joints", [])) if isinstance(settings.get("low_confidence_joints", []), list) else [],
            },'''
    new = '''            "confidence": {
                "pose": float(settings.get("pose_confidence", 0.0)),
                "joints": dict(settings.get("joint_confidence", {})) if isinstance(settings.get("joint_confidence", {}), dict) else {},
                "thresholds": dict(settings.get("joint_confidence_thresholds", {})) if isinstance(settings.get("joint_confidence_thresholds", {}), dict) else {},
                "status": dict(settings.get("joint_confidence_status", {})) if isinstance(settings.get("joint_confidence_status", {}), dict) else {},
                "low_confidence_joints": list(settings.get("low_confidence_joints", [])) if isinstance(settings.get("low_confidence_joints", []), list) else [],
                "guarded_joints": list(settings.get("guarded_joints", [])) if isinstance(settings.get("guarded_joints", []), list) else [],
                "uncertain_limbs": list(settings.get("uncertain_limbs", [])) if isinstance(settings.get("uncertain_limbs", []), list) else [],
                "exact_anchor_joints": list(settings.get("exact_anchor_joints", [])) if isinstance(settings.get("exact_anchor_joints", []), list) else [],
            },'''
    text = path.read_text(encoding="utf-8")
    if old in text:
        replace_once(path, old, new)
    elif '"uncertain_limbs": list(settings.get("uncertain_limbs"' not in text:
        raise SystemExit("runtime confidence block not found")


def patch_probe() -> None:
    path = ROOT / "tools" / "probe_gold_character.py"
    old_read = '''    low_confidence_joints = rig_confidence.get("low_confidence_joints", [])
    if not isinstance(low_confidence_joints, list):
        low_confidence_joints = []
'''
    new_read = '''    low_confidence_joints = rig_confidence.get("low_confidence_joints", [])
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
'''
    text = path.read_text(encoding="utf-8")
    if old_read in text:
        replace_once(path, old_read, new_read)

    old_gates = '''    if bool(result.get("review_required")):
        failures.append("gold cutout still requires manual review")
    if float(result.get("cutout_confidence", 0.0)) < 0.75:
        failures.append(f"gold cutout confidence too low: {result.get('cutout_confidence')}")
    alpha_coverage = float(result.get("alpha_coverage", 0.0))
    if not 0.12 <= alpha_coverage <= 0.50:
        failures.append(f"gold alpha coverage out of expected subject range: {alpha_coverage:.6f}")
    if backend == "dwpose-onnx" and len(joint_confidence) != len(JOINT_ORDER):
        failures.append(f"per-joint confidence missing/incomplete: {len(joint_confidence)} != {len(JOINT_ORDER)}")
'''
    new_gates = '''    if bool(result.get("review_required")):
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
'''
    text = path.read_text(encoding="utf-8")
    if old_gates in text:
        replace_once(path, old_gates, new_gates)

    old_report = '''        "joint_confidence": joint_confidence,
        "low_confidence_joints": low_confidence_joints,
        "pose_confidence": float(rig_confidence.get("pose", 0.0) or 0.0),
'''
    new_report = '''        "joint_confidence": joint_confidence,
        "joint_confidence_status": rig_confidence.get("status", {}),
        "low_confidence_joints": low_confidence_joints,
        "guarded_joints": guarded_joints,
        "uncertain_limbs": uncertain_limbs,
        "exact_anchor_joints": exact_anchor_joints,
        "pose_confidence": float(rig_confidence.get("pose", 0.0) or 0.0),
'''
    text = path.read_text(encoding="utf-8")
    if old_report in text:
        replace_once(path, old_report, new_report)

    old_print = '''        f"vertices={pipeline['vertices']} triangles={pipeline['triangles']} failures={len(failures)} "
        f"low_confidence={','.join(report.get('low_confidence_joints', [])) or 'none'}"
'''
    new_print = '''        f"vertices={pipeline['vertices']} triangles={pipeline['triangles']} failures={len(failures)} "
        f"low_confidence={','.join(report.get('low_confidence_joints', [])) or 'none'} "
        f"uncertain_limbs={','.join(report.get('uncertain_limbs', [])) or 'none'}"
'''
    text = path.read_text(encoding="utf-8")
    if old_print in text:
        replace_once(path, old_print, new_print)


def main() -> None:
    patch_rig_tools()
    patch_runtime_package()
    patch_probe()
    print("KROLIK_OCCLUDED_LIMB_POLICY_PATCH status=ok")


if __name__ == "__main__":
    main()
