from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"bootstrap marker missing: {label}")
    return text.replace(old, new, 1)


runtime_path = ROOT / "runtime_package.py"
runtime = runtime_path.read_text(encoding="utf-8")
runtime = replace_once(
    runtime,
    '            "health": health,\n            "skinning": skin,\n',
    '            "health": health,\n            "confidence": {\n                "pose": float(settings.get("pose_confidence", 0.0)),\n                "joints": dict(settings.get("joint_confidence", {})) if isinstance(settings.get("joint_confidence", {}), dict) else {},\n                "low_confidence_joints": list(settings.get("low_confidence_joints", [])) if isinstance(settings.get("low_confidence_joints", []), list) else [],\n            },\n            "skinning": skin,\n',
    "runtime-rig-confidence",
)
runtime_path.write_text(runtime, encoding="utf-8")

probe_path = ROOT / "tools" / "probe_gold_character.py"
probe = probe_path.read_text(encoding="utf-8")
probe = replace_once(
    probe,
    '    joints = _joint_map(manifest)\n    failures.extend(_geometry_checks(joints))\n\n    backend = str(result.get("backend") or "none")\n',
    '''    joints = _joint_map(manifest)\n    failures.extend(_geometry_checks(joints))\n    rig_confidence = manifest.get("rig", {}).get("confidence", {})\n    if not isinstance(rig_confidence, dict):\n        rig_confidence = {}\n    joint_confidence = rig_confidence.get("joints", {})\n    if not isinstance(joint_confidence, dict):\n        joint_confidence = {}\n    low_confidence_joints = rig_confidence.get("low_confidence_joints", [])\n    if not isinstance(low_confidence_joints, list):\n        low_confidence_joints = []\n\n    backend = str(result.get("backend") or "none")\n''',
    "probe-confidence-read",
)
probe = replace_once(
    probe,
    '    if int(result.get("collision_proxies", 0)) != 14:\n        failures.append(f"collision_proxies={result.get(\'collision_proxies\')} expected=14")\n\n    overlay = output_root / "gold_elf_v1_skeleton_overlay.png"\n',
    '''    if int(result.get("collision_proxies", 0)) != 14:\n        failures.append(f"collision_proxies={result.get('collision_proxies')} expected=14")\n    if bool(result.get("review_required")):\n        failures.append("gold cutout still requires manual review")\n    if float(result.get("cutout_confidence", 0.0)) < 0.75:\n        failures.append(f"gold cutout confidence too low: {result.get('cutout_confidence')}")\n    alpha_coverage = float(result.get("alpha_coverage", 0.0))\n    if not 0.12 <= alpha_coverage <= 0.50:\n        failures.append(f"gold alpha coverage out of expected subject range: {alpha_coverage:.6f}")\n    if backend == "dwpose-onnx" and len(joint_confidence) != len(JOINT_ORDER):\n        failures.append(f"per-joint confidence missing/incomplete: {len(joint_confidence)} != {len(JOINT_ORDER)}")\n\n    overlay = output_root / "gold_elf_v1_skeleton_overlay.png"\n''',
    "probe-quality-gates",
)
probe = replace_once(
    probe,
    '        "joints": joints,\n        "bones": DEFAULT_BONES,\n',
    '        "joints": joints,\n        "joint_confidence": joint_confidence,\n        "low_confidence_joints": low_confidence_joints,\n        "pose_confidence": float(rig_confidence.get("pose", 0.0) or 0.0),\n        "bones": DEFAULT_BONES,\n',
    "probe-report-confidence",
)
probe = replace_once(
    probe,
    '        f"vertices={pipeline[\'vertices\']} triangles={pipeline[\'triangles\']} failures={len(failures)}"\n',
    '        f"vertices={pipeline[\'vertices\']} triangles={pipeline[\'triangles\']} failures={len(failures)} "\n        f"low_confidence={\',\'.join(report.get(\'low_confidence_joints\', [])) or \'none\'}"\n',
    "probe-console-confidence",
)
probe_path.write_text(probe, encoding="utf-8")

(ROOT / "tests" / "test_runtime_joint_confidence.py").write_text(r'''from __future__ import annotations

import json

from rig_tools import DEFAULT_BONES, JOINT_ORDER
from runtime_package import build_manifest


def test_runtime_manifest_preserves_pose_and_joint_confidence() -> None:
    joints = {name: {"x": 0.5, "y": 0.05 + index * 0.05} for index, name in enumerate(JOINT_ORDER)}
    confidence = {name: round(0.95 - index * 0.01, 4) for index, name in enumerate(JOINT_ORDER)}
    settings = {
        "backend": "dwpose-onnx",
        "bones": DEFAULT_BONES,
        "pose_confidence": 0.88,
        "joint_confidence": confidence,
        "low_confidence_joints": ["left_wrist"],
    }
    manifest = build_manifest(
        character={"id": "confidence", "name": "Confidence", "status": "imported"},
        image_version={"id": 0, "width": 512, "height": 640, "kind": "derived-cutout"},
        rig={"id": 0, "rest_json": json.dumps({"joints": joints}), "settings_json": json.dumps(settings)},
        mind=None,
        cell_id="room",
    )
    block = manifest["rig"]["confidence"]
    assert block["pose"] == 0.88
    assert block["joints"] == confidence
    assert block["low_confidence_joints"] == ["left_wrist"]
''', encoding="utf-8")

print("KROLIK_GOLD_RUNTIME_CONFIDENCE_BOOTSTRAP status=ok")
