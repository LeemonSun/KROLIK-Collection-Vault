from life_sim import (
    activity_scores,
    choose_state,
    long_term_utility_bias,
    normalize_emotion_state,
    memory_utility_bias,
    merged_needs,
    merged_profile,
    normalize_long_term_memory,
    normalize_short_term_memory,
    reinforce_relationship,
    remember_event,
    remember_place_visit,
    step_long_term_memory,
    step_emotion,
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


def test_step_mind_exposes_traits_memory_and_utility_without_breaking_existing_fields():
    memory = remember_event([], "interesting", subject="statue", valence=.7, importance=.8, ttl=120)
    result = step_mind(
        {"routine": "balanced", "traits": {"curiosity": .8}},
        None,
        1.0,
        {"interesting_targets": 1, "memory_subject": "statue"},
        memory,
    )
    assert result["state"] in {"idle", "wander", "inspect", "social", "return_home", "rest", "contained", "disabled"}
    assert result["animation"]
    assert result["affect"]["mood"]
    assert result["profile"]["traits"]["curiosity"] == .8
    assert len(result["memory"]) == 1
    assert result["memory"][0]["age"] == 1.0
    assert set(result["utility"]) == {"idle", "wander", "inspect", "social", "return_home", "rest"}

def test_long_term_relationship_learning_is_bounded_deduplicated_and_contextual():
    memory = {}
    for _ in range(6):
        memory = reinforce_relationship(memory, "alice", valence=1.0, importance=1.0)
    assert len(memory["relationships"]) == 1
    alice = memory["relationships"][0]
    assert alice["subject"] == "alice"
    assert .9 < alice["affinity"] <= 1.0
    assert .6 < alice["familiarity"] <= 1.0
    assert alice["interactions"] == 6

    profile = merged_profile({"autonomy": .2, "wander": .2, "social": .2, "routine": "balanced"})
    needs = merged_needs({"energy": .8, "comfort": .7, "curiosity": .25, "social": .25})
    context = {"interesting_targets": 1, "social_targets": 1}
    assert choose_state(profile, needs, context, None, memory) == "idle"
    focused = {**context, "social_subject": "alice"}
    assert choose_state(profile, needs, focused, None, memory) == "social"
    assert long_term_utility_bias(memory, focused)["social"] > 0.0


def test_long_term_memory_caps_relationships_and_places_deterministically():
    memory = {}
    for index in range(40):
        importance = .05 if index == 0 else .8
        memory = reinforce_relationship(memory, f"person-{index:02d}", valence=1.0, importance=importance)
    assert len(memory["relationships"]) == 32
    assert all(entry["subject"] != "person-00" for entry in memory["relationships"])

    for index in range(24):
        importance = .05 if index == 0 else .8
        memory = remember_place_visit(memory, f"place-{index:02d}", preference=1.0, importance=importance)
    assert len(memory["places"]) == 16
    assert all(entry["place"] != "place-00" for entry in memory["places"])
    assert memory["favorite_place"] in {entry["place"] for entry in memory["places"]}


def test_favorite_place_and_decay_survive_as_compact_semantic_memory():
    memory = {}
    for _ in range(6):
        memory = remember_place_visit(memory, "library", preference=1.0, importance=1.0)
    memory = remember_place_visit(memory, "cellar", preference=-1.0, importance=1.0)
    assert memory["favorite_place"] == "library"

    before = next(entry for entry in memory["places"] if entry["place"] == "library")
    aged = step_long_term_memory(memory, 3600.0)
    after = next(entry for entry in aged["places"] if entry["place"] == "library")
    assert after["hours_since_visit"] == 1.0
    assert 0.0 < after["preference"] < before["preference"]
    assert 0.0 < after["familiarity"] < before["familiarity"]
    assert aged["favorite_place"] == "library"

    normalized = normalize_long_term_memory({
        "relationships": [{"subject": "alice", "affinity": 9, "familiarity": -2}],
        "places": [{"place": "library", "preference": 9, "familiarity": 4}],
    })
    assert normalized["relationships"][0]["affinity"] == 1.0
    assert normalized["relationships"][0]["familiarity"] == 0.0
    assert normalized["places"][0]["preference"] == 1.0
    assert normalized["places"][0]["familiarity"] == 1.0


def test_long_term_place_preference_biases_target_and_favorite_home_return():
    memory = {}
    for _ in range(6):
        memory = remember_place_visit(memory, "library", preference=1.0, importance=1.0)
    profile = merged_profile({"autonomy": .2, "wander": .2, "social": .2})
    needs = merged_needs({"energy": .8, "comfort": .7, "curiosity": .25, "social": .25})
    target_context = {"interesting_targets": 1, "target_place": "library"}
    assert choose_state(profile, needs, target_context, None, memory) == "wander"
    bias = long_term_utility_bias(memory, {"away_from_home": True, "home_place": "library"})
    assert bias["return_home"] > 0.0


def test_step_mind_roundtrips_long_term_memory_without_breaking_legacy_calls():
    long_term = reinforce_relationship({}, "alice", valence=.8, importance=.9)
    long_term = remember_place_visit(long_term, "library", preference=.7, importance=.8)
    result = step_mind(
        {"autonomy": .2, "wander": .2, "social": .2},
        {"energy": .8, "comfort": .7, "curiosity": .25, "social": .25},
        60.0,
        {"interesting_targets": 1, "social_targets": 1, "social_subject": "alice", "current_place": "library"},
        [],
        long_term,
    )
    assert result["long_term_memory"]["relationships"][0]["subject"] == "alice"
    assert result["long_term_memory"]["places"][0]["place"] == "library"
    assert result["long_term_memory"]["relationships"][0]["hours_since_contact"] > 0.0
    legacy = step_mind(None, None, 1.0)
    assert legacy["long_term_memory"] == {"relationships": [], "places": [], "favorite_place": ""}



def test_constraint_emotions_depend_on_personality_and_constraint_profile():
    needs = merged_needs({"energy": .8, "comfort": .7, "curiosity": .4, "social": .4})
    context = {
        "bound": True,
        "interaction_mode": "restrained",
        "constraint_kind": "shackles",
        "constraint_severity": .95,
        "constraint_novelty": .8,
        "threat": .72,
        "witnesses": 3,
    }
    timid = merged_profile({"traits": {"boldness": .05, "resilience": .1, "patience": .4}})
    defiant = merged_profile({"traits": {"boldness": .95, "resilience": .95, "patience": .2}})
    timid_affect = step_emotion(timid, needs, "contained", context, None, 1.0)
    defiant_affect = step_emotion(defiant, needs, "contained", context, None, 1.0)
    assert timid_affect["fear"] > defiant_affect["fear"]
    assert defiant_affect["anger"] > timid_affect["anger"]
    assert timid_affect["mood"] in {"terrified", "afraid", "frustrated", "ashamed"}
    assert defiant_affect["mood"] in {"furious", "angry", "frustrated", "afraid"}


def test_constraint_profiles_have_distinct_emotional_load_and_release_creates_relief():
    profile = merged_profile({"traits": {"boldness": .5, "resilience": .5, "patience": .5}})
    needs = merged_needs(None)
    stool = step_emotion(profile, needs, "contained", {
        "bound": True, "constraint_kind": "restraint_stool", "constraint_severity": .7,
    }, None, 1.0)
    stocks = step_emotion(profile, needs, "contained", {
        "bound": True, "constraint_kind": "stocks", "constraint_severity": .9, "witnesses": 4,
    }, None, 1.0)
    assert stocks["frustration"] > stool["frustration"]
    assert stocks["shame"] > stool["shame"]
    released = step_emotion(profile, needs, "idle", {"released": True, "safe": True}, stocks, 0.5)
    assert released["relief"] > .3
    assert released["valence"] > stocks["valence"]


def test_social_outcomes_feed_joy_trust_anger_and_persist_through_step_mind_affect():
    profile = merged_profile({"traits": {"sociability": .9, "boldness": .6}})
    needs = merged_needs({"social": .8})
    positive = step_emotion(profile, needs, "social", {
        "social_success": .9, "social_affinity": .8, "social_familiarity": .8,
    }, None, 1.0)
    negative = step_emotion(profile, needs, "social", {
        "social_success": -.9, "social_affinity": -.7, "social_familiarity": .5,
    }, None, 1.0)
    assert positive["joy"] > negative["joy"]
    assert positive["trust"] > negative["trust"]
    assert negative["anger"] > positive["anger"]
    result = step_mind(profile, needs, 1.0, {"social_targets": 1, "social_success": .9}, [], {}, positive)
    assert set(normalize_emotion_state(result["affect"])) >= {"fear", "anger", "joy", "trust", "mood"}
    assert result["affect"]["facial_mood"]
