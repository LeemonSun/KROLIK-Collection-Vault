from __future__ import annotations

import numpy as np
import pytest

from tools.inspect_dwpose_model import DWPoseContractError, validate_session_contract


class _Info:
    def __init__(self, name: str, shape: list[int]):
        self.name = name
        self.shape = shape


class _FakeSession:
    def __init__(self, *, input_shape=None, x_shape=None, y_shape=None):
        self.input_shape = input_shape or [1, 3, 384, 288]
        self.x_shape = x_shape or [1, 133, 576]
        self.y_shape = y_shape or [1, 133, 768]

    def get_inputs(self):
        return [_Info("input", self.input_shape)]

    def get_outputs(self):
        return [_Info("simcc_x", self.x_shape), _Info("simcc_y", self.y_shape)]

    def get_providers(self):
        return ["CPUExecutionProvider"]

    def run(self, _outputs, feeds):
        assert list(feeds.values())[0].shape == tuple(self.input_shape)
        return [np.zeros(self.x_shape, np.float32), np.zeros(self.y_shape, np.float32)]


def test_accepts_expected_dwpose_wholebody_simcc_contract() -> None:
    report = validate_session_contract(_FakeSession())
    assert report["input_shape"] == [1, 3, 384, 288]
    assert report["output_x_shape"] == [1, 133, 576]
    assert report["output_y_shape"] == [1, 133, 768]
    assert report["keypoints"] == 133
    assert report["simcc_split_ratio"] == 2.0


def test_rejects_model_that_would_break_hardcoded_split_ratio() -> None:
    with pytest.raises(DWPoseContractError, match="split-ratio"):
        validate_session_contract(_FakeSession(x_shape=[1, 133, 288], y_shape=[1, 133, 384]))


def test_rejects_too_few_keypoints() -> None:
    with pytest.raises(DWPoseContractError, match="keypoint"):
        validate_session_contract(_FakeSession(x_shape=[1, 10, 576], y_shape=[1, 10, 768]))


def test_rejects_wrong_input_layout() -> None:
    with pytest.raises(DWPoseContractError, match="\[1,3,H,W\]"):
        validate_session_contract(_FakeSession(input_shape=[1, 384, 288, 3]))
