from __future__ import annotations

"""Non-destructive image deformation driven by KROLIK normalized rig joints.

The first implementation deliberately uses a thin-plate-spline (TPS) inverse
warp.  It is deterministic, does not invent pixels, and works on any RGBA image.
It is a useful bridge between the editable skeleton/IK layer and the future
GPU weighted-mesh renderer in Godot.
"""

from pathlib import Path
from typing import Any
import math

from PIL import Image, ImageOps

try:
    import cv2  # type: ignore
    import numpy as np
except Exception:  # pragma: no cover
    cv2 = None  # type: ignore
    np = None  # type: ignore


def capabilities() -> dict[str, Any]:
    return {
        "backend": "bone-weighted-cpu-v1",
        "backends": ["bone-weighted-cpu-v1", "tps-cpu-v1"],
        "opencv": cv2 is not None,
        "numpy": np is not None,
        "supports_alpha": True,
        "non_destructive": True,
    }


def _norm_point(p: dict[str, Any]) -> tuple[float, float]:
    return float(p.get("x", 0.0)), float(p.get("y", 0.0))


def _kernel(r2):
    return r2 * np.log(np.maximum(r2, 1e-12))


def _fit_tps(dst_ctrl, src_ctrl, regularization: float = 1e-5):
    n = int(dst_ctrl.shape[0])
    diff = dst_ctrl[:, None, :] - dst_ctrl[None, :, :]
    k = _kernel(np.sum(diff * diff, axis=2))
    if regularization > 0:
        k = k + np.eye(n, dtype=np.float64) * float(regularization)
    p = np.concatenate([np.ones((n, 1), dtype=np.float64), dst_ctrl], axis=1)
    l = np.zeros((n + 3, n + 3), dtype=np.float64)
    l[:n, :n] = k
    l[:n, n:] = p
    l[n:, :n] = p.T
    y = np.zeros((n + 3, 2), dtype=np.float64)
    y[:n] = src_ctrl
    try:
        params = np.linalg.solve(l, y)
    except np.linalg.LinAlgError:
        params = np.linalg.lstsq(l, y, rcond=None)[0]
    return params[:n], params[n:]


def _eval_tps(points, ctrl, w, a):
    out = a[0] + points @ a[1:]
    chunk = 180_000
    result = np.empty((points.shape[0], 2), dtype=np.float64)
    for start in range(0, points.shape[0], chunk):
        stop = min(points.shape[0], start + chunk)
        q = points[start:stop]
        diff = q[:, None, :] - ctrl[None, :, :]
        u = _kernel(np.sum(diff * diff, axis=2))
        result[start:stop] = out[start:stop] + u @ w
    return result


def _fixed_anchors(width: int, height: int) -> list[tuple[float, float]]:
    w, h = float(width - 1), float(height - 1)
    return [
        (0.0, 0.0), (w * .5, 0.0), (w, 0.0),
        (0.0, h * .5), (w, h * .5),
        (0.0, h), (w * .5, h), (w, h),
    ]


def warp_rgba(
    image: Image.Image,
    rest_joints: dict[str, dict[str, Any]],
    posed_joints: dict[str, dict[str, Any]],
    *,
    regularization: float = 2e-4,
    fixed_border: bool = True,
    interpolation: str = "cubic",
) -> Image.Image:
    if np is None or cv2 is None:
        raise RuntimeError("mesh_deform requires numpy and opencv-python")
    im = ImageOps.exif_transpose(image).convert("RGBA")
    w, h = im.size
    names = [name for name in rest_joints if name in posed_joints]
    if len(names) < 3:
        return im.copy()
    src = []
    dst = []
    for name in names:
        rx, ry = _norm_point(rest_joints[name])
        px, py = _norm_point(posed_joints[name])
        src.append((rx * (w - 1), ry * (h - 1)))
        dst.append((px * (w - 1), py * (h - 1)))
    if fixed_border:
        anchors = _fixed_anchors(w, h)
        src.extend(anchors)
        dst.extend(anchors)
    src_ctrl = np.asarray(src, dtype=np.float64)
    dst_ctrl = np.asarray(dst, dtype=np.float64)
    if np.max(np.abs(src_ctrl - dst_ctrl)) < 1e-5:
        return im.copy()
    weights, affine = _fit_tps(dst_ctrl, src_ctrl, regularization=regularization)
    yy, xx = np.mgrid[0:h, 0:w]
    pts = np.column_stack([xx.reshape(-1), yy.reshape(-1)]).astype(np.float64)
    mapped = _eval_tps(pts, dst_ctrl, weights, affine)
    map_x = mapped[:, 0].reshape(h, w).astype(np.float32)
    map_y = mapped[:, 1].reshape(h, w).astype(np.float32)
    flag = cv2.INTER_CUBIC if interpolation == "cubic" else cv2.INTER_LINEAR
    arr = np.asarray(im, dtype=np.uint8)
    warped = cv2.remap(arr, map_x, map_y, flag, borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
    return Image.fromarray(warped, "RGBA")


def warp_file(
    source: str | Path,
    destination: str | Path,
    rest_joints: dict[str, dict[str, Any]],
    posed_joints: dict[str, dict[str, Any]],
    **kwargs: Any,
) -> dict[str, Any]:
    source = Path(source)
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as opened:
        out = warp_rgba(opened, rest_joints, posed_joints, **kwargs)
        out.save(destination, "PNG", optimize=True)
    return {"path": str(destination), "width": out.width, "height": out.height, "backend": "tps-cpu-v1"}


def _segment_distance(points, a, b):
    ab = b - a
    denom = float(ab[0] * ab[0] + ab[1] * ab[1])
    if denom <= 1e-12:
        return np.sqrt(np.sum((points - a) ** 2, axis=1))
    t = ((points - a) @ ab) / denom
    t = np.clip(t, 0.0, 1.0)
    proj = a[None, :] + t[:, None] * ab[None, :]
    return np.sqrt(np.sum((points - proj) ** 2, axis=1))


def _inverse_bone_map(points, rest_a, rest_b, pose_a, pose_b):
    rv = rest_b - rest_a
    pv = pose_b - pose_a
    rlen = float(np.linalg.norm(rv))
    plen = float(np.linalg.norm(pv))
    if rlen <= 1e-6 or plen <= 1e-6:
        return points.copy()
    ra = math.atan2(float(rv[1]), float(rv[0]))
    pa = math.atan2(float(pv[1]), float(pv[0]))
    ang = ra - pa
    c, s = math.cos(ang), math.sin(ang)
    rot = np.asarray([[c, -s], [s, c]], dtype=np.float64)
    scale = max(0.35, min(2.8, rlen / plen))
    local = points - pose_a[None, :]
    return rest_a[None, :] + (local @ rot.T) * scale


def warp_bone_weighted_rgba(
    image: Image.Image,
    rest_joints: dict[str, dict[str, Any]],
    posed_joints: dict[str, dict[str, Any]],
    bones: list[list[str]],
    *,
    influence_radius: float = 0.17,
    identity_weight: float = 0.08,
    max_influences: int = 4,
    interpolation: str = "cubic",
) -> Image.Image:
    """Locally deform a cutout with inverse linear-blend skinning.

    Each output pixel is influenced mostly by nearby posed bones, so a wrist
    edit no longer drags the opposite side of the body like a global rubber
    sheet. This is the CPU bridge toward GPU weighted-mesh skinning in Godot.
    """
    if np is None or cv2 is None:
        raise RuntimeError("mesh_deform requires numpy and opencv-python")
    im = ImageOps.exif_transpose(image).convert("RGBA")
    w, h = im.size
    bone_data: list[tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]] = []
    for raw in bones:
        if len(raw) != 2:
            continue
        a_name, b_name = raw
        if a_name not in rest_joints or b_name not in rest_joints:
            continue
        if a_name not in posed_joints or b_name not in posed_joints:
            continue
        rax, ray = _norm_point(rest_joints[a_name]); rbx, rby = _norm_point(rest_joints[b_name])
        pax, pay = _norm_point(posed_joints[a_name]); pbx, pby = _norm_point(posed_joints[b_name])
        rest_a = np.asarray([rax * (w - 1), ray * (h - 1)], dtype=np.float64)
        rest_b = np.asarray([rbx * (w - 1), rby * (h - 1)], dtype=np.float64)
        pose_a = np.asarray([pax * (w - 1), pay * (h - 1)], dtype=np.float64)
        pose_b = np.asarray([pbx * (w - 1), pby * (h - 1)], dtype=np.float64)
        bone_data.append((rest_a, rest_b, pose_a, pose_b))
    if not bone_data:
        return im.copy()
    moved = 0.0
    for ra, rb, pa, pb in bone_data:
        moved = max(moved, float(np.max(np.abs(ra - pa))), float(np.max(np.abs(rb - pb))))
    if moved < 1e-5:
        return im.copy()
    yy, xx = np.mgrid[0:h, 0:w]
    pts = np.column_stack([xx.reshape(-1), yy.reshape(-1)]).astype(np.float64)
    n_points = pts.shape[0]
    sigma = max(3.0, float(min(w, h)) * max(0.025, min(0.6, influence_radius)))
    k = max(1, min(int(max_influences), len(bone_data)))
    map_x = np.empty(n_points, dtype=np.float32)
    map_y = np.empty(n_points, dtype=np.float32)
    chunk = 120_000
    for start in range(0, n_points, chunk):
        stop = min(n_points, start + chunk)
        q = pts[start:stop]
        distances = np.empty((q.shape[0], len(bone_data)), dtype=np.float64)
        for i, (_, _, pa, pb) in enumerate(bone_data):
            distances[:, i] = _segment_distance(q, pa, pb)
        if k < len(bone_data):
            chosen = np.argpartition(distances, k - 1, axis=1)[:, :k]
        else:
            chosen = np.tile(np.arange(len(bone_data), dtype=np.int64), (q.shape[0], 1))
        chosen_dist = np.take_along_axis(distances, chosen, axis=1)
        weights = np.exp(-0.5 * (chosen_dist / sigma) ** 2)
        idw = np.full((q.shape[0], 1), max(0.0, float(identity_weight)), dtype=np.float64)
        acc = q * idw
        total = idw[:, 0].copy()
        for slot in range(chosen.shape[1]):
            idxs = chosen[:, slot]
            slot_w = weights[:, slot]
            mapped = np.empty_like(q)
            for bone_idx in np.unique(idxs):
                mask = idxs == bone_idx
                ra, rb, pa, pb = bone_data[int(bone_idx)]
                mapped[mask] = _inverse_bone_map(q[mask], ra, rb, pa, pb)
            acc += mapped * slot_w[:, None]
            total += slot_w
        out = acc / np.maximum(total[:, None], 1e-8)
        map_x[start:stop] = out[:, 0].astype(np.float32)
        map_y[start:stop] = out[:, 1].astype(np.float32)
    map_x = map_x.reshape(h, w)
    map_y = map_y.reshape(h, w)
    flag = cv2.INTER_CUBIC if interpolation == "cubic" else cv2.INTER_LINEAR
    arr = np.asarray(im, dtype=np.uint8)
    warped = cv2.remap(arr, map_x, map_y, flag, borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
    return Image.fromarray(warped, "RGBA")


def warp_bone_weighted_file(
    source: str | Path,
    destination: str | Path,
    rest_joints: dict[str, dict[str, Any]],
    posed_joints: dict[str, dict[str, Any]],
    bones: list[list[str]],
    **kwargs: Any,
) -> dict[str, Any]:
    source = Path(source)
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as opened:
        out = warp_bone_weighted_rgba(opened, rest_joints, posed_joints, bones, **kwargs)
        out.save(destination, "PNG", optimize=True)
    return {"path": str(destination), "width": out.width, "height": out.height, "backend": "bone-weighted-cpu-v1"}
