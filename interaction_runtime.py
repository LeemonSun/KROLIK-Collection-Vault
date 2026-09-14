from __future__ import annotations

"""Runtime interaction helpers for KROLIK Collection Vault.

Fixture geometry/anchors/default constraints are loaded from the validated
fixture content catalog.  The public interaction payload remains compatible
with existing callers; optional catalog injection lets editor/content tools use
custom libraries and hot reload them without changing runtime code.
"""

from math import cos, radians, sin
from typing import Any

from prop_content import FixtureCatalog, default_fixture_catalog


# Backward-compatible fallback for unknown legacy prop kinds. Known fixture
# kinds resolve their anchors from content/fixtures/default_v1.json.
ANCHOR_LOCAL = {
    "center": (0.0, 0.0), "top": (0.0, -0.5), "bottom": (0.0, 0.5),
    "left": (-0.5, 0.0), "right": (0.5, 0.0),
    "top_left": (-0.5, -0.5), "top_right": (0.5, -0.5),
    "bottom_left": (-0.5, 0.5), "bottom_right": (0.5, 0.5),
}


def _catalog(catalog: FixtureCatalog | None) -> FixtureCatalog:
    return catalog if catalog is not None else default_fixture_catalog()


def _compat_constraint_presets() -> dict[str, list[tuple[str, str]]]:
    catalog = default_fixture_catalog()
    out: dict[str, list[tuple[str, str]]] = {}
    for kind in catalog.kinds():
        pairs: list[tuple[str, str]] = []
        for item in catalog.constraints(kind):
            joint = str(item.get("joint") or "")
            anchor = str(item.get("anchor") or "")
            if joint and anchor:
                pairs.append((joint, anchor))
        if pairs:
            out[kind] = pairs
    return out


# Compatibility import surface for older callers/tests. Runtime resolution no
# longer consumes this table; it is a snapshot derived from the JSON catalog.
FIXTURE_CONSTRAINT_PRESETS = _compat_constraint_presets()


def _f(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return float(default)


def anchor_point(
    prop: dict[str, Any],
    anchor: str,
    *,
    catalog: FixtureCatalog | None = None,
) -> dict[str, float]:
    kind = str(prop.get("kind") or "")
    local = _catalog(catalog).anchor(kind, str(anchor))
    if local is None:
        local = ANCHOR_LOCAL.get(str(anchor), ANCHOR_LOCAL["center"])
    lx, ly = local
    w, h = max(0.0, _f(prop.get("w"), 0.0)), max(0.0, _f(prop.get("h"), 0.0))
    px, py = _f(prop.get("x"), 0.5), _f(prop.get("y"), 0.5)
    ox, oy = lx * w, ly * h
    angle = radians(_f(prop.get("rotation"), 0.0))
    rx = ox * cos(angle) - oy * sin(angle)
    ry = ox * sin(angle) + oy * cos(angle)
    return {"x": px + rx, "y": py + ry}


def fixture_runtime_profile(
    prop: dict[str, Any],
    *,
    catalog: FixtureCatalog | None = None,
) -> dict[str, Any]:
    """Return content-authored render/collision/occupancy/socket metadata."""
    return _catalog(catalog).runtime_profile(str(prop.get("kind") or ""))


def resolve_constraint_items(
    items: list[dict[str, Any]],
    props_by_id: dict[int, dict[str, Any]],
    *,
    catalog: FixtureCatalog | None = None,
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    active_catalog = _catalog(catalog)
    for raw in items:
        if not isinstance(raw, dict):
            continue
        try:
            prop_id = int(raw.get("prop_id"))
        except Exception:
            continue
        prop = props_by_id.get(prop_id)
        if not prop:
            continue
        anchor = str(raw.get("anchor") or "center")
        item = dict(raw)
        item["prop_id"] = prop_id
        item["anchor"] = anchor
        item["target"] = anchor_point(prop, anchor, catalog=active_catalog)
        item["prop_kind"] = str(prop.get("kind") or "")
        item["strength"] = max(0.0, min(1.0, _f(item.get("strength"), 1.0)))
        item["enabled"] = bool(item.get("enabled", True))
        item["max_stretch"] = max(0.01, min(4.0, _f(item.get("max_stretch"), 1.0)))
        out.append(item)
    return out


def preset_constraints(
    prop: dict[str, Any],
    *,
    strength: float = 1.0,
    catalog: FixtureCatalog | None = None,
) -> list[dict[str, Any]]:
    """Build default body-joint constraints from fixture content data."""
    active_catalog = _catalog(catalog)
    scale = max(0.0, min(1.0, float(strength)))
    out: list[dict[str, Any]] = []
    for raw in active_catalog.constraints(str(prop.get("kind") or "")):
        joint = str(raw.get("joint") or "")
        anchor = str(raw.get("anchor") or "")
        if not joint or not anchor:
            continue
        out.append({
            "joint": joint,
            "prop_id": int(prop.get("id") or 0),
            "anchor": anchor,
            "enabled": bool(raw.get("enabled", True)),
            "strength": max(0.0, min(1.0, _f(raw.get("strength"), 1.0) * scale)),
            "max_stretch": max(0.01, min(4.0, _f(raw.get("max_stretch"), 1.0))),
        })
    return out


def runtime_interaction(
    *,
    placement_interaction: dict[str, Any] | None,
    constraint_doc: dict[str, Any] | None,
    props: list[dict[str, Any]],
    catalog: FixtureCatalog | None = None,
) -> dict[str, Any]:
    active_catalog = _catalog(catalog)
    props_by_id = {int(p.get("id") or 0): p for p in props if int(p.get("id") or 0) > 0}
    items = (constraint_doc or {}).get("items", [])
    if not isinstance(items, list):
        items = []
    resolved = resolve_constraint_items(items, props_by_id, catalog=active_catalog)
    interaction = dict(placement_interaction or {})
    mode = str(interaction.get("mode") or "free")
    contained = mode in {"bound", "contained", "anchored", "restrained"} or bool(resolved)
    return {
        "mode": mode,
        "contained": contained,
        "constraints": resolved,
        "constraint_count": len(resolved),
    }
