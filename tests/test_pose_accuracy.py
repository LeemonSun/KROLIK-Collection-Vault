from __future__ import annotations

import pytest

from pose_accuracy import PoseAccuracyError, score_joint_sets, summarize_errors


def _point(x: float, y: float) -> dict[str, float]:
    return {"x": x, "y": y}


def test_joint_scoring_uses_normalized_euclidean_error() -> None:
    expected = {
        "head": _point(0.50, 0.10),
        "neck": _point(0.50, 0.20),
    }
    predicted = {
        "head": _point(0.53, 0.14),  # exactly 0.05
        "neck": _point(0.50, 0.20),
    }
    errors = score_joint_sets(predicted, expected, visible=["head", "neck"])
    assert errors == pytest.approx([0.05, 0.0])


def test_summary_reports_mean_median_and_pck() -> None:
    summary = summarize_errors(
        [[0.0, 0.05, 0.06], [0.10, 0.20]],
        ["dwpose-onnx", "dwpose-onnx"],
    )
    assert summary.samples == 2
    assert summary.joints == 5
    assert summary.mean_error == pytest.approx(0.082)
    assert summary.median_error == pytest.approx(0.06)
    assert summary.pck_05 == pytest.approx(0.4)
    assert summary.pck_10 == pytest.approx(0.8)
    assert summary.backend_counts == {"dwpose-onnx": 2}


def test_scoring_rejects_unknown_or_missing_visible_joints() -> None:
    with pytest.raises(PoseAccuracyError, match="unknown KROLIK joint"):
        score_joint_sets({"head": _point(0.5, 0.1)}, {"head": _point(0.5, 0.1)}, visible=["tail"])

    with pytest.raises(PoseAccuracyError, match="predicted rig missing"):
        score_joint_sets({}, {"head": _point(0.5, 0.1)}, visible=["head"])


def test_scoring_rejects_non_normalized_ground_truth() -> None:
    with pytest.raises(PoseAccuracyError, match="normalized"):
        score_joint_sets(
            {"head": _point(0.5, 0.1)},
            {"head": _point(1.5, 0.1)},
            visible=["head"],
        )
