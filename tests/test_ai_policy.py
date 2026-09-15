from __future__ import annotations

from copy import deepcopy

from ai_policy import CONTENT_POLICY_PATH, RUNTIME_POLICY_PATH, generated_policy_document, read_policy, validate_ai_policy_document
from life_sim import activity_scores, choose_state, merged_needs, merged_profile, policy_document


def test_generated_ai_policy_is_valid_and_fresh():
    first = generated_policy_document()
    second = generated_policy_document()
    assert validate_ai_policy_document(first) == []
    assert first == policy_document()
    first["defaults"]["needs"]["energy"] = 0.0
    assert second["defaults"]["needs"]["energy"] == 0.82


def test_committed_content_and_runtime_policy_match_life_sim_source():
    expected = generated_policy_document()
    assert read_policy(CONTENT_POLICY_PATH) == expected
    assert read_policy(RUNTIME_POLICY_PATH) == expected


def test_policy_validation_rejects_drift_prone_structural_damage():
    broken = deepcopy(generated_policy_document())
    broken["state_order"] = ["idle", "idle"]
    broken["utility"]["wander"]["wander"] = float("inf")
    broken["short_term_memory"]["capacity"] = 0
    broken["short_term_memory"]["max_ttl"] = 1
    broken["short_term_memory"]["effects"]["social"] = {"bogus": .5}
    broken["long_term_memory"]["relationship_capacity"] = 0
    broken["long_term_memory"]["target_place_effects"] = {"bogus": .5}
    errors = validate_ai_policy_document(broken)
    assert any("state_order" in item for item in errors)
    assert any("utility.wander" in item for item in errors)
    assert any("short_term_memory.capacity" in item for item in errors)
    assert any("max_ttl" in item for item in errors)
    assert any("short_term_memory.effects.social" in item for item in errors)
    assert any("long_term_memory.relationship_capacity" in item for item in errors)
    assert any("long_term_memory.target_place_effects" in item for item in errors)


def test_python_behavior_still_uses_policy_values():
    needs = merged_needs({"energy": 0.8, "comfort": 0.7, "curiosity": 0.7, "social": 0.8})
    social = merged_profile({"routine": "social", "social": 0.9, "wander": 0.2})
    assert choose_state(social, needs, {"social_targets": 2}) == "social"
    explorer = merged_profile({"routine": "explorer", "wander": 0.9})
    assert activity_scores(explorer, needs, {"interesting_targets": 2})["inspect"] > 0.5
