from __future__ import annotations

from pathlib import Path

from rig_tools import DEFAULT_BONES, RIG_FORMAT_VERSION
from runtime_package import SKIN_FORMAT_VERSION, build_skinning_mesh


JOINTS = {
    "head": {"x": .50, "y": .08}, "neck": {"x": .50, "y": .18},
    "left_shoulder": {"x": .40, "y": .22}, "left_elbow": {"x": .30, "y": .36}, "left_wrist": {"x": .22, "y": .52},
    "right_shoulder": {"x": .60, "y": .22}, "right_elbow": {"x": .70, "y": .36}, "right_wrist": {"x": .78, "y": .52},
    "pelvis": {"x": .50, "y": .53},
    "left_hip": {"x": .44, "y": .55}, "left_knee": {"x": .43, "y": .73}, "left_ankle": {"x": .43, "y": .91},
    "right_hip": {"x": .56, "y": .55}, "right_knee": {"x": .57, "y": .73}, "right_ankle": {"x": .57, "y": .91},
}


def test_skin_recipe_is_normalized_and_triangulated():
    skin = build_skinning_mesh(JOINTS, DEFAULT_BONES, cols=8, rows=12, influence_radius=.16)
    assert skin["format_version"] == SKIN_FORMAT_VERSION
    assert skin["backend"] == "godot_polygon2d_grid_v1"
    assert len(skin["vertices"]) == 8 * 12
    assert len(skin["triangles"]) == (8 - 1) * (12 - 1) * 6
    assert len(skin["bone_weights"]) == len(DEFAULT_BONES)

    count = len(skin["vertices"])
    sums = [0.0] * count
    for bone in skin["bone_weights"]:
        assert len(bone["weights"]) == count
        for i, weight in enumerate(bone["weights"]):
            assert 0.0 <= weight <= 1.0
            sums[i] += weight
    assert max(abs(total - 1.0) for total in sums) < 2e-5


def test_skin_weights_are_local_to_body_segments():
    skin = build_skinning_mesh(JOINTS, DEFAULT_BONES, cols=21, rows=21, influence_radius=.13)
    vertices = skin["vertices"]
    target_index = min(
        range(len(vertices)),
        key=lambda i: (vertices[i][0] - .23) ** 2 + (vertices[i][1] - .50) ** 2,
    )
    weights = {(b["a"], b["b"]): b["weights"][target_index] for b in skin["bone_weights"]}
    assert weights[("left_elbow", "left_wrist")] > weights[("right_elbow", "right_wrist")]
    assert weights[("left_elbow", "left_wrist")] > weights[("right_hip", "right_knee")]


def test_godot_runtime_uses_polygon2d_skeleton_skinning():
    root = Path(__file__).resolve().parents[1]
    skin_script = (root / "runtime_godot/scripts/skinned_character.gd").read_text(encoding="utf-8")
    agent_script = (root / "runtime_godot/scripts/character_agent.gd").read_text(encoding="utf-8")
    assert "Skeleton2D.new()" in skin_script
    assert "Polygon2D.new()" in skin_script
    assert "polygon.add_bone" in skin_script
    assert "apply_joint_pose" in skin_script
    assert "GPUDeformableCharacter" in agent_script
    assert "extends CharacterBody2D" in agent_script
    assert "NavigationAgent2D.new()" in agent_script
    assert "CollisionRig" in agent_script
    assert "draw_texture_rect(character_texture" not in agent_script


def test_rig_format_is_explicitly_versioned():
    assert RIG_FORMAT_VERSION >= 1


def test_godot_brain_mirrors_utility_model_contract():
    root = Path(__file__).resolve().parents[1]
    brain = (root / "runtime_godot/scripts/agent_brain.gd").read_text(encoding="utf-8")
    assert "func activity_scores" in brain
    assert '"return_home"' in brain
    assert '"interesting_targets"' in brain
    assert '"social_targets"' in brain
    assert "last_utility" in brain


def test_world_runtime_builds_navigation_region():
    root = Path(__file__).resolve().parents[1]
    world = (root / "runtime_godot/scripts/world_runtime.gd").read_text(encoding="utf-8")
    assert "NavigationRegion2D.new()" in world
    assert "NavigationPolygon.new()" in world
    assert "nav_poly.add_polygon" in world
