from __future__ import annotations

from pathlib import Path

from runtime_package import DEFAULT_POSE_CLIPS, DEFAULT_ANIMATION_GRAPH, build_manifest


def test_runtime_manifest_contains_data_driven_pose_clips():
    character = {"id": "P1", "name": "Test", "status": "Исходник найден"}
    image = {"id": 1, "width": 512, "height": 1024, "kind": "cutout"}
    joints = {
        "head": {"x": .5, "y": .1}, "neck": {"x": .5, "y": .2},
        "left_shoulder": {"x": .42, "y": .24}, "left_elbow": {"x": .35, "y": .4}, "left_wrist": {"x": .3, "y": .55},
        "right_shoulder": {"x": .58, "y": .24}, "right_elbow": {"x": .65, "y": .4}, "right_wrist": {"x": .7, "y": .55},
        "pelvis": {"x": .5, "y": .55},
        "left_hip": {"x": .46, "y": .56}, "left_knee": {"x": .45, "y": .74}, "left_ankle": {"x": .45, "y": .92},
        "right_hip": {"x": .54, "y": .56}, "right_knee": {"x": .55, "y": .74}, "right_ankle": {"x": .55, "y": .92},
    }
    rig = {"id": 1, "rest_json": {"joints": joints}, "settings_json": {}}
    manifest = build_manifest(character=character, image_version=image, rig=rig, mind=None)
    animation = manifest["animation"]
    assert animation["format_version"] == 1
    assert animation["state_graph"] == DEFAULT_ANIMATION_GRAPH
    assert set(DEFAULT_POSE_CLIPS).issubset(animation["clips"])
    assert len(animation["clips"]["walk"]["keyframes"]) >= 4
    assert any(frame.get("joints") for frame in animation["clips"]["walk"]["keyframes"])


def test_godot_animation_is_sampled_before_ik():
    root = Path(__file__).resolve().parents[1]
    driver = (root / "runtime_godot/scripts/animation_driver.gd").read_text(encoding="utf-8")
    agent = (root / "runtime_godot/scripts/character_agent.gd").read_text(encoding="utf-8")
    assert "joint_offsets" in driver
    assert "_sample_clip" in driver
    assert "_lerp_samples" in driver
    assert "animation_driver.configure" in agent
    assert "_apply_animation_pose(sample)" in agent
    assert "_solve_runtime_constraints(animated_joints)" in agent
