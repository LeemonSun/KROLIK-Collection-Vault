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


def test_godot_animation_face_secondary_motion_and_ik_pipeline_order():
    root = Path(__file__).resolve().parents[1]
    driver = (root / "runtime_godot/scripts/animation_driver.gd").read_text(encoding="utf-8")
    agent = (root / "runtime_godot/scripts/character_agent.gd").read_text(encoding="utf-8")
    face = (root / "runtime_godot/scripts/facial_state.gd").read_text(encoding="utf-8")

    assert "joint_offsets" in driver
    assert "_sample_clip" in driver
    assert "_lerp_samples" in driver
    assert "set_additive_layer" in driver
    assert "animation_driver.configure" in agent
    assert "procedural_blink" in face
    assert "look_at" in face
    assert '"eye_openness"' in face
    assert '"mouth_curve"' in face

    # Physics must sample the complete base + additive animation result before
    # handing the pose to CharacterAgent's post-animation pipeline.
    sample_call = "var sample := animation_driver.step(delta)"
    pose_call = "_apply_animation_pose(sample, delta)"
    assert sample_call in agent
    assert pose_call in agent
    assert agent.index(sample_call) < agent.index(pose_call)

    # C5/C4/C2 production ordering is strict: authored body pose first, then the
    # real head/neck part of the semantic facial layer, then inertial secondary
    # motion, with interaction IK last so explicit endpoints stay authoritative.
    pose_start = agent.index("func _apply_animation_pose(")
    pose_end = agent.index("\nfunc ", pose_start + 1)
    pose_body = agent[pose_start:pose_end]
    face_call = "_apply_facial_pose(facial_state.step(delta))"
    secondary_call = "_apply_secondary_motion(delta)"
    ik_call = "_solve_runtime_constraints(animated_joints)"
    assert face_call in pose_body
    assert secondary_call in pose_body
    assert ik_call in pose_body
    assert pose_body.index(face_call) < pose_body.index(secondary_call) < pose_body.index(ik_call)

    # Empty secondary configuration must remain a cheap disabled path rather
    # than stepping springs for every runtime character.
    secondary_start = agent.index("func _apply_secondary_motion(")
    secondary_end = agent.index("\nfunc ", secondary_start + 1)
    secondary_body = agent[secondary_start:secondary_end]
    assert "if not secondary_motion_enabled" in secondary_body
    assert "secondary_motion.step(delta, velocity)" in secondary_body

    # The current single-cutout rig must not pretend to have eyelid/mouth
    # deformation. Production applies only face-authored joint offsets to actual
    # joints and keeps the rest as semantic channels for future face geometry.
    facial_start = agent.index("func _apply_facial_pose(")
    facial_end = agent.index("\nfunc ", facial_start + 1)
    facial_body = agent[facial_start:facial_end]
    assert "facial_channels" in facial_body
    assert "joint_offsets" in facial_body
    assert "animated_joints" in facial_body
