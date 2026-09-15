from __future__ import annotations

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
