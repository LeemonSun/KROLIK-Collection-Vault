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


def test_step_mind_exposes_utility_without_breaking_existing_snapshot_fields():
    result = step_mind({"routine": "balanced"}, None, 1.0, {"interesting_targets": 1})
    assert result["state"] in {"idle", "wander", "inspect", "social", "return_home", "rest", "contained", "disabled"}
    assert result["animation"]
    assert result["affect"]["mood"]
    assert set(result["utility"]) == {"idle", "wander", "inspect", "social", "return_home", "rest"}
