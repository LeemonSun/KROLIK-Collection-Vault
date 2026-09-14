from __future__ import annotations

"""Validated data-driven animation libraries for KROLIK.

Animation content is deliberately separate from runtime code.  Editors/content
packs can author JSON libraries while the runtime keeps the existing animation
format v1 contract.  Validation is strict and bounded so malformed or enormous
content cannot silently poison exported character manifests.
"""

from copy import deepcopy
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
from typing import Any


ANIMATION_FORMAT_VERSION = 1
ANIMATION_SCHEMA = "krolik.animation-library/1"
MAX_LIBRARY_BYTES = 1_048_576
MAX_CLIPS = 256
MAX_STATES = 256
MAX_KEYFRAMES_PER_CLIP = 4096
MAX_TOTAL_KEYFRAMES = 16_384
MAX_JOINTS_PER_FRAME = 256
ROOT_FIELDS = ("x", "y", "rotation", "scale_x", "scale_y")
DEFAULT_ANIMATION_LIBRARY_PATH = Path(__file__).resolve().parent / "content" / "animations" / "default_v1.json"
ENV_LIBRARY_PATH = "KROLIK_ANIMATION_LIBRARY"


class AnimationContentError(ValueError):
    """Raised when animation content cannot be safely consumed."""


@dataclass(frozen=True)
class AnimationLoadResult:
    document: dict[str, Any]
    source: str
    fallback_used: bool = False
    warnings: tuple[str, ...] = ()


def _finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _valid_vec2(value: Any) -> bool:
    if isinstance(value, (list, tuple)):
        return len(value) >= 2 and _finite_number(value[0]) and _finite_number(value[1])
    if isinstance(value, dict):
        return _finite_number(value.get("x", 0.0)) and _finite_number(value.get("y", 0.0))
    return False


def validate_animation_document(document: Any) -> list[str]:
    """Return deterministic validation errors for animation format v1."""
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["animation library must be a JSON object"]

    schema = document.get("schema", ANIMATION_SCHEMA)
    if schema != ANIMATION_SCHEMA:
        errors.append(f"unsupported animation schema: {schema!r}")
    version = document.get("format_version")
    if version != ANIMATION_FORMAT_VERSION:
        errors.append(
            f"unsupported animation format_version {version!r}; expected {ANIMATION_FORMAT_VERSION}"
        )

    clips = document.get("clips")
    if not isinstance(clips, dict) or not clips:
        errors.append("clips must be a non-empty object")
        clips = {}
    elif len(clips) > MAX_CLIPS:
        errors.append(f"clip count {len(clips)} exceeds limit {MAX_CLIPS}")

    total_keyframes = 0
    for raw_name, clip in clips.items():
        name = str(raw_name)
        prefix = f"clip {name!r}"
        if not name:
            errors.append("clip name must not be empty")
            continue
        if not isinstance(clip, dict):
            errors.append(f"{prefix} must be an object")
            continue
        duration = clip.get("duration")
        if not _finite_number(duration) or float(duration) <= 0.0:
            errors.append(f"{prefix} duration must be finite and > 0")
            continue
        duration_f = float(duration)
        if not isinstance(clip.get("loop", True), bool):
            errors.append(f"{prefix} loop must be boolean")

        frames = clip.get("keyframes")
        if not isinstance(frames, list) or not frames:
            errors.append(f"{prefix} keyframes must be a non-empty array")
            continue
        if len(frames) > MAX_KEYFRAMES_PER_CLIP:
            errors.append(
                f"{prefix} keyframe count {len(frames)} exceeds limit {MAX_KEYFRAMES_PER_CLIP}"
            )
        total_keyframes += len(frames)
        previous_t = -1.0
        for index, frame in enumerate(frames):
            fp = f"{prefix} keyframe {index}"
            if not isinstance(frame, dict):
                errors.append(f"{fp} must be an object")
                continue
            timestamp = frame.get("t")
            if not _finite_number(timestamp):
                errors.append(f"{fp} timestamp must be finite numeric")
                continue
            t = float(timestamp)
            if t < 0.0 or t > duration_f + 1e-8:
                errors.append(f"{fp} timestamp {t} is outside [0, {duration_f}]")
            if index > 0 and t <= previous_t + 1e-9:
                errors.append(f"{prefix} timestamps must be strictly increasing")
            previous_t = t

            root = frame.get("root", {})
            if not isinstance(root, dict):
                errors.append(f"{fp} root must be an object")
            else:
                for field in ROOT_FIELDS:
                    if field in root and not _finite_number(root[field]):
                        errors.append(f"{fp} root.{field} must be finite numeric")
                for field in ("scale_x", "scale_y"):
                    if field in root and _finite_number(root[field]) and float(root[field]) <= 0.0:
                        errors.append(f"{fp} root.{field} must be > 0")

            joints = frame.get("joints", {})
            if not isinstance(joints, dict):
                errors.append(f"{fp} joints must be an object")
            else:
                if len(joints) > MAX_JOINTS_PER_FRAME:
                    errors.append(
                        f"{fp} joint count {len(joints)} exceeds limit {MAX_JOINTS_PER_FRAME}"
                    )
                for raw_joint, value in joints.items():
                    joint = str(raw_joint)
                    if not joint:
                        errors.append(f"{fp} contains an empty joint name")
                    elif not _valid_vec2(value):
                        errors.append(f"{fp} joint {joint!r} must be a finite vec2")

    if total_keyframes > MAX_TOTAL_KEYFRAMES:
        errors.append(
            f"total keyframe count {total_keyframes} exceeds limit {MAX_TOTAL_KEYFRAMES}"
        )

    graph = document.get("state_graph")
    if not isinstance(graph, dict):
        errors.append("state_graph must be an object")
        graph = {}
    elif len(graph) > MAX_STATES:
        errors.append(f"state count {len(graph)} exceeds limit {MAX_STATES}")
    for raw_state, entry in graph.items():
        state = str(raw_state)
        if not state:
            errors.append("state name must not be empty")
            continue
        if not isinstance(entry, dict):
            errors.append(f"state {state!r} must be an object")
            continue
        clip_name = entry.get("clip")
        if not isinstance(clip_name, str) or not clip_name:
            errors.append(f"state {state!r} must reference a clip")
        elif clip_name not in clips:
            errors.append(f"state {state!r} references missing clip {clip_name!r}")
        blend = entry.get("blend", 0.16)
        if not _finite_number(blend) or float(blend) < 0.0:
            errors.append(f"state {state!r} blend must be finite and >= 0")
        if "loop" in entry and not isinstance(entry["loop"], bool):
            errors.append(f"state {state!r} loop must be boolean")

    default_clip = document.get("default_clip")
    if not isinstance(default_clip, str) or not default_clip:
        errors.append("default_clip must be a non-empty string")
    elif default_clip not in clips:
        errors.append(f"default_clip references missing clip {default_clip!r}")

    for optional in ("procedural_blink", "look_at"):
        if optional in document and not isinstance(document[optional], dict):
            errors.append(f"{optional} must be an object")

    return errors


def _read_json(path: Path) -> dict[str, Any]:
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise AnimationContentError(f"animation library is unavailable: {path}: {exc}") from exc
    if size > MAX_LIBRARY_BYTES:
        raise AnimationContentError(
            f"animation library is too large: {size} bytes > {MAX_LIBRARY_BYTES}: {path}"
        )
    try:
        raw = path.read_text(encoding="utf-8")
        document = json.loads(raw)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AnimationContentError(f"unable to read animation library {path}: {exc}") from exc
    errors = validate_animation_document(document)
    if errors:
        detail = "; ".join(errors[:12])
        if len(errors) > 12:
            detail += f"; ... {len(errors) - 12} more"
        raise AnimationContentError(f"invalid animation library {path}: {detail}")
    return document


def load_animation_library(
    path: str | os.PathLike[str] | None = None,
    *,
    fallback_path: str | os.PathLike[str] | None = None,
) -> AnimationLoadResult:
    """Load a validated library, optionally falling back non-destructively."""
    primary = Path(path).expanduser().resolve() if path is not None else DEFAULT_ANIMATION_LIBRARY_PATH
    try:
        document = _read_json(primary)
        return AnimationLoadResult(deepcopy(document), str(primary))
    except AnimationContentError as primary_error:
        if fallback_path is None:
            raise
        fallback = Path(fallback_path).expanduser().resolve()
        if fallback == primary:
            raise
        document = _read_json(fallback)
        return AnimationLoadResult(
            deepcopy(document),
            str(fallback),
            fallback_used=True,
            warnings=(str(primary_error),),
        )


def load_default_animation_library() -> AnimationLoadResult:
    """Load user override when configured, otherwise the bundled v1 library.

    An invalid user override never destroys/changes bundled content: it falls
    back to the validated built-in asset and reports the reason in ``warnings``.
    """
    override = os.environ.get(ENV_LIBRARY_PATH, "").strip()
    if override:
        return load_animation_library(override, fallback_path=DEFAULT_ANIMATION_LIBRARY_PATH)
    return load_animation_library(DEFAULT_ANIMATION_LIBRARY_PATH)


def default_animation_document() -> dict[str, Any]:
    """Return a fresh validated document safe for mutation by package builders."""
    return deepcopy(load_default_animation_library().document)
