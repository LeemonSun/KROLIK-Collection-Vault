from __future__ import annotations

import numpy as np

from rig_tools import _dwpose_keypoints_to_rig, capabilities


def test_dwpose_mapping_builds_portable_krolik_rig():
    points = np.zeros((133, 2), dtype=np.float32)
    scores = np.ones(133, dtype=np.float32) * .9
    coords = {
        0:(100,35), 3:(85,42), 4:(115,42),
        5:(80,100), 6:(120,100), 7:(65,160), 8:(135,160), 9:(55,220), 10:(145,220),
        11:(88,230), 12:(112,230), 13:(86,330), 14:(114,330), 15:(85,440), 16:(115,440),
    }
    for i, xy in coords.items():
        points[i] = xy
    rig = _dwpose_keypoints_to_rig(points, scores, 200, 500)
    assert rig is not None
    assert rig.settings["backend"] == "dwpose-onnx"
    assert set(["head", "neck", "pelvis", "left_wrist", "right_ankle"]).issubset(rig.joints)
    assert rig.joints["left_shoulder"]["x"] < rig.joints["right_shoulder"]["x"]
    assert 0.0 <= rig.joints["left_ankle"]["y"] <= 1.0


def test_capabilities_reports_dwpose_without_implicit_download():
    caps = capabilities()
    assert "dwpose" in caps
    assert "dwpose_model" in caps
    assert "onnxruntime" in caps
