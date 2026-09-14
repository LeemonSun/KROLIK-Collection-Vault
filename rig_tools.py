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
import os

from PIL import Image, ImageOps

try:
    import numpy as np
except Exception:  # pragma: no cover
    np = None  # type: ignore

try:
    import cv2  # type: ignore
except Exception:  # pragma: no cover
    cv2 = None  # type: ignore

try:
    import onnxruntime as ort  # type: ignore
except Exception:  # pragma: no cover
    ort = None  # type: ignore

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


def _dwpose_model_candidates() -> list[Path]:
    out: list[Path] = []
    env = os.environ.get("KROLIK_DWPOSE_MODEL", "").strip()
    if env:
        out.append(Path(env))
    root = Path(__file__).resolve().parent
    out.extend([
        root / "models" / "dwpose" / "dw-ll_ucoco_384.onnx",
        root / "models" / "dwpose" / "dwpose.onnx",
        root / "third_party" / "models" / "dwpose" / "dw-ll_ucoco_384.onnx",
    ])
    return out


def find_dwpose_model() -> Path | None:
    for path in _dwpose_model_candidates():
        if path.is_file():
            return path
    return None


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
    dwpose_model = find_dwpose_model()
    dwpose = bool(ort is not None and cv2 is not None and np is not None and dwpose_model is not None)
    if dwpose:
        backends.insert(0, "dwpose-onnx")
    return {
        "backends": backends,
        "mediapipe": mediapipe,
        "dwpose": dwpose,
        "dwpose_model": str(dwpose_model) if dwpose_model else None,
        "onnxruntime": ort is not None,
        "opencv": cv2 is not None,
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
    lo = float(np.quantile(xs, .05))
    hi = float(np.quantile(xs, .95))
    return lo, hi


def _norm(x: float, y: float, w: int, h: int) -> dict[str, float]:
    return {"x": round(max(0.0, min(1.0, x / max(1, w - 1))), 6),
            "y": round(max(0.0, min(1.0, y / max(1, h - 1))), 6)}


def heuristic_rig(path: str | Path) -> RigDetection:
    """Build an editable rig from the foreground silhouette."""
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


def _dwpose_provider_list() -> list[str]:
    if ort is None:
        return []
    try:
        available = set(ort.get_available_providers())
    except Exception:
        available = {"CPUExecutionProvider"}
    preferred = [
        "DmlExecutionProvider",
        "CUDAExecutionProvider",
        "ROCMExecutionProvider",
        "CoreMLExecutionProvider",
        "CPUExecutionProvider",
    ]
    return [name for name in preferred if name in available] or ["CPUExecutionProvider"]


def _dwpose_keypoints_to_rig(points, scores, width: int, height: int, min_conf: float = .18) -> RigDetection | None:
    """Map COCO/WholeBody's first 17 joints into the portable KROLIK rig."""
    if np is None:
        return None
    pts = np.asarray(points, dtype=float)
    conf = np.asarray(scores, dtype=float).reshape(-1)
    if pts.ndim != 2 or pts.shape[0] < 17 or pts.shape[1] < 2 or conf.size < 17:
        return None
    required = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    if sum(float(conf[i]) >= min_conf for i in required) < 8:
        return None

    def get(i: int) -> dict[str, float]:
        return _norm(float(pts[i, 0]), float(pts[i, 1]), width, height)

    ls, rs = get(5), get(6)
    lh, rh = get(11), get(12)
    face_candidates = [i for i in [0, 1, 2, 3, 4] if float(conf[i]) >= min_conf]
    if face_candidates:
        hx = sum(float(pts[i, 0]) for i in face_candidates) / len(face_candidates)
        hy = sum(float(pts[i, 1]) for i in face_candidates) / len(face_candidates)
        head = _norm(hx, hy, width, height)
    else:
        head = _norm((float(pts[5,0])+float(pts[6,0]))*.5, min(float(pts[5,1]),float(pts[6,1])) - height*.08, width, height)
    neck = {"x": round((ls["x"] + rs["x"]) / 2, 6), "y": round((ls["y"] + rs["y"]) / 2, 6)}
    pelvis = {"x": round((lh["x"] + rh["x"]) / 2, 6), "y": round((lh["y"] + rh["y"]) / 2, 6)}
    joints = {
        "head": head, "neck": neck,
        "left_shoulder": ls, "left_elbow": get(7), "left_wrist": get(9),
        "right_shoulder": rs, "right_elbow": get(8), "right_wrist": get(10),
        "pelvis": pelvis,
        "left_hip": lh, "left_knee": get(13), "left_ankle": get(15),
        "right_hip": rh, "right_knee": get(14), "right_ankle": get(16),
    }
    used_scores = [float(conf[i]) for i in required if float(conf[i]) >= 0.0]
    quality = sum(used_scores) / max(1, len(used_scores))
    return RigDetection(joints=joints, settings={
        "backend": "dwpose-onnx",
        "rig_format_version": RIG_FORMAT_VERSION,
        "bones": DEFAULT_BONES,
        "mesh_cols": 16,
        "mesh_rows": 30,
        "influence_radius": .155,
        "preserve_volume": .68,
        "pose_confidence": round(float(quality), 5),
    })


def _dwpose_third_point(a, b):
    direction = a - b
    return b + np.asarray([-direction[1], direction[0]], dtype=np.float32)


def _dwpose_affine_preprocess(image_bgr, bbox, in_w: int, in_h: int):
    """Match the official DWPose ONNX bbox->affine preprocessing path."""
    x0, y0, x1, y1 = [float(v) for v in bbox]
    center = np.asarray([(x0 + x1) * .5, (y0 + y1) * .5], dtype=np.float32)
    scale = np.asarray([max(2.0, x1 - x0), max(2.0, y1 - y0)], dtype=np.float32) * 1.25
    aspect = float(in_w) / float(in_h)
    if float(scale[0]) > float(scale[1]) * aspect:
        scale[1] = scale[0] / aspect
    else:
        scale[0] = scale[1] * aspect

    src_dir = np.asarray([0.0, float(scale[0]) * -0.5], dtype=np.float32)
    dst_dir = np.asarray([0.0, float(in_w) * -0.5], dtype=np.float32)
    src = np.zeros((3, 2), dtype=np.float32)
    dst = np.zeros((3, 2), dtype=np.float32)
    src[0] = center
    src[1] = center + src_dir
    src[2] = _dwpose_third_point(src[0], src[1])
    dst[0] = [float(in_w) * .5, float(in_h) * .5]
    dst[1] = dst[0] + dst_dir
    dst[2] = _dwpose_third_point(dst[0], dst[1])
    matrix = cv2.getAffineTransform(src, dst)
    warped = cv2.warpAffine(image_bgr, matrix, (int(in_w), int(in_h)), flags=cv2.INTER_LINEAR)
    mean = np.asarray([123.675, 116.28, 103.53], dtype=np.float32)
    std = np.asarray([58.395, 57.12, 57.375], dtype=np.float32)
    normalized = (warped.astype(np.float32) - mean) / std
    tensor = normalized.transpose(2, 0, 1)[None, ...].astype(np.float32)
    return tensor, center, scale


def _dwpose_infer_points(path: str | Path):
    """Return raw DWPose points/scores plus diagnostics before KROLIK filtering."""
    model = find_dwpose_model()
    if model is None or ort is None or cv2 is None or np is None:
        return None
    im = _load(path)
    # Official DWPose ONNX example reads images with cv2.imread (B,G,R order).
    image_bgr = np.asarray(im.convert("RGB"), dtype=np.uint8)[:, :, ::-1].copy()
    mask = _alpha_mask(im)
    x0, y0, x1, y1 = _bbox(mask)
    src_h, src_w = image_bgr.shape[:2]
    try:
        session = ort.InferenceSession(str(model), providers=_dwpose_provider_list())
        inp = session.get_inputs()[0]
        shape = inp.shape
        in_h = int(shape[2]) if isinstance(shape[2], int) else 384
        in_w = int(shape[3]) if isinstance(shape[3], int) else 288
        tensor, center, scale = _dwpose_affine_preprocess(
            image_bgr, (x0, y0, x1, y1), in_w, in_h
        )
        outputs = session.run(None, {inp.name: tensor})
    except Exception:
        return None
    if len(outputs) < 2:
        return None
    simcc_x = np.asarray(outputs[0])
    simcc_y = np.asarray(outputs[1])
    if simcc_x.ndim != 3 or simcc_y.ndim != 3:
        return None

    xs = np.argmax(simcc_x, axis=2).astype(np.float32) / 2.0
    ys = np.argmax(simcc_y, axis=2).astype(np.float32) / 2.0
    sx = np.max(simcc_x, axis=2)
    sy = np.max(simcc_y, axis=2)
    score = np.minimum(sx, sy)[0]
    points = np.stack([xs[0], ys[0]], axis=1)
    points = points / np.asarray([float(in_w), float(in_h)], dtype=np.float32)
    points = points * scale[None, :] + center[None, :] - scale[None, :] * .5

    required = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    core_scores = [float(score[index]) for index in required if index < score.shape[0]]
    diagnostics = {
        "model": str(model),
        "source_size": [int(src_w), int(src_h)],
        "bbox": [int(x0), int(y0), int(x1), int(y1)],
        "input_size": [int(in_w), int(in_h)],
        "center": [round(float(center[0]), 4), round(float(center[1]), 4)],
        "scale": [round(float(scale[0]), 4), round(float(scale[1]), 4)],
        "output_x_shape": [int(v) for v in simcc_x.shape],
        "output_y_shape": [int(v) for v in simcc_y.shape],
        "score_min": round(float(np.min(score)), 6),
        "score_max": round(float(np.max(score)), 6),
        "score_mean": round(float(np.mean(score)), 6),
        "core_scores": [round(value, 6) for value in core_scores],
        "core_above_018": sum(value >= .18 for value in core_scores),
        "providers": list(session.get_providers()),
    }
    return points, score, diagnostics


def dwpose_diagnostics(path: str | Path) -> dict[str, Any]:
    result = _dwpose_infer_points(path)
    if result is None:
        return {"status": "unavailable_or_inference_failed"}
    points, scores, diagnostics = result
    mapped = _dwpose_keypoints_to_rig(points, scores, diagnostics["source_size"][0], diagnostics["source_size"][1])
    return {
        **diagnostics,
        "status": "ok" if mapped is not None else "insufficient_core_confidence",
        "mapped": mapped is not None,
    }


def _dwpose_onnx_rig(path: str | Path) -> RigDetection | None:
    """Run local DWPose using KROLIK's single-character cutout bbox."""
    result = _dwpose_infer_points(path)
    if result is None:
        return None
    points, score, diagnostics = result
    src_w, src_h = diagnostics["source_size"]
    return _dwpose_keypoints_to_rig(points, score, int(src_w), int(src_h))


def detect_rig(path: str | Path, prefer_ai: bool = True) -> RigDetection:
    if prefer_ai:
        dw_result = _dwpose_onnx_rig(path)
        if dw_result is not None:
            return dw_result
        mp_result = _mediapipe_rig(path)
        if mp_result is not None:
            return mp_result
    return heuristic_rig(path)
