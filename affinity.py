from __future__ import annotations

"""Bounded long-term affinity/favorite-place mechanics for KROLIK.

This module is intentionally pure and policy-driven. `life_sim.py` owns the
policy values; callers pass that config here so Python/Godot can share the same
semantics without making relationship history an unbounded per-frame system.
"""

import math
from typing import Any


AFFINITY_KINDS = ("character", "place")
UTILITY_STATES = ("idle", "wander", "inspect", "social", "return_home", "rest")

DEFAULT_LONG_TERM_AFFINITY_POLICY: dict[str, Any] = {
    "character_capacity": 16,
    "place_capacity": 8,
    "max_subject_length": 64,
    "learning_rate": 0.20,
    "familiarity_gain": 0.08,
    "decay_per_hour": 0.001,
    "familiarity_decay_per_hour": 0.0002,
    "drop_epsilon": 0.01,
    "max_abs_state_bias": 0.30,
    "character_social_weight": 0.30,
    "place_wander_weight": 0.12,
    "place_inspect_weight": 0.08,
    "home_return_weight": 0.20,
    "favorite_min_affinity": 0.20,
}


def _finite(value: Any, default: float = 0.0) -> float:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return default
    return out if math.isfinite(out) else default


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, float(value)))


def _capacity_for(kind: str, config: dict[str, Any]) -> int:
    key = "character_capacity" if kind == "character" else "place_capacity"
    return max(1, min(128, int(config.get(key, 16 if kind == "character" else 8))))


def _sanitize_record(raw: Any, config: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    kind = str(raw.get("kind") or "")
    if kind not in AFFINITY_KINDS:
        return None
    max_len = max(1, min(256, int(config.get("max_subject_length", 64))))
    subject = str(raw.get("subject") or "")[:max_len]
    if not subject:
        return None
    return {
        "kind": kind,
        "subject": subject,
        "affinity": _clamp(_finite(raw.get("affinity"), 0.0), -1.0, 1.0),
        "familiarity": _clamp(_finite(raw.get("familiarity"), 0.0), 0.0, 1.0),
    }


def _retention(record: dict[str, Any]) -> float:
    """Importance for bounded eviction: known/strong relations survive first."""
    return abs(float(record["affinity"])) * 0.70 + float(record["familiarity"]) * 0.30


def _evict_kind(records: list[dict[str, Any]], kind: str, config: dict[str, Any]) -> list[dict[str, Any]]:
    capacity = _capacity_for(kind, config)
    indices = [index for index, record in enumerate(records) if record["kind"] == kind]
    while len(indices) > capacity:
        # Stable deterministic tie-break: retention, familiarity, affinity,
        # lexical subject, then original order. Lowest score is evicted.
        victim = min(
            indices,
            key=lambda index: (
                _retention(records[index]),
                float(records[index]["familiarity"]),
                abs(float(records[index]["affinity"])),
                str(records[index]["subject"]),
                index,
            ),
        )
        records.pop(victim)
        indices = [index for index, record in enumerate(records) if record["kind"] == kind]
    return records


def normalize_affinity_records(value: Any, config: dict[str, Any]) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    out: list[dict[str, Any]] = []
    index_by_key: dict[tuple[str, str], int] = {}
    for raw in value:
        record = _sanitize_record(raw, config)
        if record is None:
            continue
        key = (record["kind"], record["subject"])
        if key in index_by_key:
            index = index_by_key[key]
            existing = out[index]
            # More familiar wins; stronger absolute affinity breaks ties.
            if (
                record["familiarity"],
                abs(record["affinity"]),
            ) > (
                existing["familiarity"],
                abs(existing["affinity"]),
            ):
                out[index] = record
        else:
            index_by_key[key] = len(out)
            out.append(record)
    out = _evict_kind(out, "character", config)
    out = _evict_kind(out, "place", config)
    return out


def learn_affinity(
    records_value: Any,
    kind: str,
    subject: str,
    signal: float,
    config: dict[str, Any],
) -> list[dict[str, Any]]:
    records = normalize_affinity_records(records_value, config)
    candidate = _sanitize_record({"kind": kind, "subject": subject}, config)
    if candidate is None:
        return records
    signal_f = _clamp(_finite(signal, 0.0), -1.0, 1.0)
    learning_rate = max(0.0, _finite(config.get("learning_rate"), 0.20))
    familiarity_gain = max(0.0, _finite(config.get("familiarity_gain"), 0.08))
    for record in records:
        if record["kind"] == candidate["kind"] and record["subject"] == candidate["subject"]:
            record["affinity"] = _clamp(record["affinity"] + signal_f * learning_rate, -1.0, 1.0)
            record["familiarity"] = _clamp(record["familiarity"] + abs(signal_f) * familiarity_gain, 0.0, 1.0)
            return records
    candidate["affinity"] = _clamp(signal_f * learning_rate, -1.0, 1.0)
    candidate["familiarity"] = _clamp(abs(signal_f) * familiarity_gain, 0.0, 1.0)
    records.append(candidate)
    return _evict_kind(records, kind, config)


def decay_affinities(records_value: Any, elapsed_hours: float, config: dict[str, Any]) -> list[dict[str, Any]]:
    records = normalize_affinity_records(records_value, config)
    hours = max(0.0, min(_finite(elapsed_hours, 0.0), 24.0 * 365.0))
    affinity_decay = max(0.0, _finite(config.get("decay_per_hour"), 0.001))
    familiarity_decay = max(0.0, _finite(config.get("familiarity_decay_per_hour"), 0.0002))
    affinity_factor = max(0.0, 1.0 - affinity_decay * hours)
    familiarity_factor = max(0.0, 1.0 - familiarity_decay * hours)
    epsilon = _clamp(_finite(config.get("drop_epsilon"), 0.01), 0.0, 1.0)
    out: list[dict[str, Any]] = []
    for record in records:
        updated = dict(record)
        updated["affinity"] = _clamp(float(updated["affinity"]) * affinity_factor, -1.0, 1.0)
        updated["familiarity"] = _clamp(float(updated["familiarity"]) * familiarity_factor, 0.0, 1.0)
        if abs(updated["affinity"]) <= epsilon and updated["familiarity"] <= epsilon:
            continue
        out.append(updated)
    return out


def affinity_lookup(records_value: Any, config: dict[str, Any]) -> dict[str, dict[str, dict[str, Any]]]:
    lookup = {"character": {}, "place": {}}
    for record in normalize_affinity_records(records_value, config):
        lookup[record["kind"]][record["subject"]] = dict(record)
    return lookup


def affinity_utility_bias(
    records_value: Any,
    context: dict[str, Any] | None,
    config: dict[str, Any],
) -> dict[str, float]:
    bias = {state: 0.0 for state in UTILITY_STATES}
    if not context:
        return bias
    lookup = affinity_lookup(records_value, config)
    social_subject = str(context.get("social_subject") or "")
    if social_subject:
        record = lookup["character"].get(social_subject)
        if record:
            strength = float(record["affinity"]) * float(record["familiarity"])
            bias["social"] += strength * _finite(config.get("character_social_weight"), 0.30)

    place_subject = str(context.get("place_subject") or "")
    if place_subject:
        record = lookup["place"].get(place_subject)
        if record:
            strength = float(record["affinity"]) * float(record["familiarity"])
            bias["wander"] += strength * _finite(config.get("place_wander_weight"), 0.12)
            bias["inspect"] += strength * _finite(config.get("place_inspect_weight"), 0.08)

    home_subject = str(context.get("home_place_subject") or "")
    if bool(context.get("away_from_home", False)) and home_subject:
        record = lookup["place"].get(home_subject)
        if record:
            strength = float(record["affinity"]) * float(record["familiarity"])
            bias["return_home"] += strength * _finite(config.get("home_return_weight"), 0.20)

    cap = max(0.0, _finite(config.get("max_abs_state_bias"), 0.30))
    for state in bias:
        bias[state] = _clamp(bias[state], -cap, cap)
    return bias


def favorite_place(records_value: Any, config: dict[str, Any]) -> str | None:
    minimum = _clamp(_finite(config.get("favorite_min_affinity"), 0.20), -1.0, 1.0)
    candidates = []
    for record in normalize_affinity_records(records_value, config):
        if record["kind"] != "place" or float(record["affinity"]) < minimum:
            continue
        score = float(record["affinity"]) * (0.5 + 0.5 * float(record["familiarity"]))
        candidates.append((score, float(record["familiarity"]), str(record["subject"])))
    if not candidates:
        return None
    # Highest score/familiarity; lexical id makes exact ties deterministic.
    candidates.sort(key=lambda item: (-item[0], -item[1], item[2]))
    return candidates[0][2]
