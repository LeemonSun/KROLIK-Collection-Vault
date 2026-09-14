from __future__ import annotations

from copy import deepcopy
import json

import pytest

from animation_content import default_animation_document, validate_animation_document
from pose_content import (
    POSE_FORMAT_VERSION,
    POSE_SCHEMA,
    PoseCatalog,
    PoseContentError,
    load_pose_library,
    mirror_pose,
    save_pose_library,
    upsert_pose,
    validate_pose_document,
)


REST = {
    "head": {"x": 0.50, "y": 0.10},
    "neck": {"x": 0.50, "y": 0.20},
    "left_shoulder": {"x": 0.40, "y": 0.24},
    "left_elbow": {"x": 0.34, "y": 0.40},
    "left_wrist": {"x": 0.30, "y": 0.55},
    "right_shoulder": {"x": 0.60, "y": 0.24},
    "right_elbow": {"x": 0.66, "y": 0.40},
    "right_wrist": {"x": 0.70, "y": 0.55},
    "pelvis": {"x": 0.50, "y": 0.55},
    "left_hip": {"x": 0.46, "y": 0.56},
    "left_knee": {"x": 0.45, "y": 0.74},
    "left_ankle": {"x": 0.45, "y": 0.92},
    "right_hip": {"x": 0.54, "y": 0.56},
    "right_knee": {"x": 0.55, "y": 0.74},
    "right_ankle": {"x": 0.55, "y": 0.92},
}


def _custom_document() -> dict:
    return {
        "schema": POSE_SCHEMA,
        "format_version": POSE_FORMAT_VERSION,
        "poses": {
            "custom_wave": {
                "category": "gesture",
                "tags": ["custom", "arm"],
                "mode": "offset",
                "mirrorable": True,
                "duration_hint": 1.25,
                "joints": {
                    "left_elbow": [0.03, -0.03],
                    "left_wrist": [0.08, -0.10],
                },
                "root": {"rotation": -0.01},
            }
        },
    }


def test_bundled_pose_library_is_valid_and_filterable():
    catalog = PoseCatalog()
    assert catalog.revision == 1
    assert {"neutral", "attentive", "relaxed", "inspect_left", "lean_left", "step_ready_left", "arms_close", "rest_low"}.issubset(catalog.names())
    assert "inspect_left" in catalog.names(tag="inspect")
    assert "rest_low" in catalog.names(category="rest")
    assert validate_pose_document(catalog.document) == []


def test_pose_application_is_non_destructive_and_strength_blended():
    catalog = PoseCatalog()
    before = deepcopy(REST)
    full = catalog.apply("attentive", REST)
    half = catalog.apply("attentive", REST, strength=0.5)
    assert REST == before
    assert full["head"]["y"] == pytest.approx(0.092)
    assert half["head"]["y"] == pytest.approx(0.096)
    assert full["left_ankle"] == REST["left_ankle"]


def test_semantic_mirroring_swaps_sides_and_inverts_horizontal_offsets():
    source = {
        "mode": "offset",
        "mirrorable": True,
        "joints": {"left_wrist": [0.08, -0.10], "head": [-0.02, 0.01]},
        "root": {"x": 2.0, "rotation": -0.2},
    }
    mirrored = mirror_pose(source)
    assert "right_wrist" in mirrored["joints"]
    assert mirrored["joints"]["right_wrist"] == pytest.approx([-0.08, -0.10])
    assert mirrored["joints"]["head"] == pytest.approx([0.02, 0.01])
    assert mirrored["root"]["x"] == pytest.approx(-2.0)
    assert mirrored["root"]["rotation"] == pytest.approx(0.2)


def test_pose_converts_into_existing_animation_v1_contract():
    catalog = PoseCatalog()
    animation = default_animation_document()
    merged = catalog.add_to_animation(
        animation,
        "inspect_left",
        clip_name="author_inspect_pose",
        state_name="author_pose_preview",
        duration=1.5,
        loop=True,
        blend=0.12,
    )
    assert validate_animation_document(merged) == []
    assert "author_inspect_pose" not in animation["clips"]
    clip = merged["clips"]["author_inspect_pose"]
    assert clip["duration"] == pytest.approx(1.5)
    assert len(clip["keyframes"]) == 2
    assert clip["keyframes"][0]["joints"] == clip["keyframes"][1]["joints"]
    assert merged["state_graph"]["author_pose_preview"]["clip"] == "author_inspect_pose"


def test_custom_pose_file_can_drive_preview_and_runtime_clip_without_code_change(tmp_path):
    path = tmp_path / "poses.json"
    path.write_text(json.dumps(_custom_document()), encoding="utf-8")
    catalog = PoseCatalog(path)
    preview = catalog.apply("custom_wave", REST)
    assert preview["left_wrist"] == pytest.approx({"x": 0.38, "y": 0.45})

    animation = catalog.add_to_animation(
        default_animation_document(),
        "custom_wave",
        state_name="custom_wave_state",
    )
    assert validate_animation_document(animation) == []
    assert animation["state_graph"]["custom_wave_state"]["clip"] == "pose_custom_wave"


def test_pose_authoring_upsert_and_atomic_save_preserve_previous_file(tmp_path):
    path = tmp_path / "poses.json"
    base = _custom_document()
    first = save_pose_library(path, base)
    assert first.pose_count == 1
    assert first.backup_path is None

    new_pose = {
        "category": "gesture",
        "tags": ["authored"],
        "mode": "offset",
        "mirrorable": True,
        "duration_hint": 1.0,
        "joints": {"right_wrist": [-0.04, -0.02]},
        "root": {},
    }
    updated = upsert_pose(base, "authored_pose", new_pose)
    second = save_pose_library(path, updated)
    assert second.pose_count == 2
    assert second.backup_path is not None
    backup = json.loads((tmp_path / "poses.json.bak").read_text(encoding="utf-8"))
    assert set(backup["poses"]) == {"custom_wave"}
    assert set(load_pose_library(path).document["poses"]) == {"custom_wave", "authored_pose"}

    invalid = deepcopy(updated)
    invalid["poses"]["authored_pose"]["joints"]["right_wrist"] = [float("nan"), 0.0]
    before = path.read_text(encoding="utf-8")
    with pytest.raises(PoseContentError):
        save_pose_library(path, invalid)
    assert path.read_text(encoding="utf-8") == before
