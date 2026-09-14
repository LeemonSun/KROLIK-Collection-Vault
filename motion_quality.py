from __future__ import annotations

"""Quality audit for the default KROLIK motion library.

Schema validation answers whether a clip is safe to parse. This module adds a
higher bar for production content: enough motion families, non-static authored
clips, bounded body offsets and seamless closure for looped clips. It is kept
renderer-independent so CI can protect content quality without needing Godot.
"""

from dataclasses import dataclass
import json
import math
from typing import Any

from animation_content import validate_animation_document


MIN_TOTAL_CLIPS = 30
MAX_ABS_JOINT_OFFSET = 0.18
MAX_ABS_ROOT_ROTATION = 0.25
STATIC_ALLOWLIST = {"idle_static"}
FAMILY_RULES = {
    "idle": {"prefixes": ("idle_",), "minimum": 6},
    "locomotion": {"prefixes": ("walk", "turn_", "step_", "sidestep_"), "minimum": 7},
    "gesture": {"prefixes": ("gesture_",), "minimum": 6},
    "reaction": {"prefixes": ("reaction_",), "minimum": 3},
    "environment": {"prefixes": ("environment_",), "minimum": 3},
}


@dataclass(frozen=True)
class MotionAuditReport:
    clip_count: int
    family_counts: dict[str, int]
    dynamic_clip_count: int
    loop_clip_count: int
    loop_closed_count: int
    errors: tuple[str, ...]
    warnings: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.errors


def _finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _xy(value: Any) -> tuple[float, float] | None:
    if isinstance(value, (list, tuple)) and len(value) >= 2 and _finite(value[0]) and _finite(value[1]):
        return float(value[0]), float(value[1])
    if isinstance(value, dict) and _finite(value.get("x", 0.0)) and _finite(value.get("y", 0.0)):
        return float(value.get("x", 0.0)), float(value.get("y", 0.0))
    return None


def _canonical_pose(frame: dict[str, Any]) -> str:
    # Timestamp is deliberately excluded; cycle closure compares pose values.
    return json.dumps(
        {"joints": frame.get("joints", {}), "root": frame.get("root", {})},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def _is_dynamic(frames: list[Any]) -> bool:
    signatures = {
        _canonical_pose(frame)
        for frame in frames
        if isinstance(frame, dict)
    }
    return len(signatures) > 1


def _family_count(clips: dict[str, Any], prefixes: tuple[str, ...]) -> int:
    return sum(1 for name in clips if any(name == prefix or name.startswith(prefix) for prefix in prefixes))


def audit_motion_library(document: Any) -> MotionAuditReport:
    errors = list(validate_animation_document(document))
    warnings: list[str] = []
    if not isinstance(document, dict):
        return MotionAuditReport(0, {}, 0, 0, 0, tuple(errors), tuple(warnings))
    clips = document.get("clips", {})
    if not isinstance(clips, dict):
        clips = {}

    if len(clips) < MIN_TOTAL_CLIPS:
        errors.append(f"motion library has {len(clips)} clips; need at least {MIN_TOTAL_CLIPS}")

    family_counts: dict[str, int] = {}
    for family, rule in FAMILY_RULES.items():
        count = _family_count(clips, tuple(rule["prefixes"]))
        family_counts[family] = count
        if count < int(rule["minimum"]):
            errors.append(f"motion family {family!r} has {count} clips; need at least {rule['minimum']}")

    dynamic_count = 0
    loop_count = 0
    loop_closed = 0
    for raw_name, clip in clips.items():
        name = str(raw_name)
        if not isinstance(clip, dict):
            continue
        frames = clip.get("keyframes", [])
        if not isinstance(frames, list) or not frames:
            continue
        dynamic = _is_dynamic(frames)
        if dynamic:
            dynamic_count += 1
        elif name not in STATIC_ALLOWLIST:
            errors.append(f"clip {name!r} is static; only {sorted(STATIC_ALLOWLIST)} may be static")

        loop = bool(clip.get("loop", True))
        if loop:
            loop_count += 1
            if len(frames) == 1 or (
                isinstance(frames[0], dict)
                and isinstance(frames[-1], dict)
                and _canonical_pose(frames[0]) == _canonical_pose(frames[-1])
            ):
                loop_closed += 1
            else:
                errors.append(f"loop clip {name!r} does not close on its starting pose")

        active_joints: set[str] = set()
        for index, frame in enumerate(frames):
            if not isinstance(frame, dict):
                continue
            joints = frame.get("joints", {})
            if isinstance(joints, dict):
                for raw_joint, value in joints.items():
                    joint = str(raw_joint)
                    xy = _xy(value)
                    if xy is None:
                        continue
                    active_joints.add(joint)
                    if abs(xy[0]) > MAX_ABS_JOINT_OFFSET or abs(xy[1]) > MAX_ABS_JOINT_OFFSET:
                        errors.append(
                            f"clip {name!r} keyframe {index} joint {joint!r} exceeds quality offset bound +/-{MAX_ABS_JOINT_OFFSET}"
                        )
            root = frame.get("root", {})
            if isinstance(root, dict) and "rotation" in root and _finite(root["rotation"]):
                if abs(float(root["rotation"])) > MAX_ABS_ROOT_ROTATION:
                    errors.append(
                        f"clip {name!r} keyframe {index} root.rotation exceeds +/-{MAX_ABS_ROOT_ROTATION} rad"
                    )
        if dynamic and len(active_joints) < 2 and name not in {"gesture_nod", "gesture_shake_head"}:
            warnings.append(f"clip {name!r} animates fewer than two joints")

    return MotionAuditReport(
        clip_count=len(clips),
        family_counts=family_counts,
        dynamic_clip_count=dynamic_count,
        loop_clip_count=loop_count,
        loop_closed_count=loop_closed,
        errors=tuple(errors),
        warnings=tuple(warnings),
    )
