from __future__ import annotations

"""Small objective metrics for the real DWPose production backend.

This module is intentionally independent of pycocotools.  The heavy A2 CI uses
OpenMMLab MMPose's tiny COCO test fixture (four public images plus keypoint
annotations) and scores DWPose body joints against the human annotations.
Errors are normalized by the annotated person's bbox diagonal so image canvas
size does not make a small person look artificially accurate.
"""

from dataclasses import dataclass
from math import hypot
from typing import Any


class DWPoseBenchmarkError(ValueError):
    pass


@dataclass(frozen=True)
class DWPoseBenchmarkSummary:
    samples: int
    joints: int
    mean_error: float
    median_error: float
    pck_05: float
    pck_10: float
    mean_pose_confidence: float

    def as_dict(self) -> dict[str, Any]:
        return {
            "samples": self.samples,
            "joints": self.joints,
            "mean_error": self.mean_error,
            "median_error": self.median_error,
            "pck_05": self.pck_05,
            "pck_10": self.pck_10,
            "mean_pose_confidence": self.mean_pose_confidence,
        }


def score_coco_body_joints(
    predicted_points: Any,
    coco_keypoints: list[float] | list[int],
    bbox_xywh: list[float] | list[int],
    *,
    visible_only: bool = False,
) -> list[float]:
    """Return bbox-diagonal-normalized errors for COCO's first 17 joints."""
    if len(coco_keypoints) < 17 * 3:
        raise DWPoseBenchmarkError("COCO annotation does not contain 17 keypoints")
    if len(bbox_xywh) != 4:
        raise DWPoseBenchmarkError("COCO bbox must be [x,y,w,h]")
    width = float(bbox_xywh[2])
    height = float(bbox_xywh[3])
    diagonal = hypot(width, height)
    if diagonal <= 1e-6:
        raise DWPoseBenchmarkError("COCO bbox has zero diagonal")

    try:
        point_count = len(predicted_points)
    except TypeError as exc:
        raise DWPoseBenchmarkError("predicted points must be indexable") from exc
    if point_count < 17:
        raise DWPoseBenchmarkError("DWPose prediction contains fewer than 17 body joints")

    errors: list[float] = []
    for index in range(17):
        gx = float(coco_keypoints[index * 3])
        gy = float(coco_keypoints[index * 3 + 1])
        visibility = int(coco_keypoints[index * 3 + 2])
        if visibility <= 0:
            continue
        if visible_only and visibility < 2:
            continue
        px = float(predicted_points[index][0])
        py = float(predicted_points[index][1])
        errors.append(hypot(px - gx, py - gy) / diagonal)
    if not errors:
        raise DWPoseBenchmarkError("sample has no scoreable COCO keypoints")
    return errors


def summarize_benchmark(
    per_sample_errors: list[list[float]],
    pose_confidences: list[float],
) -> DWPoseBenchmarkSummary:
    if not per_sample_errors:
        raise DWPoseBenchmarkError("benchmark has no successful samples")
    values = [value for sample in per_sample_errors for value in sample]
    if not values:
        raise DWPoseBenchmarkError("benchmark has no scored joints")
    ordered = sorted(values)
    count = len(ordered)
    middle = count // 2
    median = ordered[middle] if count % 2 else (ordered[middle - 1] + ordered[middle]) * .5
    mean_confidence = sum(pose_confidences) / max(1, len(pose_confidences))
    return DWPoseBenchmarkSummary(
        samples=len(per_sample_errors),
        joints=count,
        mean_error=round(sum(values) / count, 6),
        median_error=round(median, 6),
        pck_05=round(sum(value <= .05 for value in values) / count, 6),
        pck_10=round(sum(value <= .10 for value in values) / count, 6),
        mean_pose_confidence=round(mean_confidence, 6),
    )
