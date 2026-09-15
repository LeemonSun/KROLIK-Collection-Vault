from __future__ import annotations

"""Deterministic matte cleanup and edge quality metrics for KROLIK cutouts.

v3 treats a cutout as two independent problems:
1) alpha segmentation must not retain a broad background-coloured fringe;
2) RGB hidden under antialiased/transparent texels must be decontaminated so
   texture filtering and mip generation do not re-introduce a white/grey halo.

The routines are deliberately model-independent and run after any segmentation
backend (embedded alpha, fast border cutout, GrabCut, or a future ONNX matte).
"""

from typing import Any

import numpy as np
from PIL import Image

try:
    import cv2  # type: ignore
except Exception:  # pragma: no cover
    cv2 = None  # type: ignore


MATTE_QUALITY_VERSION = 3
DEFAULT_HALO_REVIEW_THRESHOLD = 0.24


def _as_rgba(image: Image.Image) -> np.ndarray:
    return np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()


def _local_rgb_mean(rgb: np.ndarray, mask: np.ndarray, kernel_size: int) -> tuple[np.ndarray, np.ndarray]:
    weights = mask.astype(np.float32)
    count = cv2.boxFilter(weights, -1, (kernel_size, kernel_size), normalize=False, borderType=cv2.BORDER_REFLECT)
    mean = np.empty_like(rgb, dtype=np.float32)
    for channel in range(3):
        summed = cv2.boxFilter(
            rgb[:, :, channel].astype(np.float32) * weights,
            -1,
            (kernel_size, kernel_size),
            normalize=False,
            borderType=cv2.BORDER_REFLECT,
        )
        mean[:, :, channel] = summed / np.maximum(count, 1e-6)
    return mean, count


def _fringe_width(alpha: np.ndarray) -> dict[str, float]:
    if cv2 is None:
        return {"p95": 0.0, "p99": 0.0, "max": 0.0}
    core = alpha >= 245
    support = alpha > 0
    soft = support & ~core
    if not bool(np.any(core)) or not bool(np.any(soft)):
        return {"p95": 0.0, "p99": 0.0, "max": 0.0}
    distance = cv2.distanceTransform((~core).astype(np.uint8), cv2.DIST_L2, 5)
    values = distance[soft]
    return {
        "p95": round(float(np.percentile(values, 95.0)), 4),
        "p99": round(float(np.percentile(values, 99.0)), 4),
        "max": round(float(np.max(values)), 4),
    }


def refine_alpha_boundary(image: Image.Image) -> tuple[Image.Image, dict[str, Any]]:
    """Suppress background-like pixels in a narrow cutout boundary band.

    GrabCut/border segmentation can leave a 3-8 px opaque or semi-opaque rim of
    studio floor/background. We compare each boundary texel with local outside
    colour and a deeper local foreground reference. Pixels that look more like
    their surrounding background lose alpha; interior pixels are untouched.
    """
    rgba = _as_rgba(image)
    alpha_u8 = rgba[:, :, 3]
    support = alpha_u8 > 0
    support_count = int(np.count_nonzero(support))
    if cv2 is None or support_count <= 0:
        return Image.fromarray(rgba, mode="RGBA"), {
            "alpha_boundary_refined": False,
            "alpha_trimmed_pixels": 0,
            "alpha_coverage_before": round(float(np.mean(support)), 6),
            "alpha_coverage_after": round(float(np.mean(support)), 6),
            "fringe_width_before": _fringe_width(alpha_u8),
            "fringe_width_after": _fringe_width(alpha_u8),
        }

    height, width = alpha_u8.shape
    radius = max(2, int(round(min(width, height) * 0.0075)))
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (radius * 2 + 1, radius * 2 + 1))
    interior = cv2.erode(support.astype(np.uint8), kernel) > 0
    outside = ~support
    boundary = support & ~interior
    if not bool(np.any(interior)) or not bool(np.any(boundary)):
        return Image.fromarray(rgba, mode="RGBA"), {
            "alpha_boundary_refined": False,
            "alpha_trimmed_pixels": 0,
            "alpha_coverage_before": round(float(np.mean(support)), 6),
            "alpha_coverage_after": round(float(np.mean(support)), 6),
            "fringe_width_before": _fringe_width(alpha_u8),
            "fringe_width_after": _fringe_width(alpha_u8),
        }

    rgb = rgba[:, :, :3].astype(np.float32)
    local_size = max(9, radius * 4 + 1)
    if local_size % 2 == 0:
        local_size += 1
    bg_rgb, bg_count = _local_rgb_mean(rgb, outside, local_size)
    fg_rgb, fg_count = _local_rgb_mean(rgb, interior, local_size)
    bg_distance = np.linalg.norm(rgb - bg_rgb, axis=2)
    fg_distance = np.linalg.norm(rgb - fg_rgb, axis=2)
    fg_likelihood = bg_distance / (bg_distance + fg_distance + 1e-6)

    valid = boundary & (bg_count >= 3.0) & (fg_count >= 3.0)
    factor = np.clip((fg_likelihood - 0.28) / 0.36, 0.0, 1.0)
    old_alpha = alpha_u8.astype(np.float32)
    new_alpha = old_alpha.copy()
    new_alpha[valid] = old_alpha[valid] * factor[valid]
    new_alpha[new_alpha < 10.0] = 0.0
    alpha_after = np.clip(new_alpha, 0.0, 255.0).astype(np.uint8)
    rgba[:, :, 3] = alpha_after

    changed = np.abs(alpha_after.astype(np.int16) - alpha_u8.astype(np.int16)) >= 8
    before_width = _fringe_width(alpha_u8)
    after_width = _fringe_width(alpha_after)
    return Image.fromarray(rgba, mode="RGBA"), {
        "alpha_boundary_refined": bool(np.any(changed)),
        "alpha_trimmed_pixels": int(np.count_nonzero(changed)),
        "alpha_coverage_before": round(float(np.mean(alpha_u8 > 0)), 6),
        "alpha_coverage_after": round(float(np.mean(alpha_after > 0)), 6),
        "fringe_width_before": before_width,
        "fringe_width_after": after_width,
    }


def _propagate_interior_rgb(rgba: np.ndarray, *, max_steps: int = 48) -> tuple[np.ndarray, np.ndarray]:
    rgb = rgba[:, :, :3].astype(np.float32)
    alpha = rgba[:, :, 3]
    support = alpha > 0
    known = alpha >= 245
    if not bool(np.any(support)) or not bool(np.any(known)) or cv2 is None:
        return rgb, known

    pad_radius = max(2, int(round(min(alpha.shape) * 0.010)))
    pad_kernel = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE,
        (pad_radius * 2 + 1, pad_radius * 2 + 1),
    )
    propagation_support = cv2.dilate(support.astype(np.uint8), pad_kernel) > 0

    out = rgb.copy()
    kernel = np.ones((3, 3), dtype=np.float32)
    for _ in range(max(1, int(max_steps))):
        target = propagation_support & ~known
        if not bool(np.any(target)):
            break
        count = cv2.filter2D(known.astype(np.float32), -1, kernel, borderType=cv2.BORDER_CONSTANT)
        can_fill = target & (count > 0.0)
        if not bool(np.any(can_fill)):
            break
        for channel in range(3):
            summed = cv2.filter2D(
                (out[:, :, channel] * known).astype(np.float32),
                -1,
                kernel,
                borderType=cv2.BORDER_CONSTANT,
            )
            values = summed / np.maximum(count, 1e-6)
            out[:, :, channel][can_fill] = values[can_fill]
        known[can_fill] = True
    return out, known


def _halo_score_from_arrays(rgba: np.ndarray, reference_rgb: np.ndarray) -> tuple[float, int]:
    alpha = rgba[:, :, 3].astype(np.float32)
    edge = (alpha > 0.0) & (alpha < 245.0)
    edge_count = int(np.count_nonzero(edge))
    if edge_count <= 0:
        return 0.0, 0
    delta = np.linalg.norm(
        rgba[:, :, :3].astype(np.float32) - reference_rgb.astype(np.float32), axis=2
    ) / float(255.0 * np.sqrt(3.0))
    normalized_alpha = alpha / 255.0
    weights = np.maximum(normalized_alpha * (1.0 - normalized_alpha) * 4.0, 0.10)
    total_weight = float(np.sum(weights[edge]))
    score = float(np.sum(delta[edge] * weights[edge]) / max(total_weight, 1e-8))
    return max(0.0, min(1.0, score)), edge_count


def measure_edge_halo(image: Image.Image) -> dict[str, Any]:
    rgba = _as_rgba(image)
    reference_rgb, propagated = _propagate_interior_rgb(rgba)
    score, edge_count = _halo_score_from_arrays(rgba, reference_rgb)
    support = rgba[:, :, 3] > 0
    support_count = int(np.count_nonzero(support))
    return {
        "halo_score": round(score, 6),
        "edge_pixels": edge_count,
        "support_pixels": support_count,
        "propagated_fraction": round(float(np.count_nonzero(propagated & support)) / max(1, support_count), 6),
    }


def decontaminate_alpha_edges(image: Image.Image) -> tuple[Image.Image, dict[str, Any]]:
    rgba = _as_rgba(image)
    alpha_u8 = rgba[:, :, 3]
    reference_rgb, propagated = _propagate_interior_rgb(rgba)
    before, edge_count = _halo_score_from_arrays(rgba, reference_rgb)

    if cv2 is None or edge_count <= 0 or not bool(np.any(propagated)):
        return Image.fromarray(rgba, mode="RGBA"), {
            "edge_cleanup_applied": False,
            "edge_pixels": edge_count,
            "edge_halo_score_before": round(before, 6),
            "edge_halo_score_after": round(before, 6),
            "matte_quality": round(max(0.0, 1.0 - before / 0.18), 6),
            "transparent_padding_pixels": 0,
        }

    alpha = alpha_u8.astype(np.float32) / 255.0
    edge = (alpha_u8 > 0) & (alpha_u8 < 245) & propagated
    strength = np.clip((0.97 - alpha) / 0.72, 0.0, 1.0)
    strength = np.where(edge, strength, 0.0)
    source_rgb = rgba[:, :, :3].astype(np.float32)
    corrected = source_rgb * (1.0 - strength[:, :, None]) + reference_rgb * strength[:, :, None]
    rgba[:, :, :3] = np.clip(corrected, 0.0, 255.0).astype(np.uint8)

    transparent_padding = (alpha_u8 == 0) & propagated
    rgba[:, :, :3][transparent_padding] = np.clip(reference_rgb[transparent_padding], 0.0, 255.0).astype(np.uint8)
    rgba[:, :, :3][(alpha_u8 == 0) & ~propagated] = 0

    after_reference, _ = _propagate_interior_rgb(rgba)
    after, _ = _halo_score_from_arrays(rgba, after_reference)
    quality = max(0.0, min(1.0, 1.0 - after / 0.18))
    return Image.fromarray(rgba, mode="RGBA"), {
        "edge_cleanup_applied": bool(after + 1e-6 < before),
        "edge_pixels": edge_count,
        "edge_halo_score_before": round(before, 6),
        "edge_halo_score_after": round(after, 6),
        "matte_quality": round(quality, 6),
        "transparent_padding_pixels": int(np.count_nonzero(transparent_padding)),
    }


def finalize_cutout_matte(
    image: Image.Image,
    info: dict[str, Any],
    *,
    halo_review_threshold: float = DEFAULT_HALO_REVIEW_THRESHOLD,
) -> tuple[Image.Image, dict[str, Any]]:
    refined, alpha_metrics = refine_alpha_boundary(image)
    cleaned, rgb_metrics = decontaminate_alpha_edges(refined)
    updated = dict(info)
    warnings = list(updated.get("warnings", []))
    after = float(rgb_metrics.get("edge_halo_score_after", 0.0))
    if after > float(halo_review_threshold):
        if "cutout_edge_halo_excess" not in warnings:
            warnings.append("cutout_edge_halo_excess")
        updated["review_required"] = True
    updated["warnings"] = warnings
    updated.update(alpha_metrics)
    updated.update(rgb_metrics)
    updated["matte_quality_version"] = MATTE_QUALITY_VERSION
    return cleaned, updated
