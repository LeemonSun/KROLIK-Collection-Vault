from __future__ import annotations

"""Validated data-driven fixture/prop libraries for KROLIK.

The fixture library keeps reusable scene interaction data outside runtime code:
named anchors/sockets, render/occlusion metadata, collision profiles, occupancy
and default body-joint constraints.  Runtime/editor callers may inject a custom
catalog without changing the existing interaction payload shape.
"""

from copy import deepcopy
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
from typing import Any


FIXTURE_FORMAT_VERSION = 1
FIXTURE_SCHEMA = "krolik.fixture-library/1"
MAX_LIBRARY_BYTES = 1_048_576
MAX_FIXTURES = 256
MAX_ANCHORS_PER_FIXTURE = 64
MAX_CONSTRAINTS_PER_FIXTURE = 32
MAX_SLOTS_PER_FIXTURE = 32
DEFAULT_FIXTURE_LIBRARY_PATH = Path(__file__).resolve().parent / "content" / "fixtures" / "default_v1.json"
ENV_LIBRARY_PATH = "KROLIK_FIXTURE_LIBRARY"
OCCLUSION_MODES = {"none", "front", "back", "mixed"}
COLLISION_PROFILES = {"none", "solid", "sensor", "mixed"}
COLLISION_SHAPES = {"none", "rect", "circle", "capsule", "custom"}


class FixtureContentError(ValueError):
    """Raised when fixture content cannot be safely consumed."""


@dataclass(frozen=True)
class FixtureLoadResult:
    document: dict[str, Any]
    source: str
    fallback_used: bool = False
    warnings: tuple[str, ...] = ()


def _finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _string_list(value: Any, *, limit: int = 64) -> bool:
    return isinstance(value, list) and len(value) <= limit and all(isinstance(item, str) and item for item in value)


def validate_fixture_document(document: Any) -> list[str]:
    """Return deterministic validation errors for fixture-library format v1."""
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["fixture library must be a JSON object"]

    schema = document.get("schema", FIXTURE_SCHEMA)
    if schema != FIXTURE_SCHEMA:
        errors.append(f"unsupported fixture schema: {schema!r}")
    version = document.get("format_version")
    if version != FIXTURE_FORMAT_VERSION:
        errors.append(
            f"unsupported fixture format_version {version!r}; expected {FIXTURE_FORMAT_VERSION}"
        )

    fixtures = document.get("fixtures")
    if not isinstance(fixtures, dict) or not fixtures:
        errors.append("fixtures must be a non-empty object")
        fixtures = {}
    elif len(fixtures) > MAX_FIXTURES:
        errors.append(f"fixture count {len(fixtures)} exceeds limit {MAX_FIXTURES}")

    for raw_kind, fixture in fixtures.items():
        kind = str(raw_kind)
        prefix = f"fixture {kind!r}"
        if not kind:
            errors.append("fixture kind must not be empty")
            continue
        if not isinstance(fixture, dict):
            errors.append(f"{prefix} must be an object")
            continue

        category = fixture.get("category", "generic")
        if not isinstance(category, str) or not category:
            errors.append(f"{prefix} category must be a non-empty string")
        tags = fixture.get("tags", [])
        if not _string_list(tags, limit=64):
            errors.append(f"{prefix} tags must be a bounded string array")

        dimensions = fixture.get("dimensions", {})
        if not isinstance(dimensions, dict):
            errors.append(f"{prefix} dimensions must be an object")
        else:
            for field in ("w", "h"):
                value = dimensions.get(field, 1.0)
                if not _finite(value) or float(value) <= 0.0 or float(value) > 100.0:
                    errors.append(f"{prefix} dimensions.{field} must be finite in (0, 100]")

        render = fixture.get("render", {})
        if not isinstance(render, dict):
            errors.append(f"{prefix} render must be an object")
        else:
            occlusion = render.get("occlusion", "none")
            if occlusion not in OCCLUSION_MODES:
                errors.append(f"{prefix} render.occlusion must be one of {sorted(OCCLUSION_MODES)}")
            if "layer" in render and (not isinstance(render["layer"], int) or isinstance(render["layer"], bool)):
                errors.append(f"{prefix} render.layer must be an integer")
            if "z_offset" in render and not _finite(render["z_offset"]):
                errors.append(f"{prefix} render.z_offset must be finite numeric")

        collision = fixture.get("collision", {})
        if not isinstance(collision, dict):
            errors.append(f"{prefix} collision must be an object")
        else:
            profile = collision.get("profile", "none")
            shape = collision.get("shape", "none")
            if profile not in COLLISION_PROFILES:
                errors.append(f"{prefix} collision.profile must be one of {sorted(COLLISION_PROFILES)}")
            if shape not in COLLISION_SHAPES:
                errors.append(f"{prefix} collision.shape must be one of {sorted(COLLISION_SHAPES)}")

        occupancy = fixture.get("occupancy", {})
        if not isinstance(occupancy, dict):
            errors.append(f"{prefix} occupancy must be an object")
        else:
            capacity = occupancy.get("capacity", 0)
            if not isinstance(capacity, int) or isinstance(capacity, bool) or not (0 <= capacity <= 64):
                errors.append(f"{prefix} occupancy.capacity must be an integer in [0, 64]")
            if "exclusive" in occupancy and not isinstance(occupancy["exclusive"], bool):
                errors.append(f"{prefix} occupancy.exclusive must be boolean")

        anchors = fixture.get("anchors")
        if not isinstance(anchors, dict) or not anchors:
            errors.append(f"{prefix} anchors must be a non-empty object")
            anchors = {}
        elif len(anchors) > MAX_ANCHORS_PER_FIXTURE:
            errors.append(
                f"{prefix} anchor count {len(anchors)} exceeds limit {MAX_ANCHORS_PER_FIXTURE}"
            )
        for raw_name, anchor in anchors.items():
            name = str(raw_name)
            ap = f"{prefix} anchor {name!r}"
            if not name:
                errors.append(f"{prefix} anchor name must not be empty")
                continue
            if not isinstance(anchor, dict):
                errors.append(f"{ap} must be an object")
                continue
            for field in ("x", "y"):
                value = anchor.get(field)
                if not _finite(value) or abs(float(value)) > 4.0:
                    errors.append(f"{ap}.{field} must be finite and within [-4, 4]")
            if "angle" in anchor and not _finite(anchor["angle"]):
                errors.append(f"{ap}.angle must be finite numeric")
            if "tags" in anchor and not _string_list(anchor["tags"], limit=32):
                errors.append(f"{ap}.tags must be a bounded string array")

        slots = fixture.get("slots", {})
        if not isinstance(slots, dict):
            errors.append(f"{prefix} slots must be an object")
            slots = {}
        elif len(slots) > MAX_SLOTS_PER_FIXTURE:
            errors.append(f"{prefix} slot count {len(slots)} exceeds limit {MAX_SLOTS_PER_FIXTURE}")
        for raw_name, slot in slots.items():
            name = str(raw_name)
            sp = f"{prefix} slot {name!r}"
            if not name:
                errors.append(f"{prefix} slot name must not be empty")
                continue
            if not isinstance(slot, dict):
                errors.append(f"{sp} must be an object")
                continue
            anchor_name = slot.get("anchor")
            if not isinstance(anchor_name, str) or anchor_name not in anchors:
                errors.append(f"{sp} references missing anchor {anchor_name!r}")
            if "accepts" in slot and not _string_list(slot["accepts"], limit=32):
                errors.append(f"{sp}.accepts must be a bounded string array")

        constraints = fixture.get("constraints", [])
        if not isinstance(constraints, list):
            errors.append(f"{prefix} constraints must be an array")
            constraints = []
        elif len(constraints) > MAX_CONSTRAINTS_PER_FIXTURE:
            errors.append(
                f"{prefix} constraint count {len(constraints)} exceeds limit {MAX_CONSTRAINTS_PER_FIXTURE}"
            )
        for index, item in enumerate(constraints):
            cp = f"{prefix} constraint {index}"
            if not isinstance(item, dict):
                errors.append(f"{cp} must be an object")
                continue
            joint = item.get("joint")
            anchor_name = item.get("anchor")
            if not isinstance(joint, str) or not joint:
                errors.append(f"{cp}.joint must be a non-empty string")
            if not isinstance(anchor_name, str) or anchor_name not in anchors:
                errors.append(f"{cp} references missing anchor {anchor_name!r}")
            strength = item.get("strength", 1.0)
            if not _finite(strength) or not (0.0 <= float(strength) <= 1.0):
                errors.append(f"{cp}.strength must be finite in [0, 1]")
            stretch = item.get("max_stretch", 1.0)
            if not _finite(stretch) or not (0.01 <= float(stretch) <= 4.0):
                errors.append(f"{cp}.max_stretch must be finite in [0.01, 4]")

    return errors


def _read_json(path: Path) -> dict[str, Any]:
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise FixtureContentError(f"fixture library is unavailable: {path}: {exc}") from exc
    if size > MAX_LIBRARY_BYTES:
        raise FixtureContentError(
            f"fixture library is too large: {size} bytes > {MAX_LIBRARY_BYTES}: {path}"
        )
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise FixtureContentError(f"unable to read fixture library {path}: {exc}") from exc
    errors = validate_fixture_document(document)
    if errors:
        detail = "; ".join(errors[:12])
        if len(errors) > 12:
            detail += f"; ... {len(errors) - 12} more"
        raise FixtureContentError(f"invalid fixture library {path}: {detail}")
    return document


def load_fixture_library(
    path: str | os.PathLike[str] | None = None,
    *,
    fallback_path: str | os.PathLike[str] | None = None,
) -> FixtureLoadResult:
    primary = Path(path).expanduser().resolve() if path is not None else DEFAULT_FIXTURE_LIBRARY_PATH
    try:
        document = _read_json(primary)
        return FixtureLoadResult(deepcopy(document), str(primary))
    except FixtureContentError as primary_error:
        if fallback_path is None:
            raise
        fallback = Path(fallback_path).expanduser().resolve()
        if fallback == primary:
            raise
        document = _read_json(fallback)
        return FixtureLoadResult(
            deepcopy(document),
            str(fallback),
            fallback_used=True,
            warnings=(str(primary_error),),
        )


def load_default_fixture_library() -> FixtureLoadResult:
    override = os.environ.get(ENV_LIBRARY_PATH, "").strip()
    if override:
        return load_fixture_library(override, fallback_path=DEFAULT_FIXTURE_LIBRARY_PATH)
    return load_fixture_library(DEFAULT_FIXTURE_LIBRARY_PATH)


class FixtureCatalog:
    """Cached in-memory catalog with an explicit, deterministic reload path."""

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
        self._fixtures: dict[str, dict[str, Any]] = {}
        self.reload()

    def reload(self) -> FixtureLoadResult:
        if self.path is None:
            result = load_default_fixture_library()
        else:
            result = load_fixture_library(self.path, fallback_path=self.fallback_path)
        self._document = deepcopy(result.document)
        self._fixtures = deepcopy(self._document.get("fixtures", {}))
        self.source = result.source
        self.fallback_used = result.fallback_used
        self.warnings = result.warnings
        self.revision += 1
        return FixtureLoadResult(
            deepcopy(self._document),
            self.source,
            fallback_used=self.fallback_used,
            warnings=self.warnings,
        )

    @property
    def document(self) -> dict[str, Any]:
        return deepcopy(self._document)

    def kinds(self) -> tuple[str, ...]:
        return tuple(sorted(self._fixtures))

    def get(self, kind: str) -> dict[str, Any] | None:
        value = self._fixtures.get(str(kind))
        return deepcopy(value) if isinstance(value, dict) else None

    def anchor(self, kind: str, name: str) -> tuple[float, float] | None:
        fixture = self._fixtures.get(str(kind))
        if not isinstance(fixture, dict):
            return None
        anchors = fixture.get("anchors", {})
        anchor = anchors.get(str(name)) if isinstance(anchors, dict) else None
        if not isinstance(anchor, dict):
            return None
        return float(anchor["x"]), float(anchor["y"])

    def constraints(self, kind: str) -> list[dict[str, Any]]:
        fixture = self._fixtures.get(str(kind))
        if not isinstance(fixture, dict):
            return []
        constraints = fixture.get("constraints", [])
        return deepcopy(constraints) if isinstance(constraints, list) else []

    def runtime_profile(self, kind: str) -> dict[str, Any]:
        fixture = self.get(kind) or {}
        return {
            "kind": str(kind),
            "category": fixture.get("category", "generic"),
            "tags": deepcopy(fixture.get("tags", [])),
            "dimensions": deepcopy(fixture.get("dimensions", {})),
            "render": deepcopy(fixture.get("render", {})),
            "collision": deepcopy(fixture.get("collision", {})),
            "occupancy": deepcopy(fixture.get("occupancy", {})),
            "anchors": deepcopy(fixture.get("anchors", {})),
            "slots": deepcopy(fixture.get("slots", {})),
        }


_DEFAULT_CATALOG: FixtureCatalog | None = None


def default_fixture_catalog(*, reload: bool = False) -> FixtureCatalog:
    global _DEFAULT_CATALOG
    if _DEFAULT_CATALOG is None:
        _DEFAULT_CATALOG = FixtureCatalog()
    elif reload:
        _DEFAULT_CATALOG.reload()
    return _DEFAULT_CATALOG


def reset_fixture_catalog_cache() -> None:
    """Forget the shared catalog so tests/editor tooling can re-read overrides."""
    global _DEFAULT_CATALOG
    _DEFAULT_CATALOG = None
