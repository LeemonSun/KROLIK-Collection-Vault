from __future__ import annotations

"""Validated manual joint correction helpers for the portable KROLIK rig.

Corrections do not create a second rig format. They are an authoring operation
on the existing normalized joint map and therefore preserve RIG_FORMAT_VERSION.
The edit document itself is separately versioned for durable UI/CLI exchange.
"""

from copy import deepcopy
from math import hypot, isfinite
from pathlib import Path
from typing import Any
import json

from rig_tools import JOINT_ORDER


RIG_EDIT_SCHEMA = "krolik.rig-joint-overrides/1"
RIG_EDIT_FORMAT_VERSION = 1


def normalize_joint_overrides(document: dict[str, Any] | None) -> dict[str, dict[str, float]]:
    if document is None:
        return {}
    if not isinstance(document, dict):
        raise ValueError("joint override document must be a dictionary")

    if "schema" in document or "joints" in document:
        schema = str(document.get("schema") or RIG_EDIT_SCHEMA)
        if schema != RIG_EDIT_SCHEMA:
            raise ValueError(f"unsupported rig edit schema: {schema}")
        version = int(document.get("format_version", RIG_EDIT_FORMAT_VERSION))
        if version != RIG_EDIT_FORMAT_VERSION:
            raise ValueError(f"unsupported rig edit format version: {version}")
        raw = document.get("joints", {})
    else:
        raw = document

    if not isinstance(raw, dict):
        raise ValueError("joint overrides must be a dictionary")

    allowed = set(JOINT_ORDER)
    normalized: dict[str, dict[str, float]] = {}
    for raw_name, raw_point in raw.items():
        name = str(raw_name)
        if name not in allowed:
            raise ValueError(f"unknown rig joint: {name}")
        if not isinstance(raw_point, dict) or "x" not in raw_point or "y" not in raw_point:
            raise ValueError(f"joint override {name} must contain numeric x and y")
        try:
            x = float(raw_point["x"])
            y = float(raw_point["y"])
        except (TypeError, ValueError) as exc:
            raise ValueError(f"joint override {name} must contain numeric x and y") from exc
        if not isfinite(x) or not isfinite(y):
            raise ValueError(f"joint override {name} must be finite")
        if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
            raise ValueError(f"joint override {name} must stay inside normalized [0,1] bounds")
        normalized[name] = {"x": round(x, 6), "y": round(y, 6)}
    return normalized


def load_joint_overrides(path: str | Path) -> dict[str, dict[str, float]]:
    source = Path(path)
    try:
        document = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"unable to read joint override document: {exc}") from exc
    return normalize_joint_overrides(document)


def apply_joint_overrides(
    joints: dict[str, Any],
    overrides: dict[str, Any] | None,
) -> tuple[dict[str, dict[str, float]], dict[str, Any]]:
    """Return an edited copy plus deterministic provenance/quality metrics."""
    if not isinstance(joints, dict):
        raise ValueError("rig joints must be a dictionary")
    normalized = normalize_joint_overrides(overrides)
    edited = deepcopy(joints)
    changed: list[str] = []
    max_delta = 0.0

    for name in JOINT_ORDER:
        if name not in normalized:
            continue
        if name not in edited or not isinstance(edited[name], dict):
            raise ValueError(f"cannot override missing rig joint: {name}")
        try:
            before_x = float(edited[name]["x"])
            before_y = float(edited[name]["y"])
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(f"existing rig joint is invalid: {name}") from exc
        after = normalized[name]
        delta = hypot(after["x"] - before_x, after["y"] - before_y)
        if delta > 1e-9:
            changed.append(name)
            max_delta = max(max_delta, delta)
        edited[name] = dict(after)

    return edited, {
        "schema": RIG_EDIT_SCHEMA,
        "format_version": RIG_EDIT_FORMAT_VERSION,
        "override_count": len(normalized),
        "changed_count": len(changed),
        "changed_joints": changed,
        "max_delta": round(max_delta, 6),
        "joints": normalized,
    }


def build_joint_override_document(overrides: dict[str, Any]) -> dict[str, Any]:
    normalized = normalize_joint_overrides(overrides)
    return {
        "schema": RIG_EDIT_SCHEMA,
        "format_version": RIG_EDIT_FORMAT_VERSION,
        "joints": normalized,
    }
