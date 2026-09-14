from __future__ import annotations

from affinity import (
    DEFAULT_LONG_TERM_AFFINITY_POLICY,
    affinity_lookup,
    affinity_utility_bias,
    decay_affinities,
    favorite_place,
    learn_affinity,
    normalize_affinity_records,
)


def cfg():
    return dict(DEFAULT_LONG_TERM_AFFINITY_POLICY)


def test_normalize_clamps_dedupes_and_ignores_invalid_records():
    records = normalize_affinity_records([
        {"kind": "character", "subject": "alice", "affinity": 2, "familiarity": -.2},
        {"kind": "character", "subject": "alice", "affinity": -.4, "familiarity": .9},
        {"kind": "place", "subject": "tower", "affinity": .6, "familiarity": .4},
        {"kind": "bogus", "subject": "x", "affinity": 1, "familiarity": 1},
        {"kind": "place", "subject": "", "affinity": 1, "familiarity": 1},
    ], cfg())
    assert len(records) == 2
    lookup = affinity_lookup(records, cfg())
    assert lookup["character"]["alice"] == {
        "kind": "character", "subject": "alice", "affinity": -.4, "familiarity": .9,
    }
    assert lookup["place"]["tower"]["affinity"] == .6


def test_learning_is_bounded_incremental_and_event_driven():
    records = []
    for _ in range(20):
        records = learn_affinity(records, "character", "alice", 1.0, cfg())
    alice = affinity_lookup(records, cfg())["character"]["alice"]
    assert alice["affinity"] == 1.0
    assert alice["familiarity"] == 1.0
    records = learn_affinity(records, "character", "alice", -1.0, cfg())
    alice = affinity_lookup(records, cfg())["character"]["alice"]
    assert alice["affinity"] == .8
    assert alice["familiarity"] == 1.0


def test_character_and_place_capacities_evict_weakest_independently():
    config = cfg()
    config["character_capacity"] = 3
    config["place_capacity"] = 2
    records = []
    for name, signal in [("weak", .1), ("a", 1), ("b", .9), ("c", .8)]:
        records = learn_affinity(records, "character", name, signal, config)
    for name, signal in [("weak-place", .1), ("p1", 1), ("p2", .9)]:
        records = learn_affinity(records, "place", name, signal, config)
    lookup = affinity_lookup(records, config)
    assert set(lookup["character"]) == {"a", "b", "c"}
    assert set(lookup["place"]) == {"p1", "p2"}


def test_decay_is_explicit_slow_and_can_drop_neutral_records():
    config = cfg()
    records = [
        {"kind": "character", "subject": "alice", "affinity": .8, "familiarity": .8},
        {"kind": "place", "subject": "tiny", "affinity": .005, "familiarity": .005},
    ]
    decayed = decay_affinities(records, 100, config)
    lookup = affinity_lookup(decayed, config)
    assert 0.7 < lookup["character"]["alice"]["affinity"] < .8
    assert 0.7 < lookup["character"]["alice"]["familiarity"] < .8
    assert "tiny" not in lookup["place"]


def test_empty_affinity_has_exact_zero_utility_bias():
    assert affinity_utility_bias([], {"social_subject": "alice", "place_subject": "tower"}, cfg()) == {
        "idle": 0.0, "wander": 0.0, "inspect": 0.0,
        "social": 0.0, "return_home": 0.0, "rest": 0.0,
    }


def test_matching_character_and_place_ids_apply_only_relevant_capped_biases():
    config = cfg()
    records = [
        {"kind": "character", "subject": "alice", "affinity": 1, "familiarity": 1},
        {"kind": "character", "subject": "bob", "affinity": -1, "familiarity": 1},
        {"kind": "place", "subject": "tower", "affinity": 1, "familiarity": 1},
        {"kind": "place", "subject": "home", "affinity": .8, "familiarity": 1},
    ]
    bias = affinity_utility_bias(records, {
        "social_subject": "alice",
        "place_subject": "tower",
        "home_place_subject": "home",
        "away_from_home": True,
    }, config)
    assert bias["social"] == .30
    assert bias["wander"] == .12
    assert bias["inspect"] == .08
    assert bias["return_home"] == .16
    assert affinity_utility_bias(records, {"social_subject": "unknown"}, config)["social"] == 0.0


def test_favorite_place_is_positive_familiar_and_deterministic():
    config = cfg()
    records = [
        {"kind": "place", "subject": "market", "affinity": .6, "familiarity": .4},
        {"kind": "place", "subject": "garden", "affinity": .6, "familiarity": .9},
        {"kind": "place", "subject": "bad", "affinity": -.9, "familiarity": 1},
    ]
    assert favorite_place(records, config) == "garden"
    assert favorite_place([{"kind": "place", "subject": "meh", "affinity": .1, "familiarity": 1}], config) is None
