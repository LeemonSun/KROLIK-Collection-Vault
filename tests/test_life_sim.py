from life_sim import activity_scores, choose_state, merged_needs, merged_profile, step_mind


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


def test_step_mind_exposes_traits_and_utility_without_breaking_existing_fields():
    result = step_mind({"routine": "balanced", "traits": {"curiosity": .8}}, None, 1.0, {"interesting_targets": 1})
    assert result["state"] in {"idle", "wander", "inspect", "social", "return_home", "rest", "contained", "disabled"}
    assert result["animation"]
    assert result["affect"]["mood"]
    assert result["profile"]["traits"]["curiosity"] == .8
    assert set(result["utility"]) == {"idle", "wander", "inspect", "social", "return_home", "rest"}
