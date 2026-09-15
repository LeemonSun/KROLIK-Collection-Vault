from __future__ import annotations

"""Validated data-driven room templates for the KROLIK Vault.

Rooms are product content, not hardcoded scene branches.  A room template owns
visual theme, navigation hints, placement slots, capacity and fixture
compatibility.  World/cell records keep their own persistent identity and only
reference a room template by kind.
"""

from copy import deepcopy
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
from typing import Any

from prop_content import FixtureCatalog

ROOM_FORMAT_VERSION = 1
ROOM_SCHEMA = "krolik.room-library/1"
MAX_LIBRARY_BYTES = 1_048_576
MAX_ROOM_TYPES = 128
MAX_SLOTS_PER_ROOM = 64
MAX_BUILTINS_PER_ROOM = 32
DEFAULT_ROOM_LIBRARY_PATH = Path(__file__).resolve().parent / "content" / "rooms" / "default_v1.json"
ENV_LIBRARY_PATH = "KROLIK_ROOM_LIBRARY"


class RoomContentError(ValueError):
    pass


@dataclass(frozen=True)
class RoomLoadResult:
    document: dict[str, Any]
    source: str
    fallback_used: bool = False
    warnings: tuple[str, ...] = ()


def _finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _string_list(value: Any, *, limit: int = 64) -> bool:
    return isinstance(value, list) and len(value) <= limit and all(isinstance(item, str) and item for item in value)


def _color(value: Any) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 3
        and all(_finite(channel) and 0.0 <= float(channel) <= 1.0 for channel in value)
    )


def validate_room_document(document: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["room library must be a JSON object"]
    if document.get("schema") != ROOM_SCHEMA:
        errors.append(f"unsupported room schema: {document.get('schema')!r}")
    if document.get("format_version") != ROOM_FORMAT_VERSION:
        errors.append(
            f"unsupported room format_version {document.get('format_version')!r}; expected {ROOM_FORMAT_VERSION}"
        )

    rooms = document.get("rooms")
    if not isinstance(rooms, dict) or not rooms:
        errors.append("rooms must be a non-empty object")
        rooms = {}
    elif len(rooms) > MAX_ROOM_TYPES:
        errors.append(f"room count {len(rooms)} exceeds limit {MAX_ROOM_TYPES}")

    for raw_kind, room in rooms.items():
        kind = str(raw_kind)
        prefix = f"room {kind!r}"
        if not kind:
            errors.append("room kind must not be empty")
            continue
        if not isinstance(room, dict):
            errors.append(f"{prefix} must be an object")
            continue
        category = room.get("category")
        if not isinstance(category, str) or not category:
            errors.append(f"{prefix} category must be a non-empty string")
        if not _string_list(room.get("tags", []), limit=64):
            errors.append(f"{prefix} tags must be a bounded string array")

        dimensions = room.get("dimensions")
        if not isinstance(dimensions, dict):
            errors.append(f"{prefix} dimensions must be an object")
        else:
            for field in ("w", "h"):
                value = dimensions.get(field)
                if not _finite(value) or not (2.0 <= float(value) <= 100.0):
                    errors.append(f"{prefix} dimensions.{field} must be finite in [2, 100]")

        theme = room.get("theme")
        if not isinstance(theme, dict):
            errors.append(f"{prefix} theme must be an object")
        else:
            for field in ("floor_rgb", "border_rgb", "accent_rgb"):
                if not _color(theme.get(field)):
                    errors.append(f"{prefix} theme.{field} must be RGB values in [0, 1]")
            for field in ("ambient", "fog"):
                value = theme.get(field, 0.0)
                if not _finite(value) or not (0.0 <= float(value) <= 1.0):
                    errors.append(f"{prefix} theme.{field} must be finite in [0, 1]")

        navigation = room.get("navigation", {})
        if not isinstance(navigation, dict):
            errors.append(f"{prefix} navigation must be an object")
        else:
            for field, low, high in (("padding", 0.0, 4.0), ("doorway_width", 0.2, 8.0)):
                value = navigation.get(field, low)
                if not _finite(value) or not (low <= float(value) <= high):
                    errors.append(f"{prefix} navigation.{field} must be finite in [{low}, {high}]")

        capacity = room.get("capacity", 1)
        if not isinstance(capacity, int) or isinstance(capacity, bool) or not (1 <= capacity <= 64):
            errors.append(f"{prefix} capacity must be an integer in [1, 64]")

        compatibility = room.get("fixture_compatibility", {})
        if not isinstance(compatibility, dict):
            errors.append(f"{prefix} fixture_compatibility must be an object")
            compatibility = {}
        if not _string_list(compatibility.get("allowed_fixture_tags", []), limit=64):
            errors.append(f"{prefix} allowed_fixture_tags must be a bounded string array")
        if not _string_list(compatibility.get("preferred_fixture_kinds", []), limit=64):
            errors.append(f"{prefix} preferred_fixture_kinds must be a bounded string array")

        slots = room.get("placement_slots", [])
        if not isinstance(slots, list):
            errors.append(f"{prefix} placement_slots must be an array")
            slots = []
        elif len(slots) > MAX_SLOTS_PER_ROOM:
            errors.append(f"{prefix} placement slot count exceeds {MAX_SLOTS_PER_ROOM}")
        seen_slots: set[str] = set()
        for index, slot in enumerate(slots):
            sp = f"{prefix} placement slot {index}"
            if not isinstance(slot, dict):
                errors.append(f"{sp} must be an object")
                continue
            slot_id = slot.get("id")
            if not isinstance(slot_id, str) or not slot_id:
                errors.append(f"{sp}.id must be a non-empty string")
            elif slot_id in seen_slots:
                errors.append(f"{prefix} has duplicate placement slot id {slot_id!r}")
            else:
                seen_slots.add(slot_id)
            for field in ("x", "y"):
                value = slot.get(field)
                if not _finite(value) or not (0.0 <= float(value) <= 1.0):
                    errors.append(f"{sp}.{field} must be finite in [0, 1]")
            role = slot.get("role", "character")
            if not isinstance(role, str) or not role:
                errors.append(f"{sp}.role must be a non-empty string")
            if "accepts" in slot and not _string_list(slot["accepts"], limit=32):
                errors.append(f"{sp}.accepts must be a bounded string array")

        builtins = room.get("builtins", [])
        if not isinstance(builtins, list):
            errors.append(f"{prefix} builtins must be an array")
            builtins = []
        elif len(builtins) > MAX_BUILTINS_PER_ROOM:
            errors.append(f"{prefix} builtin count exceeds {MAX_BUILTINS_PER_ROOM}")
        for index, builtin in enumerate(builtins):
            bp = f"{prefix} builtin {index}"
            if not isinstance(builtin, dict):
                errors.append(f"{bp} must be an object")
                continue
            fixture = builtin.get("fixture")
            slot = builtin.get("slot")
            if not isinstance(fixture, str) or not fixture:
                errors.append(f"{bp}.fixture must be a non-empty string")
            if not isinstance(slot, str) or slot not in seen_slots:
                errors.append(f"{bp}.slot references missing placement slot {slot!r}")
    return errors


def validate_room_fixture_references(document: Any, fixtures: FixtureCatalog | None = None) -> list[str]:
    errors = validate_room_document(document)
    if errors or not isinstance(document, dict):
        return errors
    catalog = fixtures or FixtureCatalog()
    known = set(catalog.kinds())
    for kind, room in document["rooms"].items():
        preferred = room.get("fixture_compatibility", {}).get("preferred_fixture_kinds", [])
        for fixture in preferred:
            if fixture not in known:
                errors.append(f"room {kind!r} references unknown preferred fixture {fixture!r}")
        for builtin in room.get("builtins", []):
            fixture = builtin.get("fixture")
            if fixture not in known:
                errors.append(f"room {kind!r} references unknown builtin fixture {fixture!r}")
    return errors


def _read_json(path: Path) -> dict[str, Any]:
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise RoomContentError(f"room library is unavailable: {path}: {exc}") from exc
    if size > MAX_LIBRARY_BYTES:
        raise RoomContentError(f"room library is too large: {size} bytes > {MAX_LIBRARY_BYTES}: {path}")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RoomContentError(f"unable to read room library {path}: {exc}") from exc
    errors = validate_room_fixture_references(document)
    if errors:
        detail = "; ".join(errors[:12])
        if len(errors) > 12:
            detail += f"; ... {len(errors) - 12} more"
        raise RoomContentError(f"invalid room library {path}: {detail}")
    return document


def load_room_library(path: str | os.PathLike[str] | None = None, *, fallback_path: str | os.PathLike[str] | None = None) -> RoomLoadResult:
    primary = Path(path).expanduser().resolve() if path is not None else DEFAULT_ROOM_LIBRARY_PATH
    try:
        document = _read_json(primary)
        return RoomLoadResult(deepcopy(document), str(primary))
    except RoomContentError as primary_error:
        if fallback_path is None:
            raise
        fallback = Path(fallback_path).expanduser().resolve()
        if fallback == primary:
            raise
        document = _read_json(fallback)
        return RoomLoadResult(deepcopy(document), str(fallback), True, (str(primary_error),))


def load_default_room_library() -> RoomLoadResult:
    override = os.environ.get(ENV_LIBRARY_PATH, "").strip()
    if override:
        return load_room_library(override, fallback_path=DEFAULT_ROOM_LIBRARY_PATH)
    return load_room_library(DEFAULT_ROOM_LIBRARY_PATH)


class RoomCatalog:
    def __init__(self, path: str | os.PathLike[str] | None = None, *, fallback_path: str | os.PathLike[str] | None = None) -> None:
        self.path = path
        self.fallback_path = fallback_path
        self.revision = 0
        self.source = ""
        self._document: dict[str, Any] = {}
        self._rooms: dict[str, dict[str, Any]] = {}
        self.reload()

    def reload(self) -> RoomLoadResult:
        result = load_default_room_library() if self.path is None else load_room_library(self.path, fallback_path=self.fallback_path)
        self._document = deepcopy(result.document)
        self._rooms = deepcopy(self._document["rooms"])
        self.source = result.source
        self.revision += 1
        return RoomLoadResult(deepcopy(self._document), result.source, result.fallback_used, result.warnings)

    @property
    def document(self) -> dict[str, Any]:
        return deepcopy(self._document)

    def kinds(self) -> tuple[str, ...]:
        return tuple(sorted(self._rooms))

    def get(self, kind: str) -> dict[str, Any] | None:
        room = self._rooms.get(str(kind))
        return deepcopy(room) if isinstance(room, dict) else None

    def placement_slots(self, kind: str) -> list[dict[str, Any]]:
        room = self.get(kind) or {}
        return deepcopy(room.get("placement_slots", []))

    def capacity(self, kind: str) -> int:
        room = self.get(kind) or {}
        return int(room.get("capacity", 1))

    def supports_fixture(self, room_kind: str, fixture_kind: str, fixtures: FixtureCatalog | None = None) -> bool:
        room = self.get(room_kind)
        if room is None:
            return False
        catalog = fixtures or FixtureCatalog()
        fixture = catalog.get(fixture_kind)
        if fixture is None:
            return False
        compatibility = room.get("fixture_compatibility", {})
        preferred = set(compatibility.get("preferred_fixture_kinds", []))
        if fixture_kind in preferred:
            return True
        allowed_tags = set(compatibility.get("allowed_fixture_tags", []))
        return bool(allowed_tags.intersection(fixture.get("tags", [])))
