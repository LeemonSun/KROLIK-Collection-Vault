from __future__ import annotations

"""Small deterministic 2D IK/constraint primitives for KROLIK runtime.

The editor stores joints in normalized image coordinates.  This module solves
joint targets without mutating source art.  It is intentionally renderer-agnostic
so the exact same maths can be mirrored by the Godot runtime and unit-tested in
Python.
"""

from math import acos, atan2, cos, hypot, sin
from typing import Any


def _xy(p: dict[str, Any]) -> tuple[float, float]:
    return float(p.get("x", 0.0)), float(p.get("y", 0.0))


def _point(x: float, y: float) -> dict[str, float]:
    return {"x": float(x), "y": float(y)}


def distance(a: dict[str, Any], b: dict[str, Any]) -> float:
    ax, ay = _xy(a); bx, by = _xy(b)
    return hypot(bx - ax, by - ay)


def solve_two_bone(
    root: dict[str, Any],
    mid: dict[str, Any],
    end: dict[str, Any],
    target: dict[str, Any],
    *,
    bend_sign: float | None = None,
    max_stretch: float = 1.0,
) -> dict[str, dict[str, float]]:
    """Solve a planar two-bone chain while preserving segment lengths.

    `bend_sign` selects the elbow/knee side.  If omitted, the original chain's
    cross-product side is preserved.  Targets beyond reach are clamped rather
    than stretching the sprite into impossible proportions.
    """
    rx, ry = _xy(root); mx, my = _xy(mid); ex, ey = _xy(end); tx, ty = _xy(target)
    l1 = max(1e-8, hypot(mx-rx, my-ry))
    l2 = max(1e-8, hypot(ex-mx, ey-my))
    dx, dy = tx-rx, ty-ry
    d = hypot(dx, dy)
    if d < 1e-8:
        dx, dy, d = 1.0, 0.0, 1.0

    reach = (l1 + l2) * max(0.01, float(max_stretch))
    min_reach = abs(l1-l2) + 1e-8
    d_clamped = max(min_reach, min(d, reach))
    ux, uy = dx/d, dy/d
    endx, endy = rx + ux*d_clamped, ry + uy*d_clamped

    if bend_sign is None:
        cross = (mx-rx)*(ey-my) - (my-ry)*(ex-mx)
        bend_sign = -1.0 if cross < 0 else 1.0
    bend_sign = -1.0 if float(bend_sign) < 0 else 1.0

    a = (l1*l1 - l2*l2 + d_clamped*d_clamped) / (2.0*d_clamped)
    h_sq = max(0.0, l1*l1 - a*a)
    h = h_sq ** 0.5
    basex, basey = rx + ux*a, ry + uy*a
    perpx, perpy = -uy, ux
    midx = basex + perpx*h*bend_sign
    midy = basey + perpy*h*bend_sign

    return {"root": _point(rx, ry), "mid": _point(midx, midy), "end": _point(endx, endy)}


def apply_joint_target(
    joints: dict[str, dict[str, Any]],
    *,
    root: str,
    mid: str,
    end: str,
    target: dict[str, Any],
    strength: float = 1.0,
    max_stretch: float = 1.0,
) -> dict[str, dict[str, float]]:
    if any(name not in joints for name in (root, mid, end)):
        raise KeyError("В rig отсутствует сустав цепи")
    s = max(0.0, min(1.0, float(strength)))
    solved = solve_two_bone(joints[root], joints[mid], joints[end], target, max_stretch=max_stretch)
    out = {name: _point(*_xy(p)) for name, p in joints.items()}
    for name, key in ((root, "root"), (mid, "mid"), (end, "end")):
        ox, oy = _xy(out[name]); nx, ny = _xy(solved[key])
        out[name] = _point(ox + (nx-ox)*s, oy + (ny-oy)*s)
    return out


LIMB_CHAINS = {
    "left_wrist": ("left_shoulder", "left_elbow", "left_wrist"),
    "right_wrist": ("right_shoulder", "right_elbow", "right_wrist"),
    "left_ankle": ("left_hip", "left_knee", "left_ankle"),
    "right_ankle": ("right_hip", "right_knee", "right_ankle"),
}


def solve_constraints(joints: dict[str, dict[str, Any]], constraints: list[dict[str, Any]]) -> dict[str, dict[str, float]]:
    pose = {name: _point(*_xy(p)) for name, p in joints.items()}
    for item in constraints:
        if not item or not item.get("enabled", True):
            continue
        joint = str(item.get("joint") or "")
        chain = LIMB_CHAINS.get(joint)
        target = item.get("target")
        if not chain or not isinstance(target, dict):
            continue
        try:
            pose = apply_joint_target(
                pose, root=chain[0], mid=chain[1], end=chain[2], target=target,
                strength=float(item.get("strength", 1.0)),
                max_stretch=float(item.get("max_stretch", 1.0)),
            )
        except Exception:
            continue
    return pose
