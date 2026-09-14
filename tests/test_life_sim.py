from affinity import learn_affinity
from life_sim import (
    AI_POLICY,
    activity_scores,
    choose_state,
    memory_utility_bias,
    merged_needs,
    merged_profile,
    normalize_short_term_memory,
    remember_event,
    step_memory,
    step_mind,
)


def test_profile_routine_is_validated_and_preserved():
    assert merged_profile({"routine": "explorer"})["routine"] == "explorer"
    assert merged_profile({"routine": "bogus"})["routine"] == "balanced"


def test_hard_mobility_and_return_home_gates_precede_utility():
    p = merged_profile(None)
    n = merged_needs(None)
    assert choose_state({**p, "mobility": "disabled"}, n) == "disabled"
    assert choose_state(p, n, {"bound": True}) == "contained"
    low = {**n, "energy": 0.1}
    assert choose_state(p, low, {"away_from_home": True}) == "return_home"
    assert choose_state(p, low) == "rest"


def test_utility_context_and_routine_change_decisions():
    n = merged_needs({"energy": .8, "comfort": .7, "curiosity": .7, "social": .8})
    social = merged_profile({"routine": "social", "social": .9, "wander": .2})
    assert choose_state(social, n, {"social_targets": 2}) == "social"
    explorer = merged_profile({"routine": "explorer", "wander": .9})
    scores = activity_scores(explorer, n, {"interesting_targets": 2})
    assert scores["inspect"] > .5


def test_legacy_profile_gets_neutral_traits_and_explicit_neutral_is_identical():
    base = {"autonomy": .6, "wander": .5, "social": .5, "routine": "balanced"}
    implicit = merged_profile(base)
    explicit = merged_profile({**base, "traits": {
        "curiosity": .5, "sociability": .5, "boldness": .5, "patience": .5, "resilience": .5,
    }})
    assert implicit == explicit
    assert set(implicit["traits"].values()) == {.5}


def test_traits_are_bounded_and_unknown_traits_are_ignored():
    profile = merged_profile({"traits": {"curiosity": 9, "sociability": -2, "unknown": 1}})
    assert profile["traits"]["curiosity"] == 1.0
    assert profile["traits"]["sociability"] == 0.0
    assert "unknown" not in profile["traits"]
    assert profile["traits"]["boldness"] == .5


def test_same_needs_and_context_produce_distinct_personality_decisions():
    needs = merged_needs({"energy": .8, "comfort": .7, "curiosity": .55, "social": .55})
    context = {"interesting_targets": 1, "social_targets": 1}
    base = {"autonomy": .6, "wander": .5, "social": .5, "routine": "balanced"}
    curious = merged_profile({**base, "traits": {"curiosity": 1.0}})
    sociable = merged_profile({**base, "traits": {"sociability": 1.0}})
    bold = merged_profile({**base, "traits": {"boldness": 1.0}})
    patient = merged_profile({**base, "traits": {"patience": 1.0}})
    assert choose_state(curious, needs, context) == "inspect"
    assert choose_state(sociable, needs, context) == "social"
    assert choose_state(bold, needs, context) == "wander"
    assert choose_state(patient, needs, context) == "idle"


def test_empty_memory_preserves_legacy_decision_and_utility_exactly():
    profile = merged_profile({"autonomy": .6, "wander": .5, "social": .5})
    needs = merged_needs({"energy": .8, "comfort": .7, "curiosity": .55, "social": .55})
    context = {"interesting_targets": 1, "social_targets": 1}
    assert memory_utility_bias([], context) == {
        "return_home": 0.0, "rest": 0.0, "social": 0.0,
        "inspect": 0.0, "wander": 0.0, "idle": 0.0,
    }
    assert activity_scores(profile, needs, context) == activity_scores(profile, needs, context, [])
    assert choose_state(profile, needs, context) == choose_state(profile, needs, context, [])


def test_memory_deduplicates_is_bounded_and_evicts_weakest_deterministically():
    memory = remember_event([], "social", subject="alice", valence=.2, importance=.2, ttl=120)
    memory = remember_event(memory, "social", subject="alice", valence=.9, importance=.9, ttl=120)
    assert len(memory) == 1
    assert memory[0]["valence"] == .9
    assert memory[0]["importance"] == .9
    memory = remember_event([], "interesting", subject="weak", valence=1, importance=.01, ttl=120)
    for index in range(8):
        memory = remember_event(memory, "interesting", subject=f"strong-{index}", valence=1, importance=.8, ttl=120)
    assert len(memory) == 8
    assert all(entry["subject"] != "weak" for entry in memory)
    assert {entry["subject"] for entry in memory} == {f"strong-{index}" for index in range(8)}


def test_memory_ttl_ages_and_expires_without_growth():
    memory = remember_event([], "home", subject="room-a", valence=1, importance=1, ttl=10)
    halfway = step_memory(memory, 5)
    assert len(halfway) == 1
    assert halfway[0]["age"] == 5
    assert step_memory(halfway, 5) == []
    assert normalize_short_term_memory([{"kind": "bogus", "subject": "x"}]) == []


def test_focused_memory_can_shift_borderline_choice_while_unfocused_stays_legacy():
    profile = merged_profile({"autonomy": .2, "wander": .2, "social": .2, "routine": "balanced"})
    needs = merged_needs({"energy": .8, "comfort": .7, "curiosity": .25, "social": .25})
    context = {"interesting_targets": 1, "social_targets": 1}
    memory = remember_event([], "social", subject="alice", valence=1, importance=1, ttl=180)
    assert choose_state(profile, needs, context) == "idle"
    assert choose_state(profile, needs, context, memory) == "idle"
    focused = {**context, "memory_subject": "alice"}
    assert choose_state(profile, needs, focused, memory) == "social"
    assert memory_utility_bias(memory, focused)["social"] > memory_utility_bias(memory, context)["social"]


def test_memory_never_overrides_hard_contained_or_exhaustion_gates():
    profile = merged_profile(None)
    needs = merged_needs({"energy": .1})
    memory = remember_event([], "interesting", subject="door", valence=1, importance=1, ttl=180)
    assert choose_state(profile, needs, {"bound": True, "interesting_targets": 9, "memory_subject": "door"}, memory) == "contained"
    assert choose_state(profile, needs, {"interesting_targets": 9, "memory_subject": "door"}, memory) == "rest"


def test_empty_affinity_is_legacy_neutral_and_matching_friend_can_shift_social_choice():
    profile = merged_profile({"autonomy": .2, "wander": .2, "social": .2, "routine": "balanced"})
    needs = merged_needs({"energy": .8, "comfort": .7, "curiosity": .25, "social": .25})
    context = {"interesting_targets": 1, "social_targets": 1, "social_subject": "alice"}
    baseline = choose_state(profile, needs, context, [], [])
    assert baseline == "idle"
    affinity = []
    for _ in range(10):
        affinity = learn_affinity(affinity, "character", "alice", 1.0, AI_POLICY["long_term_affinity"])
    assert choose_state(profile, needs, context, [], affinity) == "social"
    assert choose_state(profile, needs, {**context, "social_subject": "bob"}, [], affinity) == baseline


def test_affinity_does_not_override_hard_gates():
    profile = merged_profile(None)
    needs = merged_needs({"energy": .1})
    affinity = [{"kind": "character", "subject": "alice", "affinity": 1, "familiarity": 1}]
    assert choose_state(profile, needs, {"bound": True, "social_targets": 9, "social_subject": "alice"}, [], affinity) == "contained"
    assert choose_state(profile, needs, {"social_targets": 9, "social_subject": "alice"}, [], affinity) == "rest"


def test_step_mind_exposes_traits_memory_affinity_favorite_place_and_utility():
    memory = remember_event([], "interesting", subject="statue", valence=.7, importance=.8, ttl=120)
    affinity = [
        {"kind": "place", "subject": "garden", "affinity": .8, "familiarity": .9},
        {"kind": "character", "subject": "alice", "affinity": .6, "familiarity": .7},
    ]
    result = step_mind(
        {"routine": "balanced", "traits": {"curiosity": .8}},
        None,
        1.0,
        {"interesting_targets": 1, "memory_subject": "statue", "place_subject": "garden"},
        memory,
        affinity,
    )
    assert result["state"] in {"idle", "wander", "inspect", "social", "return_home", "rest", "contained", "disabled"}
    assert result["animation"]
    assert result["affect"]["mood"]
    assert result["profile"]["traits"]["curiosity"] == .8
    assert len(result["memory"]) == 1
    assert result["memory"][0]["age"] == 1.0
    assert len(result["affinity"]) == 2
    assert result["favorite_place"] == "garden"
    assert set(result["utility"]) == {"idle", "wander", "inspect", "social", "return_home", "rest"}
