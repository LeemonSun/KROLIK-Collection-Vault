from __future__ import annotations

import numpy as np

from rig_tools import JOINT_ORDER, _dwpose_keypoints_to_rig


def test_dwpose_rig_persists_named_joint_confidence() -> None:
    points = np.zeros((17, 2), dtype=np.float32)
    coords = {
        0: (100, 30), 1: (94, 28), 2: (106, 28), 3: (88, 34), 4: (112, 34),
        5: (75, 90), 6: (125, 90), 7: (62, 145), 8: (138, 145),
        9: (55, 210), 10: (145, 210), 11: (82, 220), 12: (118, 220),
        13: (80, 310), 14: (120, 310), 15: (78, 390), 16: (122, 390),
    }
    for index, value in coords.items():
        points[index] = value
    scores = np.full((17,), 0.91, dtype=np.float32)
    scores[9] = 0.11
    rig = _dwpose_keypoints_to_rig(points, scores, 200, 420)
    assert rig is not None
    confidence = rig.settings["joint_confidence"]
    assert set(confidence) == set(JOINT_ORDER)
    assert confidence["left_wrist"] == 0.11
    assert confidence["right_wrist"] > 0.90
    assert "left_wrist" in rig.settings["low_confidence_joints"]
    assert "right_wrist" not in rig.settings["low_confidence_joints"]
