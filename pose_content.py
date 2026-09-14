from __future__ import annotations

"""Validated reusable pose libraries and authoring services for KROLIK.

Poses are authoring-time assets expressed in the same normalized joint-offset
semantics already used by animation format v1.  They can be applied to an
editable rig for previews or converted into ordinary animation-v1 clips without
changing the runtime manifest contract.
"""

from copy import deepcopy
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import shutil
from typing import Any

from animation_content import validate_animation_document


POSE_FORMAT_VERSION = 1
POSE_SCHEMA = "krolik.pose-library/1"
MAX_LIBRARY_BYTES = 1_048_576
MAX_POSES = 512
MAX_JOINTS_PER_POSE = 256
MAX_TAGS_PER_POSE = 64
MAX_JOINT_OFFSET = 2.0
MAX_ROOT_TRANSLATION = 4096.0
MAX_ROOT_ROTATION = math.tau * 4.0
MAX_ROOT_SCALE = 8.0
DEFAULT_POSE_LIBRARY_PATH = Path(__file__).resolve().parent / "content" / "poses" / "default_v1.json"
ENV_LIBRARY_PATH = "KROLIK_POSE_LIBRARY"
ROOT_FIELDS = ("x", "y", "rotation", "scale_x", "scale_y")


class PoseContentError(ValueError):
    """Raised when pose content cannot be safely consumed or authored."""


@dataclass(frozen=True)
class PoseLoadResult:
    document: dict[str, Any]
    source: str
    fallback_used: bool = False
    warnings: tuple[str, ...] = ()


@dataclass(frozen=True)
class PoseSaveResult:
    path: str
    backup_path: str | None
    pose_count: int


def _finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _vec2(value: Any) -> tuple[float, float] | None:
    if isinstance(value, (list, tuple)) and len(value) >= 2 and _finite(value[0]) and _finite(value[1]):
        return float(value[0]), float(value[1])
    if isinstance(value, dict) and _finite(value.get("x", 0.0)) and _finite(value.get("y", 0.0)):
        return float(value.get("x", 0.0)), float(value.get("y", 0.0))
    return None


def _string_list(value: Any, *, limit: int) -> bool:
    return isinstance(value, list) and len(value) <= limit and all(isinstance(item, str) and item for item in value)


def validate_pose_document(document: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["pose library must be a JSON object"]

    schema = document.get("schema", POSE_SCHEMA)
    if schema != POSE_SCHEMA:
        errors.append(f"unsupported pose schema: {schema!r}")
    version = document.get("format_version")
    if version != POSE_FORMAT_VERSION:
        errors.append(f"unsupported pose format_version {version!r}; expected {POSE_FORMAT_VERSION}")

    poses = document.get("poses")
    if not isinstance(poses, dict) or not poses:
        errors.append("poses must be a non-empty object")
        poses = {}
    elif len(poses) > MAX_POSES:
        errors.append(f"pose count {len(poses)} exceeds limit {MAX_POSES}")

    for raw_name, pose in poses.items():
        name = str(raw_name)
        prefix = f"pose {name!r}"
        if not name:
            errors.append("pose name must not be empty")
            continue
        if not isinstance(pose, dict):
            errors.append(f"{prefix} must be an object")
            continue
        if pose.get("mode", "offset") != "offset":
            errors.append(f"{prefix} mode must be 'offset' for format v1")
        if not _string_list(pose.get("tags", []), limit=MAX_TAGS_PER_POSE):
            errors.append(f"{prefix} tags must be a bounded string array")
        category = pose.get("category", "general")
        if not isinstance(category, str) or not category:
            errors.append(f"{prefix} category must be a non-empty string")
        if "mirrorable" in pose and not isinstance(pose["mirrorable"], bool):
            errors.append(f"{prefix} mirrorable must be boolean")

        joints = pose.get("joints", {})
        if not isinstance(joints, dict):
            errors.append(f"{prefix} joints must be an object")
            joints = {}
        elif len(joints) > MAX_JOINTS_PER_POSE:
            errors.append(f"{prefix} joint count {len(joints)} exceeds limit {MAX_JOINTS_PER_POSE}")
        for raw_joint, value in joints.items():
            joint = str(raw_joint)
            if not joint:
                errors.append(f"{prefix} contains an empty joint name")
                continue
            xy = _vec2(value)
            if xy is None:
                errors.append(f"{prefix} joint {joint!r} must be a finite vec2")
            elif abs(xy[0]) > MAX_JOINT_OFFSET or abs(xy[1]) > MAX_JOINT_OFFSET:
                errors.append(f"{prefix} joint {joint!r} offset exceeds +/-{MAX_JOINT_OFFSET}")

        root = pose.get("root", {})
        if not isinstance(root, dict):
            errors.append(f"{prefix} root must be an object")
        else:
            unknown = sorted(set(root) - set(ROOT_FIELDS))
            if unknown:
                errors.append(f"{prefix} root has unsupported fields: {', '.join(unknown)}")
            for field in ROOT_FIELDS:
                if field in root and not _finite(root[field]):
                    errors.append(f"{prefix} root.{field} must be finite numeric")
            for field in ("x", "y"):
                if field in root and _finite(root[field]) and abs(float(root[field])) > MAX_ROOT_TRANSLATION:
                    errors.append(f"{prefix} root.{field} exceeds +/-{MAX_ROOT_TRANSLATION}")
            if "rotation" in root and _finite(root["rotation"]) and abs(float(root["rotation"])) > MAX_ROOT_ROTATION:
                errors.append(f"{prefix} root.rotation exceeds +/-{MAX_ROOT_ROTATION}")
            for field in ("scale_x", "scale_y"):
                if field in root and _finite(root[field]) and not (0.01 <= float(root[field]) <= MAX_ROOT_SCALE):
                    errors.append(f"{prefix} root.{field} must be in [0.01, {MAX_ROOT_SCALE}]")

        duration = pose.get("duration_hint", 1.0)
        if not _finite(duration) or not (0.01 <= float(duration) <= 120.0):
            errors.append(f"{prefix} duration_hint must be finite in [0.01, 120]")

    return errors


def _read_json(path: Path) -> dict[str, Any]:
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise PoseContentError(f"pose library is unavailable: {path}: {exc}") from exc
    if size > MAX_LIBRARY_BYTES:
        raise PoseContentError(f"pose library is too large: {size} bytes > {MAX_LIBRARY_BYTES}: {path}")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise PoseContentError(f"unable to read pose library {path}: {exc}") from exc
    errors = validate_pose_document(document)
    if errors:
        detail = "; ".join(errors[:12])
        if len(errors) > 12:
            detail += f"; ... {len(errors) - 12} more"
        raise PoseContentError(f"invalid pose library {path}: {detail}")
    return document


def load_pose_library(
    path: str | os.PathLike[str] | None = None,
    *,
    fallback_path: str | os.PathLike[str] | None = None,
) -> PoseLoadResult:
    primary = Path(path).expanduser().resolve() if path is not None else DEFAULT_POSE_LIBRARY_PATH
    try:
        document = _read_json(primary)
        return PoseLoadResult(deepcopy(document), str(primary))
    except PoseContentError as primary_error:
        if fallback_path is None:
            raise
        fallback = Path(fallback_path).expanduser().resolve()
        if fallback == primary:
            raise
        document = _read_json(fallback)
        return PoseLoadResult(
            deepcopy(document), str(fallback), fallback_used=True, warnings=(str(primary_error),)
        )


def load_default_pose_library() -> PoseLoadResult:
    override = os.environ.get(ENV_LIBRARY_PATH, "").strip()
    if override:
        return load_pose_library(override, fallback_path=DEFAULT_POSE_LIBRARY_PATH)
    return load_pose_library(DEFAULT_POSE_LIBRARY_PATH)


def _mirrored_joint_name(name: str) -> str:
    if name.startswith("left_"):
        return "right_" + name[len("left_"):]
    if name.startswith("right_"):
        return "left_" + name[len("right_"):]
    return name


def mirror_pose(pose: dict[str, Any]) -> dict[str, Any]:
    """Return a horizontal mirror using semantic left/right joint names."""
    out = deepcopy(pose)
    source = pose.get("joints", {}) if isinstance(pose, dict) else {}
    mirrored: dict[str, list[float]] = {}
    if isinstance(source, dict):
        for raw_name, value in source.items():
            xy = _vec2(value)
            if xy is None:
                continue
            mirrored[_mirrored_joint_name(str(raw_name))] = [-xy[0], xy[1]]
    out["joints"] = mirrored
    root = deepcopy(pose.get("root", {})) if isinstance(pose.get("root", {}), dict) else {}
    if "x" in root and _finite(root["x"]):
        root["x"] = -float(root["x"])
    if "rotation" in root and _finite(root["rotation"]):
        root["rotation"] = -float(root["rotation"])
    out["root"] = root
    return out


class PoseCatalog:
    """Cached reusable poses with explicit authoring-time reload."""

    def __init__(
        self,
        path: str | os.PathLike[str] | None = None,
        *,
        fallback_path: str | os.PathLike[str] | None = None,
    ) -> None:
        self.path = path
        self.fallback_path = fallback_path
        self.revision = 0
        self.source = ""
        self.fallback_used = False
        self.warnings: tuple[str, ...] = ()
        self._document: dict[str, Any] = {}
        self._poses: dict[str, dict[str, Any]] = {}
        self.reload()

    def reload(self) -> PoseLoadResult:
        result = load_default_pose_library() if self.path is None else load_pose_library(self.path, fallback_path=self.fallback_path)
        self._document = deepcopy(result.document)
        self._poses = deepcopy(self._document.get("poses", {}))
        self.source = result.source
        self.fallback_used = result.fallback_used
        self.warnings = result.warnings
        self.revision += 1
        return PoseLoadResult(deepcopy(self._document), self.source, self.fallback_used, self.warnings)

    @property
    def document(self) -> dict[str, Any]:
        return deepcopy(self._document)

    def names(self, *, category: str | None = None, tag: str | None = None) -> tuple[str, ...]:
        names: list[str] = []
        for name, pose in self._poses.items():
            if category is not None and pose.get("category", "general") != category:
                continue
            if tag is not None and tag not in pose.get("tags", []):
                continue
            names.append(name)
        return tuple(sorted(names))

    def get(self, name: str, *, mirrored: bool = False) -> dict[str, Any] | None:
        value = self._poses.get(str(name))
        if not isinstance(value, dict):
            return None
        result = deepcopy(value)
        if mirrored:
            if not bool(result.get("mirrorable", True)):
                raise PoseContentError(f"pose {name!r} is not mirrorable")
            result = mirror_pose(result)
        return result

    def apply(
        self,
        name: str,
        rest_joints: dict[str, dict[str, Any]],
        *,
        strength: float = 1.0,
        mirrored: bool = False,
        clamp_normalized: bool = True,
    ) -> dict[str, dict[str, float]]:
        pose = self.get(name, mirrored=mirrored)
        if pose is None:
            raise KeyError(f"unknown pose: {name}")
        amount = max(0.0, min(1.0, float(strength)))
        out: dict[str, dict[str, float]] = {}
        for joint, point in rest_joints.items():
            if not isinstance(point, dict) or not _finite(point.get("x")) or not _finite(point.get("y")):
                continue
            out[str(joint)] = {"x": float(point["x"]), "y": float(point["y"])}
        for raw_joint, value in pose.get("joints", {}).items():
            joint = str(raw_joint)
            if joint not in out:
                continue
            xy = _vec2(value)
            if xy is None:
                continue
            x = out[joint]["x"] + xy[0] * amount
            y = out[joint]["y"] + xy[1] * amount
            if clamp_normalized:
                x, y = max(0.0, min(1.0, x)), max(0.0, min(1.0, y))
            out[joint] = {"x": x, "y": y}
        return out

    def as_animation_clip(
        self,
        name: str,
        *,
        duration: float | None = None,
        loop: bool = True,
        mirrored: bool = False,
    ) -> dict[str, Any]:
        pose = self.get(name, mirrored=mirrored)
        if pose is None:
            raise KeyError(f"unknown pose: {name}")
        actual_duration = float(duration if duration is not None else pose.get("duration_hint", 1.0))
        if not math.isfinite(actual_duration) or actual_duration <= 0.0:
            raise PoseContentError("animation clip duration must be finite and > 0")
        frame = {"joints": deepcopy(pose.get("joints", {})), "root": deepcopy(pose.get("root", {}))}
        return {
            "duration": actual_duration,
            "loop": bool(loop),
            "keyframes": [
                {"t": 0.0, **deepcopy(frame)},
                {"t": actual_duration, **deepcopy(frame)},
            ],
        }

    def add_to_animation(
        self,
        animation_document: dict[str, Any],
        pose_name: str,
        *,
        clip_name: str | None = None,
        state_name: str | None = None,
        duration: float | None = None,
        loop: bool = True,
        blend: float = 0.16,
        mirrored: bool = False,
        overwrite: bool = False,
    ) -> dict[str, Any]:
        out = deepcopy(animation_document)
        clips = out.setdefault("clips", {})
        graph = out.setdefault("state_graph", {})
        if not isinstance(clips, dict) or not isinstance(graph, dict):
            raise PoseContentError("animation document clips/state_graph must be objects")
        target_clip = str(clip_name or f"pose_{pose_name}")
        target_state = str(state_name) if state_name is not None else ""
        if not target_clip:
            raise PoseContentError("clip_name must not be empty")
        if target_clip in clips and not overwrite:
            raise PoseContentError(f"animation clip already exists: {target_clip}")
        if target_state and target_state in graph and not overwrite:
            raise PoseContentError(f"animation state already exists: {target_state}")
        clips[target_clip] = self.as_animation_clip(pose_name, duration=duration, loop=loop, mirrored=mirrored)
        if target_state:
            if not math.isfinite(float(blend)) or float(blend) < 0.0:
                raise PoseContentError("blend must be finite and >= 0")
            graph[target_state] = {"clip": target_clip, "loop": bool(loop), "blend": float(blend)}
        errors = validate_animation_document(out)
        if errors:
            raise PoseContentError("pose-generated animation document is invalid: " + "; ".join(errors[:8]))
        return out


def upsert_pose(
    document: dict[str, Any],
    name: str,
    pose: dict[str, Any],
    *,
    overwrite: bool = False,
) -> dict[str, Any]:
    if not name:
        raise PoseContentError("pose name must not be empty")
    out = deepcopy(document)
    poses = out.setdefault("poses", {})
    if not isinstance(poses, dict):
        raise PoseContentError("poses must be an object")
    if name in poses and not overwrite:
        raise PoseContentError(f"pose already exists: {name}")
    poses[name] = deepcopy(pose)
    errors = validate_pose_document(out)
    if errors:
        raise PoseContentError("invalid authored pose: " + "; ".join(errors[:8]))
    return out


def save_pose_library(
    path: str | os.PathLike[str],
    document: dict[str, Any],
    *,
    backup: bool = True,
) -> PoseSaveResult:
    """Atomically save validated authoring data, optionally preserving one backup."""
    errors = validate_pose_document(document)
    if errors:
        raise PoseContentError("refusing to save invalid pose library: " + "; ".join(errors[:8]))
    target = Path(path).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    raw = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if len(raw.encode("utf-8")) > MAX_LIBRARY_BYTES:
        raise PoseContentError("refusing to save pose library larger than configured limit")

    backup_path: Path | None = None
    if backup and target.exists():
        backup_path = target.with_suffix(target.suffix + ".bak")
        shutil.copy2(target, backup_path)
    temp = target.with_suffix(target.suffix + ".tmp")
    try:
        temp.write_text(raw, encoding="utf-8")
        os.replace(temp, target)
    finally:
        if temp.exists():
            temp.unlink()
    return PoseSaveResult(str(target), str(backup_path) if backup_path else None, len(document["poses"]))


_DEFAULT_CATALOG: PoseCatalog | None = None


def default_pose_catalog(*, reload: bool = False) -> PoseCatalog:
    global _DEFAULT_CATALOG
    if _DEFAULT_CATALOG is None:
        _DEFAULT_CATALOG = PoseCatalog()
    elif reload:
        _DEFAULT_CATALOG.reload()
    return _DEFAULT_CATALOG


def reset_pose_catalog_cache() -> None:
    global _DEFAULT_CATALOG
    _DEFAULT_CATALOG = None
