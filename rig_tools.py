from __future__ import annotations

"""Character rig helpers for KROLIK Collection Vault.

The rig format is deliberately small and portable: normalized 2D joints plus a
bone list.  A detector may provide better landmarks, but the format does not
depend on any single ML framework.  This means a rig created today with a
heuristic can later be refined by MediaPipe/MMPose or manually without breaking
placements or saved poses.
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageOps

try:
    import numpy as np
except Exception:  # pragma: no cover
    np = None  # type: ignore


RIG_FORMAT_VERSION = 1

DEFAULT_BONES = [
    ["head", "neck"],
    ["neck", "left_shoulder"], ["left_shoulder", "left_elbow"], ["left_elbow", "left_wrist"],
    ["neck", "right_shoulder"], ["right_shoulder", "right_elbow"], ["right_elbow", "right_wrist"],
    ["neck", "pelvis"],
    ["pelvis", "left_hip"], ["left_hip", "left_knee"], ["left_knee", "left_ankle"],
    ["pelvis", "right_hip"], ["right_hip", "right_knee"], ["right_knee", "right_ankle"],
]

JOINT_ORDER = [
    "head", "neck",
    "left_shoulder", "left_elbow", "left_wrist",
    "right_shoulder", "right_elbow", "right_wrist",
    "pelvis", "left_hip", "left_knee", "left_ankle",
    "right_hip", "right_knee", "right_ankle",
]


@dataclass
class RigDetection:
    joints: dict[str, dict[str, float]]
    settings: dict[str, Any]


def capabilities() -> dict[str, Any]:
    """Report local rig detectors without downloading anything."""
    backends = ["heuristic-silhouette"]
    mediapipe = False
    try:
        import mediapipe as mp  # type: ignore
        solutions = getattr(mp, "solutions", None)
        mediapipe = bool(solutions and hasattr(solutions, "pose"))
        if mediapipe:
            backends.insert(0, "mediapipe-pose")
    except Exception:
        pass
    return {
        "backends": backends,
        "mediapipe": mediapipe,
        "numpy": np is not None,
        "editable": True,
        "joint_count": len(JOINT_ORDER),
        "rig_format_version": RIG_FORMAT_VERSION,
        "bones": DEFAULT_BONES,
    }


def _load(path: str | Path) -> Image.Image:
    with Image.open(path) as opened:
        return ImageOps.exif_transpose(opened).convert("RGBA")


def _alpha_mask(im: Image.Image):
    if np is None:
        raise RuntimeError("Numpy is required for auto rig")
    a = np.asarray(im.getchannel("A"), dtype="uint8")
    if int(a.min()) >= 245:
        # With an opaque source, use luminance only to identify obvious card
        # borders.  The heuristic remains editable in the rig lab.
        return np.ones(a.shape, dtype=bool)
    return a > 32


def _bbox(mask):
    ys, xs = np.where(mask)
    if not len(xs):
        return 0, 0, mask.shape[1] - 1, mask.shape[0] - 1
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def _run_at(mask, y: int, x0: int, x1: int) -> tuple[float, float]:
    y = max(0, min(mask.shape[0] - 1, int(y)))
    xs = np.where(mask[y])[0]
    xs = xs[(xs >= x0) & (xs <= x1)]
    if not len(xs):
        return float(x0), float(x1)
    # Ignore single-pixel accessories/noise at the extremities.
    lo = float(np.quantile(xs, .05))
    hi = float(np.quantile(xs, .95))
    return lo, hi


def _norm(x: float, y: float, w: int, h: int) -> dict[str, float]:
    return {"x": round(max(0.0, min(1.0, x / max(1, w - 1))), 6),
            "y": round(max(0.0, min(1.0, y / max(1, h - 1))), 6)}


def heuristic_rig(path: str | Path) -> RigDetection:
    """Build an editable rig from the foreground silhouette.

    This is not presented as perfect pose estimation.  It exists so every image
    can enter the rig editor even when no AI pose backend is installed or when
    a stylized character defeats a human detector.
    """
    im = _load(path)
    w, h = im.size
    mask = _alpha_mask(im)
    x0, y0, x1, y1 = _bbox(mask)
    bw, bh = max(1, x1 - x0 + 1), max(1, y1 - y0 + 1)
    cx = (x0 + x1) / 2

    def y(frac: float) -> float:
        return y0 + bh * frac

    def ext(frac: float) -> tuple[float, float]:
        return _run_at(mask, int(y(frac)), x0, x1)

    sh_l, sh_r = ext(.22)
    el_l, el_r = ext(.38)
    wr_l, wr_r = ext(.52)
    hip_l_run, hip_r_run = ext(.51)
    knee_l_run, knee_r_run = ext(.72)
    ankle_l_run, ankle_r_run = ext(.90)

    # Insets prevent loose hair from becoming shoulder/elbow landmarks.
    shoulder_in = bw * .10
    arm_in = bw * .045
    hip_half = bw * .14
    leg_half = bw * .10

    joints = {
        "head": _norm(cx, y(.085), w, h),
        "neck": _norm(cx, y(.18), w, h),
        "left_shoulder": _norm(min(cx - bw*.12, sh_l + shoulder_in), y(.22), w, h),
        "left_elbow": _norm(min(cx - bw*.10, el_l + arm_in), y(.38), w, h),
        "left_wrist": _norm(min(cx - bw*.08, wr_l + arm_in), y(.53), w, h),
        "right_shoulder": _norm(max(cx + bw*.12, sh_r - shoulder_in), y(.22), w, h),
        "right_elbow": _norm(max(cx + bw*.10, el_r - arm_in), y(.38), w, h),
        "right_wrist": _norm(max(cx + bw*.08, wr_r - arm_in), y(.53), w, h),
        "pelvis": _norm(cx, y(.53), w, h),
        "left_hip": _norm(cx - hip_half, y(.52), w, h),
        "left_knee": _norm(cx - leg_half, y(.73), w, h),
        "left_ankle": _norm(cx - leg_half*.72, y(.91), w, h),
        "right_hip": _norm(cx + hip_half, y(.52), w, h),
        "right_knee": _norm(cx + leg_half, y(.73), w, h),
        "right_ankle": _norm(cx + leg_half*.72, y(.91), w, h),
    }
    return RigDetection(joints=joints, settings={
        "backend": "heuristic-silhouette",
        "rig_format_version": RIG_FORMAT_VERSION,
        "bones": DEFAULT_BONES,
        "mesh_cols": 12,
        "mesh_rows": 22,
        "influence_radius": .18,
        "preserve_volume": .55,
    })


def _mediapipe_rig(path: str | Path) -> RigDetection | None:
    """Try MediaPipe's bundled classic Pose API when available."""
    if np is None:
        return None
    try:
        import mediapipe as mp  # type: ignore
    except Exception:
        return None
    solutions = getattr(mp, "solutions", None)
    if not solutions or not hasattr(solutions, "pose"):
        return None
    im = _load(path)
    rgb = np.asarray(im.convert("RGB"))
    try:
        with solutions.pose.Pose(static_image_mode=True, model_complexity=2, enable_segmentation=False,
                                 min_detection_confidence=.35) as pose:
            res = pose.process(rgb)
    except Exception:
        return None
    if not getattr(res, "pose_landmarks", None):
        return None
    lm = res.pose_landmarks.landmark
    P = solutions.pose.PoseLandmark

    def get(idx):
        z = lm[idx.value if hasattr(idx, "value") else int(idx)]
        return {"x": round(float(z.x), 6), "y": round(float(z.y), 6)}

    left_ear, right_ear = get(P.LEFT_EAR), get(P.RIGHT_EAR)
    head = {"x": round((left_ear["x"] + right_ear["x"]) / 2, 6),
            "y": round((left_ear["y"] + right_ear["y"]) / 2, 6)}
    ls, rs = get(P.LEFT_SHOULDER), get(P.RIGHT_SHOULDER)
    lh, rh = get(P.LEFT_HIP), get(P.RIGHT_HIP)
    neck = {"x": round((ls["x"] + rs["x"]) / 2, 6), "y": round((ls["y"] + rs["y"]) / 2, 6)}
    pelvis = {"x": round((lh["x"] + rh["x"]) / 2, 6), "y": round((lh["y"] + rh["y"]) / 2, 6)}
    joints = {
        "head": head, "neck": neck,
        "left_shoulder": ls, "left_elbow": get(P.LEFT_ELBOW), "left_wrist": get(P.LEFT_WRIST),
        "right_shoulder": rs, "right_elbow": get(P.RIGHT_ELBOW), "right_wrist": get(P.RIGHT_WRIST),
        "pelvis": pelvis,
        "left_hip": lh, "left_knee": get(P.LEFT_KNEE), "left_ankle": get(P.LEFT_ANKLE),
        "right_hip": rh, "right_knee": get(P.RIGHT_KNEE), "right_ankle": get(P.RIGHT_ANKLE),
    }
    return RigDetection(joints=joints, settings={
        "backend": "mediapipe-pose",
        "rig_format_version": RIG_FORMAT_VERSION,
        "bones": DEFAULT_BONES,
        "mesh_cols": 14,
        "mesh_rows": 26,
        "influence_radius": .17,
        "preserve_volume": .62,
    })


def detect_rig(path: str | Path, prefer_ai: bool = True) -> RigDetection:
    if prefer_ai:
        mp_result = _mediapipe_rig(path)
        if mp_result is not None:
            return mp_result
    return heuristic_rig(path)
