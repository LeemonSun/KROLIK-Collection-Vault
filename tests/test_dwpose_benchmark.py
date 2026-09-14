from __future__ import annotations

import pytest

from dwpose_benchmark import DWPoseBenchmarkError, score_coco_body_joints, summarize_benchmark


def _coco_keypoints() -> list[float]:
    values: list[float] = []
    for index in range(17):
        values.extend([10.0 + index, 20.0 + index * 2.0, 2.0])
    return values


def test_coco_metric_is_normalized_by_person_bbox_diagonal() -> None:
    truth = _coco_keypoints()
    predicted = [[truth[i * 3], truth[i * 3 + 1]] for i in range(17)]
    predicted[5] = [predicted[5][0] + 3.0, predicted[5][1] + 4.0]
    errors = score_coco_body_joints(predicted, truth, [0.0, 0.0, 30.0, 40.0])
    assert len(errors) == 17
    assert errors[5] == pytest.approx(0.1)
    assert sum(errors) == pytest.approx(0.1)


def test_coco_metric_can_ignore_occluded_keypoints() -> None:
    truth = _coco_keypoints()
    truth[2] = 1.0
    predicted = [[truth[i * 3], truth[i * 3 + 1]] for i in range(17)]
    assert len(score_coco_body_joints(predicted, truth, [0, 0, 100, 100])) == 17
    assert len(score_coco_body_joints(predicted, truth, [0, 0, 100, 100], visible_only=True)) == 16


def test_benchmark_summary_reports_pck_and_confidence() -> None:
    summary = summarize_benchmark([[0.01, 0.06], [0.09, 0.20]], [0.5, 0.7])
    assert summary.samples == 2
    assert summary.joints == 4
    assert summary.mean_error == pytest.approx(0.09)
    assert summary.median_error == pytest.approx(0.075)
    assert summary.pck_05 == pytest.approx(0.25)
    assert summary.pck_10 == pytest.approx(0.75)
    assert summary.mean_pose_confidence == pytest.approx(0.6)


def test_coco_metric_rejects_empty_or_invalid_annotations() -> None:
    with pytest.raises(DWPoseBenchmarkError):
        score_coco_body_joints([], [], [0, 0, 10, 10])
    with pytest.raises(DWPoseBenchmarkError, match="zero diagonal"):
        score_coco_body_joints([[0, 0]] * 17, _coco_keypoints(), [0, 0, 0, 0])
