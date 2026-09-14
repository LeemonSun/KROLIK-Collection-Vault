from __future__ import annotations

import hashlib
import json
from pathlib import Path

from tools.build_core_vertical_slice import CHARACTER_ID, build_core_vertical_slice


def test_core_vertical_slice_builds_runtime_ready_package(tmp_path: Path) -> None:
    metrics = build_core_vertical_slice(tmp_path)
    assert metrics["character_id"] == CHARACTER_ID
    assert metrics["backend"] == "heuristic-silhouette"
    assert metrics["runtime_ready"] is True
    assert float(metrics["rig_score"]) == 100.0
    assert metrics["joints"] == 15
    assert metrics["bones"] == 14
    assert metrics["vertices"] > 0
    assert metrics["triangles"] > 0
    assert metrics["bone_weights"] == 14
    assert metrics["collision_proxies"] == 14

    manifest_path = Path(str(metrics["manifest"]))
    image_path = Path(str(metrics["image"]))
    assert manifest_path.is_file()
    assert image_path.is_file()

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert manifest["schema"] == "krolik.runtime-character/1"
    assert manifest["character"]["id"] == CHARACTER_ID
    assert manifest["quality"]["runtime_ready"] is True
    assert manifest["rig"]["skinning"]["backend"] == "godot_polygon2d_grid_v1"
    assert manifest["visual"]["sha256"] == hashlib.sha256(image_path.read_bytes()).hexdigest()
    assert manifest["animation"]["schema"] == "krolik.animation-library/1"
    assert manifest["mind"]["enabled"] is True
