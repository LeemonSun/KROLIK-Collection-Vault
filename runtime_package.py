from __future__ import annotations

"""Portable runtime-character package builder for KROLIK Collection Vault.

This module bridges the editor/database world and the realtime Godot runtime.
It does not mutate source images.  A package contains one visual asset plus a
machine-readable manifest describing skeleton, collision proxies, animation
channels and autonomous-behaviour state.
"""

from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path
from typing import Any
import json
import math
import shutil

from animation_content import default_animation_document


RADIUS_BY_BONE = {
    ("head", "neck"): 0.055,
    ("neck", "pelvis"): 0.095,
    ("neck", "left_shoulder"): 0.055,
    ("left_shoulder", "left_elbow"): 0.045,
    ("left_elbow", "left_wrist"): 0.038,
    ("neck", "right_shoulder"): 0.055,
    ("right_shoulder", "right_elbow"): 0.045,
    ("right_elbow", "right_wrist"): 0.038,
    ("pelvis", "left_hip"): 0.070,
    ("left_hip", "left_knee"): 0.060,
    ("left_knee", "left_ankle"): 0.050,
    ("pelvis", "right_hip"): 0.070,
    ("right_hip", "right_knee"): 0.060,
    ("right_knee", "right_ankle"): 0.050,
}

# Backwards-compatible public names for callers/tests that still import the
# original defaults.  The source of truth is now the validated external JSON
# library under content/animations, not Python code.
_DEFAULT_ANIMATION = default_animation_document()
DEFAULT_ANIMATION_GRAPH = _DEFAULT_ANIMATION["state_graph"]
DEFAULT_POSE_CLIPS = _DEFAULT_ANIMATION["clips"]

SECONDARY_CHANNELS = {
    "hair": {"stiffness": 0.34, "damping": 0.74, "gravity": 0.18, "max_angle": 18.0},
    "chest": {"stiffness": 0.56, "damping": 0.84, "gravity": 0.04, "max_offset": 0.012},
    "hips": {"stiffness": 0.48, "damping": 0.81, "gravity": 0.06, "max_offset": 0.015},
    "accessories": {"stiffness": 0.28, "damping": 0.68, "gravity": 0.24, "max_angle": 24.0},
}


def _json(value: Any, default: Any) -> Any:
    if isinstance(value, (dict, list)):
        return value
    try:
        return json.loads(value or "")
    except Exception:
        return default


def _point(joints: dict[str, Any], name: str) -> dict[str, float] | None:
    p = joints.get(name)
    if not isinstance(p, dict):
        return None
    try:
        return {"x": float(p["x"]), "y": float(p["y"])}
    except Exception:
        return None


def collision_proxies(joints: dict[str, Any], bones: list[list[str]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for a, b in bones:
        pa, pb = _point(joints, a), _point(joints, b)
        if not pa or not pb:
            continue
        radius = RADIUS_BY_BONE.get((a, b), RADIUS_BY_BONE.get((b, a), 0.045))
        out.append({
            "type": "capsule_segment",
            "a": a,
            "b": b,
            "p0": pa,
            "p1": pb,
            "radius": radius,
            "sensor": False,
        })
    return out


SKIN_FORMAT_VERSION = 1


def _segment_distance(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    """Euclidean distance from a normalized point to a normalized segment."""
    dx, dy = bx - ax, by - ay
    denom = dx * dx + dy * dy
    if denom <= 1e-12:
        return math.hypot(px - ax, py - ay)
    t = ((px - ax) * dx + (py - ay) * dy) / denom
    t = max(0.0, min(1.0, t))
    qx, qy = ax + dx * t, ay + dy * t
    return math.hypot(px - qx, py - qy)


def build_skinning_mesh(
    joints: dict[str, Any],
    bones: list[list[str]],
    *,
    cols: int = 14,
    rows: int = 26,
    influence_radius: float = 0.17,
) -> dict[str, Any]:
    """Build a portable regular-grid GPU skin recipe for Godot Polygon2D."""
    cols = max(3, min(48, int(cols)))
    rows = max(3, min(72, int(rows)))
    radius = max(0.025, min(0.5, float(influence_radius)))
    vertices: list[list[float]] = []
    for iy in range(rows):
        y = iy / float(rows - 1)
        for ix in range(cols):
            x = ix / float(cols - 1)
            vertices.append([round(x, 7), round(y, 7)])

    triangles: list[int] = []
    for iy in range(rows - 1):
        for ix in range(cols - 1):
            i0 = iy * cols + ix
            i1 = i0 + 1
            i2 = i0 + cols
            i3 = i2 + 1
            triangles.extend([i0, i2, i1, i1, i2, i3])

    valid_bones: list[tuple[str, str, dict[str, float], dict[str, float]]] = []
    for raw in bones:
        if not isinstance(raw, (list, tuple)) or len(raw) != 2:
            continue
        a, b = str(raw[0]), str(raw[1])
        pa, pb = _point(joints, a), _point(joints, b)
        if pa and pb:
            valid_bones.append((a, b, pa, pb))

    if not valid_bones:
        return {
            "format_version": SKIN_FORMAT_VERSION,
            "backend": "godot_polygon2d_grid_v1",
            "cols": cols,
            "rows": rows,
            "vertices": vertices,
            "triangles": triangles,
            "bone_weights": [],
            "influence_radius": radius,
        }

    raw_by_bone: list[list[float]] = [[] for _ in valid_bones]
    for vx, vy in vertices:
        scores: list[float] = []
        for _, _, pa, pb in valid_bones:
            d = _segment_distance(vx, vy, pa["x"], pa["y"], pb["x"], pb["y"])
            score = math.exp(-((d / radius) ** 2) * 2.15) + 1e-8
            scores.append(score)
        total = sum(scores)
        if total <= 1e-12:
            nearest = max(range(len(scores)), key=lambda i: scores[i])
            scores = [1.0 if i == nearest else 0.0 for i in range(len(scores))]
            total = 1.0
        for i, score in enumerate(scores):
            raw_by_bone[i].append(score / total)

    weight_docs: list[dict[str, Any]] = []
    for (a, b, _, _), weights in zip(valid_bones, raw_by_bone):
        weight_docs.append({
            "a": a,
            "b": b,
            "weights": [round(float(w), 7) for w in weights],
        })
    return {
        "format_version": SKIN_FORMAT_VERSION,
        "backend": "godot_polygon2d_grid_v1",
        "cols": cols,
        "rows": rows,
        "vertices": vertices,
        "triangles": triangles,
        "bone_weights": weight_docs,
        "influence_radius": radius,
    }


def rig_health(joints: dict[str, Any], bones: list[list[str]]) -> dict[str, Any]:
    expected = {name for bone in bones for name in bone}
    present = {name for name in expected if _point(joints, name)}
    missing = sorted(expected - present)
    coverage = len(present) / max(1, len(expected))
    impossible: list[str] = []
    for name in present:
        p = _point(joints, name)
        if p and not (0.0 <= p["x"] <= 1.0 and 0.0 <= p["y"] <= 1.0):
            impossible.append(name)
    score = max(0.0, min(100.0, coverage * 100.0 - len(impossible) * 15.0))
    return {"score": round(score, 2), "coverage": round(coverage, 4), "missing": missing, "invalid": impossible}


def build_manifest(
    *,
    character: dict[str, Any],
    image_version: dict[str, Any],
    rig: dict[str, Any] | None,
    mind: dict[str, Any] | None,
    cell_id: str | None = None,
) -> dict[str, Any]:
    rest = _json((rig or {}).get("rest_json"), {})
    settings = _json((rig or {}).get("settings_json"), {})
    joints = rest.get("joints", {}) if isinstance(rest, dict) else {}
    bones = settings.get("bones", []) if isinstance(settings, dict) else []
    if not bones:
        try:
            from rig_tools import DEFAULT_BONES
            bones = DEFAULT_BONES
        except Exception:
            bones = []
    profile = _json((mind or {}).get("profile_json"), {})
    needs = _json((mind or {}).get("needs_json"), {})
    runtime = _json((mind or {}).get("runtime_json"), {})
    health = rig_health(joints, bones)
    skin = build_skinning_mesh(
        joints, bones,
        cols=int(settings.get("mesh_cols", 14)),
        rows=int(settings.get("mesh_rows", 26)),
        influence_radius=float(settings.get("influence_radius", 0.17)),
    )

    return {
        "schema": "krolik.runtime-character/1",
        "character": {
            "id": str(character.get("id") or ""),
            "name": str(character.get("name") or ""),
            "status": str(character.get("status") or ""),
            "home_cell": (mind or {}).get("home_cell_id") or cell_id,
        },
        "visual": {
            "file": "character.png",
            "width": int(image_version.get("width") or 0),
            "height": int(image_version.get("height") or 0),
            "version_id": int(image_version.get("id") or 0),
            "kind": str(image_version.get("kind") or ""),
            "pivot": {"x": 0.5, "y": 0.94},
            "render_mode": "deformable_2d",
        },
        "rig": {
            "format_version": int(settings.get("rig_format_version", 1)),
            "id": int((rig or {}).get("id") or 0),
            "backend": settings.get("backend", "none"),
            "joints": joints,
            "bones": bones,
            "mesh": {
                "cols": int(settings.get("mesh_cols", 14)),
                "rows": int(settings.get("mesh_rows", 26)),
                "influence_radius": float(settings.get("influence_radius", 0.17)),
                "preserve_volume": float(settings.get("preserve_volume", 0.62)),
            },
            "health": health,
            "confidence": {
                "pose": float(settings.get("pose_confidence", 0.0)),
                "joints": dict(settings.get("joint_confidence", {})) if isinstance(settings.get("joint_confidence", {}), dict) else {},
                "thresholds": dict(settings.get("joint_confidence_thresholds", {})) if isinstance(settings.get("joint_confidence_thresholds", {}), dict) else {},
                "status": dict(settings.get("joint_confidence_status", {})) if isinstance(settings.get("joint_confidence_status", {}), dict) else {},
                "low_confidence_joints": list(settings.get("low_confidence_joints", [])) if isinstance(settings.get("low_confidence_joints", []), list) else [],
                "guarded_joints": list(settings.get("guarded_joints", [])) if isinstance(settings.get("guarded_joints", []), list) else [],
                "uncertain_limbs": list(settings.get("uncertain_limbs", [])) if isinstance(settings.get("uncertain_limbs", []), list) else [],
                "exact_anchor_joints": list(settings.get("exact_anchor_joints", [])) if isinstance(settings.get("exact_anchor_joints", []), list) else [],
            },
            "skinning": skin,
        },
        "physics": {
            "collision": collision_proxies(joints, bones),
            "secondary": SECONDARY_CHANNELS,
            "floor_contact_joints": ["left_ankle", "right_ankle"],
        },
        "animation": default_animation_document(),
        "mind": {
            "enabled": bool((mind or {}).get("enabled", 0)),
            "state": str((mind or {}).get("state") or "idle"),
            "profile": profile,
            "needs": needs,
            "runtime": runtime,
        },
        "interaction": {
            "joint_targets": ["left_wrist", "right_wrist", "left_ankle", "right_ankle", "neck", "pelvis"],
            "ik_chains": {
                "left_wrist": ["left_shoulder", "left_elbow", "left_wrist"],
                "right_wrist": ["right_shoulder", "right_elbow", "right_wrist"],
                "left_ankle": ["left_hip", "left_knee", "left_ankle"],
                "right_ankle": ["right_hip", "right_knee", "right_ankle"],
            },
            "supports_constraints": True,
            "supports_props": True,
            "solver": "two_bone_ik_v1",
        },
        "quality": {
            "runtime_ready": health["score"] >= 80.0 and bool(joints),
            "rig_score": health["score"],
            "warnings": (["rig_missing_or_low_coverage"] if health["score"] < 80.0 else []),
        },
    }


def write_package(project_root: str | Path, character_id: str, source_image: str | Path, manifest: dict[str, Any]) -> dict[str, Any]:
    root = Path(project_root)
    safe = "".join(ch if (ch.isalnum() or ch in "-_.") else "_" for ch in character_id).strip("._") or "character"
    out = root / "exports" / "runtime" / safe
    out.mkdir(parents=True, exist_ok=True)
    image_out = out / "character.png"
    source = Path(source_image)
    try:
        from PIL import Image
        with Image.open(source) as im:
            im.convert("RGBA").save(image_out, "PNG", optimize=True)
    except Exception:
        shutil.copy2(source, image_out)
    raw = image_out.read_bytes()
    manifest = dict(manifest)
    manifest.setdefault("visual", {})["sha256"] = sha256(raw).hexdigest()
    manifest_path = out / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return {
        "folder": str(out),
        "image": str(image_out),
        "manifest": str(manifest_path),
        "runtime_ready": bool(manifest.get("quality", {}).get("runtime_ready")),
        "rig_score": float(manifest.get("quality", {}).get("rig_score", 0.0)),
    }
