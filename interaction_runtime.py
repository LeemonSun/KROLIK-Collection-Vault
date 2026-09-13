from __future__ import annotations

"""Runtime interaction helpers for KROLIK Collection Vault."""

from math import cos, radians, sin
from typing import Any

ANCHOR_LOCAL = {
    "center": (0.0, 0.0), "top": (0.0, -0.5), "bottom": (0.0, 0.5),
    "left": (-0.5, 0.0), "right": (0.5, 0.0),
    "top_left": (-0.5, -0.5), "top_right": (0.5, -0.5),
    "bottom_left": (-0.5, 0.5), "bottom_right": (0.5, 0.5),
}

FIXTURE_CONSTRAINT_PRESETS = {
    "wall_cuffs": [("left_wrist", "left"), ("right_wrist", "right")],
    "floor_shackles": [("left_ankle", "left"), ("right_ankle", "right")],
    "x_frame": [
        ("left_wrist", "top_left"), ("right_wrist", "top_right"),
        ("left_ankle", "bottom_left"), ("right_ankle", "bottom_right"),
    ],
    "stocks": [("left_wrist", "left"), ("right_wrist", "right")],
    "hanging_chains": [("left_wrist", "top_left"), ("right_wrist", "top_right")],
    "suspension_ring": [("left_wrist", "left"), ("right_wrist", "right")],
    "iron_post": [("left_wrist", "center"), ("right_wrist", "center")],
}


def _f(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return float(default)


def anchor_point(prop: dict[str, Any], anchor: str) -> dict[str, float]:
    lx, ly = ANCHOR_LOCAL.get(str(anchor), ANCHOR_LOCAL["center"])
    w, h = max(0.0, _f(prop.get("w"), 0.0)), max(0.0, _f(prop.get("h"), 0.0))
    px, py = _f(prop.get("x"), 0.5), _f(prop.get("y"), 0.5)
    ox, oy = lx * w, ly * h
    angle = radians(_f(prop.get("rotation"), 0.0))
    rx = ox * cos(angle) - oy * sin(angle)
    ry = ox * sin(angle) + oy * cos(angle)
    return {"x": px + rx, "y": py + ry}


def resolve_constraint_items(items: list[dict[str, Any]], props_by_id: dict[int, dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
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
        item["target"] = anchor_point(prop, anchor)
        item["prop_kind"] = str(prop.get("kind") or "")
        item["strength"] = max(0.0, min(1.0, _f(item.get("strength"), 1.0)))
        item["enabled"] = bool(item.get("enabled", True))
        item.setdefault("max_stretch", 1.0)
        out.append(item)
    return out


def preset_constraints(prop: dict[str, Any], *, strength: float = 1.0) -> list[dict[str, Any]]:
    pairs = FIXTURE_CONSTRAINT_PRESETS.get(str(prop.get("kind") or ""), [])
    return [{
        "joint": joint, "prop_id": int(prop.get("id") or 0), "anchor": anchor,
        "enabled": True, "strength": max(0.0, min(1.0, float(strength))),
    } for joint, anchor in pairs]


def runtime_interaction(*, placement_interaction: dict[str, Any] | None, constraint_doc: dict[str, Any] | None, props: list[dict[str, Any]]) -> dict[str, Any]:
    props_by_id = {int(p.get("id") or 0): p for p in props if int(p.get("id") or 0) > 0}
    items = (constraint_doc or {}).get("items", [])
    if not isinstance(items, list):
        items = []
    resolved = resolve_constraint_items(items, props_by_id)
    interaction = dict(placement_interaction or {})
    mode = str(interaction.get("mode") or "free")
    contained = mode in {"bound", "contained", "anchored", "restrained"} or bool(resolved)
    return {"mode": mode, "contained": contained, "constraints": resolved, "constraint_count": len(resolved)}
