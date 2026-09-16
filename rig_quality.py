from __future__ import annotations

"""Confidence and authoring-quality policy for portable KROLIK rigs.

The runtime must distinguish a landmark that is confidently observed from one
that is only plausible.  This module keeps that policy deterministic and small
so Python import/editor code and Godot runtime can share the same manifest
semantics without adding another rig format.
"""

from copy import deepcopy
from typing import Any

from rig_tools import JOINT_ORDER

JOINT_CONFIDENCE_THRESHOLDS: dict[str, tuple[float, float]] = {
    # (uncertain below, reliable at/above). Distal landmarks are intentionally
    # stricter because a bad wrist/ankle is much more visible during IK.
    "head": (0.18, 0.42),
    "neck": (0.22, 0.50),
    "left_shoulder": (0.22, 0.50),
    "right_shoulder": (0.22, 0.50),
    "left_elbow": (0.28, 0.58),
    "right_elbow": (0.28, 0.58),
    "left_wrist": (0.38, 0.64),
    "right_wrist": (0.38, 0.64),
    "pelvis": (0.22, 0.50),
    "left_hip": (0.22, 0.50),
    "right_hip": (0.22, 0.50),
    "left_knee": (0.28, 0.56),
    "right_knee": (0.28, 0.56),
    "left_ankle": (0.34, 0.62),
    "right_ankle": (0.34, 0.62),
}

LIMB_JOINTS = {
    "left_arm": ("left_shoulder", "left_elbow", "left_wrist"),
    "right_arm": ("right_shoulder", "right_elbow", "right_wrist"),
    "left_leg": ("left_hip", "left_knee", "left_ankle"),
    "right_leg": ("right_hip", "right_knee", "right_ankle"),
}

# Only these landmarks may become hard interaction anchors automatically.
EXACT_ANCHOR_CANDIDATES = {
    "head", "neck", "left_wrist", "right_wrist", "left_ankle", "right_ankle", "pelvis"
}


def clamp_confidence(value: Any, default: float = 0.0) -> float:
    try:
        number = float(value)
    except Exception:
        number = float(default)
    if number != number:  # NaN
        number = float(default)
    return max(0.0, min(1.0, number))


def confidence_state(name: str, confidence: float, *, authored: bool = False) -> str:
    if authored:
        return "reliable"
    uncertain, reliable = JOINT_CONFIDENCE_THRESHOLDS.get(str(name), (0.25, 0.55))
    value = clamp_confidence(confidence)
    if value < uncertain:
        return "uncertain"
    if value < reliable:
        return "guarded"
    return "reliable"


def build_joint_quality(
    joints: dict[str, Any],
    raw_confidence: dict[str, Any] | None = None,
    *,
    authored_joints: set[str] | list[str] | tuple[str, ...] | None = None,
    default_confidence: float = 0.45,
) -> dict[str, Any]:
    raw = raw_confidence if isinstance(raw_confidence, dict) else {}
    authored = {str(name) for name in (authored_joints or [])}
    states: dict[str, str] = {}
    confidence: dict[str, float] = {}
    authority: dict[str, float] = {}
    uncertain: list[str] = []
    guarded: list[str] = []
    reliable: list[str] = []

    for name in JOINT_ORDER:
        if name not in joints:
            continue
        is_authored = name in authored
        value = 1.0 if is_authored else clamp_confidence(raw.get(name), default_confidence)
        state = confidence_state(name, value, authored=is_authored)
        confidence[name] = round(value, 6)
        states[name] = state
        # Runtime authority is deliberately softer than a binary gate.
        if state == "reliable":
            a = 1.0
        elif state == "guarded":
            a = 0.62
        else:
            a = 0.30
        authority[name] = a
        {"uncertain": uncertain, "guarded": guarded, "reliable": reliable}[state].append(name)

    uncertain_limbs: list[str] = []
    guarded_limbs: list[str] = []
    for limb, names in LIMB_JOINTS.items():
        limb_states = [states.get(name, "uncertain") for name in names]
        if "uncertain" in limb_states:
            uncertain_limbs.append(limb)
        elif "guarded" in limb_states:
            guarded_limbs.append(limb)

    exact_anchors = sorted(
        name for name in EXACT_ANCHOR_CANDIDATES
        if states.get(name) == "reliable"
    )
    return {
        "schema": "krolik.rig-confidence/1",
        "confidence": confidence,
        "states": states,
        "authority": authority,
        "uncertain_joints": uncertain,
        "guarded_joints": guarded,
        "reliable_joints": reliable,
        "uncertain_limbs": uncertain_limbs,
        "guarded_limbs": guarded_limbs,
        "exact_anchors": exact_anchors,
        "authored_joints": sorted(authored),
    }


def mark_authored_joint_quality(settings: dict[str, Any], names: list[str] | set[str]) -> dict[str, Any]:
    """Return a settings copy with durable authored landmark provenance."""
    out = deepcopy(settings)
    existing = {str(v) for v in out.get("authored_joints", []) if str(v)}
    existing.update(str(name) for name in names)
    out["authored_joints"] = sorted(existing)
    raw = dict(out.get("joint_confidence", {})) if isinstance(out.get("joint_confidence"), dict) else {}
    for name in existing:
        raw[name] = 1.0
    out["joint_confidence"] = raw
    return out
