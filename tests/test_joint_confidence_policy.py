from __future__ import annotations

from rig_tools import JOINT_ORDER, classify_joint_confidence


def _all(value: float = 0.9) -> dict[str, float]:
    return {name: value for name in JOINT_ORDER}


def test_distal_joint_threshold_is_stricter_than_dwpose_detection_floor() -> None:
    confidence = _all()
    confidence["left_wrist"] = 0.30  # Above DWPose's 0.18 detection floor, still not safe to trust exactly.
    confidence["right_wrist"] = 0.52

    policy = classify_joint_confidence(confidence, fallback=0.18)

    assert "left_wrist" in policy["low_confidence_joints"]
    assert policy["status"]["left_wrist"] == "uncertain"
    assert "left_arm" in policy["uncertain_limbs"]
    assert "left_wrist" not in policy["exact_anchor_joints"]

    assert "right_wrist" not in policy["low_confidence_joints"]
    assert policy["status"]["right_wrist"] == "guarded"
    assert "right_wrist" not in policy["exact_anchor_joints"]


def test_reliable_distal_joint_can_be_exact_anchor() -> None:
    confidence = _all()
    confidence["left_wrist"] = 0.82
    confidence["right_wrist"] = 0.77
    confidence["left_ankle"] = 0.81
    confidence["right_ankle"] = 0.79

    policy = classify_joint_confidence(confidence)

    assert not policy["low_confidence_joints"]
    assert not policy["uncertain_limbs"]
    for joint in ("left_wrist", "right_wrist", "left_ankle", "right_ankle"):
        assert policy["status"][joint] == "reliable"
        assert joint in policy["exact_anchor_joints"]
