from __future__ import annotations

"""Non-destructive migration layer for persisted KROLIK rig records.

The editor stores a rig as two JSON documents (``rest_json`` and
``settings_json``).  Runtime manifests expose the same information as joints,
bones and a format version.  This module is deliberately independent from the
UI/database layer so migrations stay testable even while the legacy editor
source is unavailable.

Important design rule: unknown joints, bones and metadata are preserved.  A
future format may add fingers, face landmarks, accessory roots, cloth anchors,
etc. without an older migration silently throwing those names away.
"""

from copy import deepcopy
from dataclasses import dataclass
import json
from typing import Any, Callable

from rig_tools import DEFAULT_BONES, RIG_FORMAT_VERSION


class RigMigrationError(ValueError):
    """Raised when a rig cannot be migrated without guessing or data loss."""


@dataclass(frozen=True)
class RigMigrationResult:
    rest: dict[str, Any]
    settings: dict[str, Any]
    from_version: int
    to_version: int
    applied_steps: tuple[str, ...]


def _json_object(value: Any, *, field: str) -> dict[str, Any]:
    if value is None or value == "":
        return {}
    if isinstance(value, dict):
        return deepcopy(value)
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
        except json.JSONDecodeError as exc:
            raise RigMigrationError(f"{field} is not valid JSON: {exc.msg}") from exc
        if not isinstance(decoded, dict):
            raise RigMigrationError(f"{field} must decode to an object")
        return decoded
    raise RigMigrationError(f"{field} must be an object or JSON object string")


def _version(rest: dict[str, Any], settings: dict[str, Any]) -> int:
    raw = settings.get("rig_format_version", rest.get("rig_format_version", 0))
    if raw in (None, ""):
        return 0
    try:
        version = int(raw)
    except (TypeError, ValueError) as exc:
        raise RigMigrationError(f"invalid rig format version: {raw!r}") from exc
    if version < 0:
        raise RigMigrationError(f"invalid negative rig format version: {version}")
    return version


def _looks_like_direct_joint_map(rest: dict[str, Any]) -> bool:
    if not rest or "joints" in rest:
        return False
    for value in rest.values():
        if not isinstance(value, dict) or "x" not in value or "y" not in value:
            return False
    return True


def _migrate_v0_to_v1(rest: dict[str, Any], settings: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Normalize pre-versioned rigs into the original explicit v1 contract."""
    out_rest = deepcopy(rest)
    out_settings = deepcopy(settings)

    # Very early prototypes could persist the joint map directly.  Wrapping it
    # is lossless and leaves every custom/future joint untouched.
    if _looks_like_direct_joint_map(out_rest):
        out_rest = {"joints": out_rest}

    joints = out_rest.get("joints", {})
    if joints is None:
        joints = {}
    if not isinstance(joints, dict):
        raise RigMigrationError("rest.joints must be an object")
    out_rest["joints"] = deepcopy(joints)

    bones = out_settings.get("bones")
    if bones is None or bones == []:
        out_settings["bones"] = deepcopy(DEFAULT_BONES)
    elif not isinstance(bones, list):
        raise RigMigrationError("settings.bones must be an array")

    out_settings["rig_format_version"] = 1
    out_rest.pop("rig_format_version", None)
    return out_rest, out_settings


Migration = Callable[[dict[str, Any], dict[str, Any]], tuple[dict[str, Any], dict[str, Any]]]
_MIGRATIONS: dict[int, tuple[int, str, Migration]] = {
    0: (1, "v0_to_v1", _migrate_v0_to_v1),
}


def migrate_rig_storage(
    rest: dict[str, Any] | str | None,
    settings: dict[str, Any] | str | None,
    *,
    target_version: int = RIG_FORMAT_VERSION,
) -> RigMigrationResult:
    """Migrate the two persisted rig JSON documents without mutating inputs.

    The migration chain is intentionally explicit.  When v2 adds more joints,
    bump ``RIG_FORMAT_VERSION`` and register ``1 -> 2`` here; v0/v1 collections
    will then walk the full chain.  Documents newer than this build are rejected
    rather than being destructively rewritten by an older application.
    """
    out_rest = _json_object(rest, field="rest_json")
    out_settings = _json_object(settings, field="settings_json")
    source_version = _version(out_rest, out_settings)

    if target_version < 1:
        raise RigMigrationError("target_version must be >= 1")
    if target_version > RIG_FORMAT_VERSION:
        raise RigMigrationError(
            f"target rig format v{target_version} is newer than supported v{RIG_FORMAT_VERSION}"
        )
    if source_version > RIG_FORMAT_VERSION:
        raise RigMigrationError(
            f"rig format v{source_version} is newer than supported v{RIG_FORMAT_VERSION}; refusing downgrade"
        )
    if source_version > target_version:
        raise RigMigrationError(
            f"refusing destructive rig downgrade v{source_version} -> v{target_version}"
        )

    current = source_version
    steps: list[str] = []
    while current < target_version:
        entry = _MIGRATIONS.get(current)
        if entry is None:
            raise RigMigrationError(f"no rig migration registered from v{current}")
        next_version, name, migration = entry
        if next_version <= current:
            raise RigMigrationError(f"invalid rig migration step {name}: v{current} -> v{next_version}")
        out_rest, out_settings = migration(out_rest, out_settings)
        current = next_version
        steps.append(name)

    # Validate the current contract but never prune unknown/custom names.
    joints = out_rest.get("joints", {})
    if not isinstance(joints, dict):
        raise RigMigrationError("rest.joints must be an object")
    bones = out_settings.get("bones", [])
    if not isinstance(bones, list):
        raise RigMigrationError("settings.bones must be an array")
    for index, bone in enumerate(bones):
        if not isinstance(bone, (list, tuple)) or len(bone) != 2:
            raise RigMigrationError(f"settings.bones[{index}] must contain exactly two joint names")
        if not all(isinstance(name, str) and name for name in bone):
            raise RigMigrationError(f"settings.bones[{index}] contains an invalid joint name")

    out_settings["rig_format_version"] = current
    out_rest.pop("rig_format_version", None)
    return RigMigrationResult(
        rest=out_rest,
        settings=out_settings,
        from_version=source_version,
        to_version=current,
        applied_steps=tuple(steps),
    )


def migrate_rig_record(record: dict[str, Any], *, target_version: int = RIG_FORMAT_VERSION) -> RigMigrationResult:
    """Migrate a database-like row containing ``rest_json``/``settings_json``."""
    if not isinstance(record, dict):
        raise RigMigrationError("rig record must be an object")
    return migrate_rig_storage(
        record.get("rest_json"),
        record.get("settings_json"),
        target_version=target_version,
    )


def migrated_record_copy(record: dict[str, Any], *, target_version: int = RIG_FORMAT_VERSION) -> dict[str, Any]:
    """Return a copy suitable for persistence; never changes the caller's row."""
    result = migrate_rig_record(record, target_version=target_version)
    out = deepcopy(record)
    out["rest_json"] = json.dumps(result.rest, ensure_ascii=False, separators=(",", ":"))
    out["settings_json"] = json.dumps(result.settings, ensure_ascii=False, separators=(",", ":"))
    return out
