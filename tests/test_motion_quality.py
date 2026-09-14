from __future__ import annotations

from copy import deepcopy

from animation_content import default_animation_document, validate_animation_document
from motion_quality import FAMILY_RULES, MIN_TOTAL_CLIPS, audit_motion_library


def test_default_motion_library_meets_phase_c_coverage_and_quality():
    document = default_animation_document()
    report = audit_motion_library(document)
    assert report.ok, report.errors
    assert report.clip_count >= MIN_TOTAL_CLIPS
    assert report.dynamic_clip_count >= report.clip_count - 1
    assert report.loop_closed_count == report.loop_clip_count
    for family, rule in FAMILY_RULES.items():
        assert report.family_counts[family] >= rule["minimum"]


def test_motion_library_contains_idle_locomotion_gesture_reaction_environment_families():
    clips = default_animation_document()["clips"]
    expected = {
        "idle_shift_left", "idle_shift_right", "idle_look_left", "idle_look_right", "idle_alert", "idle_tired",
        "walk_slow", "walk_brisk", "turn_left", "turn_right", "step_back", "sidestep_left", "sidestep_right",
        "gesture_nod", "gesture_shake_head", "gesture_acknowledge", "gesture_point_left", "gesture_point_right", "gesture_wave_left", "gesture_wave_right",
        "reaction_startle", "reaction_recoil", "reaction_recover",
        "environment_wall_idle", "environment_seated_idle", "environment_cage_idle",
    }
    assert expected.issubset(clips)


def test_all_added_motion_clips_remain_animation_v1_compatible():
    document = default_animation_document()
    assert document["format_version"] == 1
    assert validate_animation_document(document) == []
    assert document["state_graph"]["alert"]["clip"] == "idle_alert"
    assert document["state_graph"]["recover"]["clip"] == "reaction_recover"


def test_quality_audit_rejects_static_fake_motion_and_open_loop():
    document = default_animation_document()
    broken = deepcopy(document)
    broken["clips"]["gesture_fake_static"] = {
        "duration": 1.0,
        "loop": False,
        "keyframes": [
            {"t": 0.0, "joints": {}, "root": {}},
            {"t": 1.0, "joints": {}, "root": {}},
        ],
    }
    broken["clips"]["idle_open_loop"] = {
        "duration": 1.0,
        "loop": True,
        "keyframes": [
            {"t": 0.0, "joints": {}, "root": {}},
            {"t": 1.0, "joints": {"head": [0.02, 0.0]}, "root": {}},
        ],
    }
    report = audit_motion_library(broken)
    assert not report.ok
    assert any("gesture_fake_static" in error and "static" in error for error in report.errors)
    assert any("idle_open_loop" in error and "does not close" in error for error in report.errors)


def test_quality_audit_rejects_extreme_offsets_even_when_schema_is_parseable():
    document = default_animation_document()
    broken = deepcopy(document)
    broken["clips"]["gesture_nod"]["keyframes"][1]["joints"]["head"] = [0.75, 0.0]
    assert validate_animation_document(broken) == []
    report = audit_motion_library(broken)
    assert not report.ok
    assert any("quality offset bound" in error for error in report.errors)
