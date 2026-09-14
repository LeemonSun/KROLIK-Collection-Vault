from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

from character_import import build_character_runtime_package
from rig_edit import RIG_EDIT_SCHEMA


def _fixture(path: Path) -> None:
    image = Image.new("RGB", (256, 512), (246, 246, 246))
    draw = ImageDraw.Draw(image)
    ink = (45, 48, 58)
    draw.ellipse((92, 28, 164, 100), fill=ink)
    draw.rectangle((116, 88, 140, 128), fill=ink)
    draw.rounded_rectangle((78, 112, 178, 300), radius=24, fill=ink)
    draw.ellipse((76, 266, 180, 330), fill=ink)
    draw.polygon([(82, 132), (54, 150), (40, 258), (64, 266), (92, 178)], fill=ink)
    draw.polygon([(174, 132), (202, 150), (216, 258), (192, 266), (164, 178)], fill=ink)
    draw.polygon([(92, 300), (122, 300), (116, 462), (82, 486), (72, 474), (88, 452)], fill=ink)
    draw.polygon([(134, 300), (164, 300), (168, 452), (184, 474), (174, 486), (140, 462)], fill=ink)
    image.save(path, "PNG")


def test_manual_joint_edit_flows_into_manifest_skin_and_collision(tmp_path: Path) -> None:
    source = tmp_path / "source.png"
    _fixture(source)
    project = tmp_path / "project"

    baseline = build_character_runtime_package(
        project, source, "baseline", prefer_ai_rig=False
    )
    edited = build_character_runtime_package(
        project,
        source,
        "edited",
        prefer_ai_rig=False,
        joint_overrides={"left_wrist": {"x": 0.16, "y": 0.49}},
    )

    assert edited["runtime_ready"] is True
    assert edited["joint_override_count"] == 1
    assert edited["joint_changed_count"] == 1
    assert edited["joint_changed"] == ["left_wrist"]
    assert edited["joint_max_delta"] > 0.0
    assert edited["rig_edit"] is not None

    edit_document = json.loads(Path(str(edited["rig_edit"])).read_text(encoding="utf-8"))
    assert edit_document["schema"] == RIG_EDIT_SCHEMA
    assert edit_document["joints"]["left_wrist"] == {"x": 0.16, "y": 0.49}
    assert edit_document["source_sha256"] == edited["source_sha256"]
    assert edit_document["cutout_sha256"] == edited["cutout_sha256"]

    baseline_manifest = json.loads(Path(str(baseline["manifest"])).read_text(encoding="utf-8"))
    edited_manifest = json.loads(Path(str(edited["manifest"])).read_text(encoding="utf-8"))
    assert baseline_manifest["rig"]["joints"]["left_wrist"] != {"x": 0.16, "y": 0.49}
    assert edited_manifest["rig"]["joints"]["left_wrist"] == {"x": 0.16, "y": 0.49}

    proxy = next(
        item for item in edited_manifest["physics"]["collision"]
        if item["a"] == "left_elbow" and item["b"] == "left_wrist"
    )
    assert proxy["p1"] == {"x": 0.16, "y": 0.49}

    baseline_weights = baseline_manifest["rig"]["skinning"]["bone_weights"]
    edited_weights = edited_manifest["rig"]["skinning"]["bone_weights"]
    assert baseline_weights != edited_weights
