from __future__ import annotations

from copy import deepcopy
import math
from typing import Any

from affinity import (
    DEFAULT_LONG_TERM_AFFINITY_POLICY,
    affinity_utility_bias,
    favorite_place,
    normalize_affinity_records,
)


AI_POLICY_SCHEMA = "krolik.ai-policy/1"
AI_POLICY_FORMAT_VERSION = 1
TRAIT_NAMES = ("curiosity", "sociability", "boldness", "patience", "resilience")
NEUTRAL_TRAITS = {name: 0.5 for name in TRAIT_NAMES}

# Semantic source of truth for both editor-side Python simulation and the Godot
# runtime brain. Tunable behavior belongs here and is exported to Godot.
AI_POLICY: dict[str, Any] = {
    "schema": AI_POLICY_SCHEMA,
    "format_version": AI_POLICY_FORMAT_VERSION,
    "defaults": {
        "needs": {"energy": 0.82, "comfort": 0.72, "curiosity": 0.35, "social": 0.45},
        "profile": {
            "autonomy": 0.75,
            "wander": 0.65,
            "social": 0.45,
            "rest_threshold": 0.24,
            "curiosity_threshold": 0.72,
            "home_bias": 0.35,
            "mobility": "auto",
            "walk_speed": 1.0,
            "routine": "balanced",
            "traits": deepcopy(NEUTRAL_TRAITS),
        },
    },
    "valid": {
        "mobility": ["auto", "free", "contained", "disabled"],
        "routine": ["balanced", "homebody", "explorer", "social"],
        "bound_modes": ["bound", "anchored", "contained", "restrained"],
        "traits": list(TRAIT_NAMES),
    },
    "state_order": ["return_home", "rest", "social", "inspect", "wander", "idle"],
    "hard_gates": {
        "away_comfort_return": 0.22,
        "autonomy_lock": 0.20,
        "inspect_no_target_multiplier": 0.82,
        "rest_energy_margin": 0.20,
        "rest_energy_floor": 0.50,
        "rest_ready_multiplier": 0.35,
    },
    "utility": {
        "idle": {"base": 0.20, "comfort": 0.12, "inverse_autonomy": 0.18},
        "wander": {"base": 0.16, "wander": 0.42, "autonomy": 0.20, "curiosity": 0.16},
        "inspect": {"base": 0.12, "curiosity": 0.58},
        "social": {"base": 0.10, "social_need": 0.48, "social_drive": 0.28},
        "return_home": {"base": 0.08, "home_bias": 0.35, "inverse_comfort": 0.32, "inverse_energy": 0.26},
        "rest": {"base": 0.12, "inverse_energy": 0.88, "home_bonus": 0.18, "away_bonus": -0.25},
        "target": {"cap": 0.18, "step": 0.06},
        "routine_bonus": {"explorer": 0.18, "social": 0.18, "homebody": 0.20},
    },
    # Trait values are centered on 0.5, so old profiles and neutral traits add
    # exactly zero utility. Effects express temperament, not duplicate raw knobs.
    "trait_effects": {
        "curiosity": {"inspect": 0.70, "wander": 0.10},
        "sociability": {"social": 0.70},
        "boldness": {"wander": 0.50, "return_home": -0.30},
        "patience": {"idle": 0.50},
        "resilience": {"rest": -0.45, "return_home": -0.20},
    },
    # D3 short-term memory is intentionally tiny and bounded. A signed valence
    # multiplied by importance and recency produces a capped utility nudge.
    "short_term_memory": {
        "capacity": 8,
        "default_ttl": 180.0,
        "max_ttl": 900.0,
        "max_subject_length": 64,
        "max_abs_state_bias": 0.35,
        "unfocused_subject_scale": 0.25,
        "effects": {
            "interesting": {"inspect": 0.32, "wander": 0.08},
            "social": {"social": 0.32, "return_home": -0.10},
            "home": {"return_home": 0.28},
            "threat": {"return_home": -0.30, "inspect": 0.15},
            "rest": {"rest": 0.25},
        },
    },
    # D4 long-term affinity is event-driven and independently bounded. Empty
    # affinity is neutral; only explicit subject ids influence utility.
    "long_term_affinity": deepcopy(DEFAULT_LONG_TERM_AFFINITY_POLICY),
    "need_rates_per_minute": {
        "rest": {"energy": 0.055, "comfort": 0.018, "curiosity": 0.012, "social": 0.0},
        "contained": {"energy": -0.004, "comfort": -0.006, "curiosity": 0.020, "social": 0.010},
        "active": {"energy": -0.018, "comfort": -0.004, "curiosity": -0.008, "social": -0.003},
        "inspect_override": {"curiosity": -0.028},
        "social_override": {"social": -0.025},
        "idle": {"energy": -0.005, "comfort": 0.0, "curiosity": 0.008, "social": 0.005},
    },
    "affect_thresholds": {
        "tired_energy": 0.22,
        "uneasy_comfort": 0.28,
        "alert_curiosity": 0.78,
        "seeking_social": 0.78,
    },
    "animation_by_state": {
        "idle": "idle_breathe",
        "wander": "walk",
        "inspect": "inspect",
        "social": "social_idle",
        "return_home": "walk",
        "contained": "contained_idle",
        "rest": "rest",
        "disabled": "idle_static",
    },
}


def policy_document() -> dict[str, Any]:
    return deepcopy(AI_POLICY)


DEFAULT_NEEDS = dict(AI_POLICY["defaults"]["needs"])
DEFAULT_PROFILE = deepcopy(AI_POLICY["defaults"]["profile"])
MOBILE_STATES = {"idle", "wander", "inspect", "social", "return_home"}
ANIMATION_BY_STATE = dict(AI_POLICY["animation_by_state"])


def clamp01(v: float) -> float:
    return max(0.0, min(1.0, float(v)))


def _finite_float(value: Any, default: float = 0.0) -> float:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return default
    return out if math.isfinite(out) else default


def _merged_traits(value: Any) -> dict[str, float]:
    out = dict(NEUTRAL_TRAITS)
    if isinstance(value, dict):
        for name in TRAIT_NAMES:
            if name in value:
                out[name] = clamp01(value[name])
    return out


def _trait_delta(profile: dict[str, Any], name: str) -> float:
    traits = profile.get("traits", {})
    value = traits.get(name, 0.5) if isinstance(traits, dict) else 0.5
    return clamp01(value) - 0.5


def _memory_policy() -> dict[str, Any]:
    return AI_POLICY["short_term_memory"]


def _sanitize_memory_entry(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    config = _memory_policy()
    effects = config["effects"]
    kind = str(raw.get("kind") or "")
    if kind not in effects:
        return None
    max_subject_length = int(config["max_subject_length"])
    subject = str(raw.get("subject") or "")[:max_subject_length]
    valence = max(-1.0, min(1.0, _finite_float(raw.get("valence"), 0.0)))
    importance = clamp01(_finite_float(raw.get("importance"), 0.5))
    ttl = _finite_float(raw.get("ttl"), float(config["default_ttl"]))
    ttl = max(1.0, min(float(config["max_ttl"]), ttl))
    age = max(0.0, _finite_float(raw.get("age"), 0.0))
    if age >= ttl:
        return None
    return {
        "kind": kind,
        "subject": subject,
        "valence": valence,
        "importance": importance,
        "age": age,
        "ttl": ttl,
    }


def _memory_retention(entry: dict[str, Any]) -> float:
    ttl = max(1.0, float(entry["ttl"]))
    recency = max(0.0, 1.0 - float(entry["age"]) / ttl)
    return float(entry["importance"]) * recency


def _evict_memory(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    capacity = int(_memory_policy()["capacity"])
    out = list(entries)
    while len(out) > capacity:
        index = min(
            range(len(out)),
            key=lambda i: (_memory_retention(out[i]), -float(out[i]["age"]), i),
        )
        out.pop(index)
    return out


def normalize_short_term_memory(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    out: list[dict[str, Any]] = []
    index_by_key: dict[tuple[str, str], int] = {}
    for raw in value:
        entry = _sanitize_memory_entry(raw)
        if entry is None:
            continue
        key = (entry["kind"], entry["subject"])
        if key in index_by_key:
            existing_index = index_by_key[key]
            existing = out[existing_index]
            # Keep the fresher duplicate; importance breaks exact-age ties.
            if (entry["age"], -entry["importance"]) < (existing["age"], -existing["importance"]):
                out[existing_index] = entry
        else:
            index_by_key[key] = len(out)
            out.append(entry)
    return _evict_memory(out)


def remember_event(
    memory_value: Any,
    kind: str,
    *,
    subject: str = "",
    valence: float = 0.0,
    importance: float = 0.5,
    ttl: float | None = None,
) -> list[dict[str, Any]]:
    entries = normalize_short_term_memory(memory_value)
    raw = {
        "kind": kind,
        "subject": subject,
        "valence": valence,
        "importance": importance,
        "age": 0.0,
        "ttl": float(_memory_policy()["default_ttl"]) if ttl is None else ttl,
    }
    entry = _sanitize_memory_entry(raw)
    if entry is None:
        return entries
    key = (entry["kind"], entry["subject"])
    for index, existing in enumerate(entries):
        if (existing["kind"], existing["subject"]) == key:
            entries[index] = entry
            return entries
    entries.append(entry)
    return _evict_memory(entries)


def step_memory(memory_value: Any, dt: float) -> list[dict[str, Any]]:
    elapsed = max(0.0, min(_finite_float(dt, 0.0), 300.0))
    out: list[dict[str, Any]] = []
    for entry in normalize_short_term_memory(memory_value):
        aged = dict(entry)
        aged["age"] = float(aged["age"]) + elapsed
        if aged["age"] < aged["ttl"]:
            out.append(aged)
    return out


def _focused_memory_subjects(context: dict[str, Any] | None) -> set[str]:
    if not context:
        return set()
    subjects: set[str] = set()
    single = context.get("memory_subject")
    if single is not None and str(single):
        subjects.add(str(single))
    many = context.get("memory_subjects")
    if isinstance(many, (list, tuple, set)):
        subjects.update(str(item) for item in many if str(item))
    return subjects


def memory_utility_bias(memory_value: Any, context: dict[str, Any] | None = None) -> dict[str, float]:
    config = _memory_policy()
    effects = config["effects"]
    cap = float(config["max_abs_state_bias"])
    unfocused_scale = float(config["unfocused_subject_scale"])
    focused_subjects = _focused_memory_subjects(context)
    bias = {state: 0.0 for state in AI_POLICY["state_order"]}
    for entry in normalize_short_term_memory(memory_value):
        ttl = max(1.0, float(entry["ttl"]))
        recency = max(0.0, 1.0 - float(entry["age"]) / ttl)
        relevance = 1.0
        subject = str(entry["subject"])
        if subject and subject not in focused_subjects:
            relevance = unfocused_scale
        strength = float(entry["valence"]) * float(entry["importance"]) * recency * relevance
        for state_name, coefficient in effects[entry["kind"]].items():
            if state_name in bias:
                bias[state_name] += strength * float(coefficient)
    for state_name in bias:
        bias[state_name] = max(-cap, min(cap, bias[state_name]))
    return bias


def derive_affect(needs: dict[str, float], state: str) -> dict[str, Any]:
    energy = clamp01(needs.get("energy", 0.5))
    comfort = clamp01(needs.get("comfort", 0.5))
    curiosity = clamp01(needs.get("curiosity", 0.5))
    social = clamp01(needs.get("social", 0.5))
    thresholds = AI_POLICY["affect_thresholds"]
    if state == "rest" or energy < float(thresholds["tired_energy"]):
        mood = "tired"
    elif comfort < float(thresholds["uneasy_comfort"]):
        mood = "uneasy"
    elif curiosity > float(thresholds["alert_curiosity"]):
        mood = "alert"
    elif social > float(thresholds["seeking_social"]):
        mood = "seeking_company"
    else:
        mood = "calm"
    return {
        "mood": mood,
        "energy": energy,
        "comfort": comfort,
        "focus": max(curiosity, social),
        "animation": ANIMATION_BY_STATE.get(state, "idle_breathe"),
    }


def merged_profile(value: dict[str, Any] | None) -> dict[str, Any]:
    out = deepcopy(DEFAULT_PROFILE)
    if value:
        out.update({k: v for k, v in value.items() if k in out and k != "traits"})
        out["traits"] = _merged_traits(value.get("traits"))
    else:
        out["traits"] = dict(NEUTRAL_TRAITS)
    for key in ("autonomy", "wander", "social", "rest_threshold", "curiosity_threshold", "home_bias"):
        out[key] = clamp01(out[key])
    out["walk_speed"] = max(0.05, min(4.0, float(out["walk_speed"])))
    valid = AI_POLICY["valid"]
    if out["mobility"] not in set(valid["mobility"]):
        out["mobility"] = "auto"
    if out["routine"] not in set(valid["routine"]):
        out["routine"] = "balanced"
    return out


def merged_needs(value: dict[str, Any] | None) -> dict[str, float]:
    out = dict(DEFAULT_NEEDS)
    if value:
        for key in out:
            if key in value:
                out[key] = clamp01(value[key])
    return out


def is_bound_context(context: dict[str, Any] | None) -> bool:
    if not context:
        return False
    if context.get("locked") or context.get("bound"):
        return True
    return str(context.get("interaction_mode") or "").lower() in set(AI_POLICY["valid"]["bound_modes"])


def activity_scores(
    profile: dict[str, Any],
    needs: dict[str, float],
    context: dict[str, Any] | None = None,
    memory_value: Any = None,
    affinity_value: Any = None,
) -> dict[str, float]:
    context = context or {}
    away = bool(context.get("away_from_home", False))
    interesting = max(0.0, float(context.get("interesting_targets", 0.0)))
    social_targets = max(0.0, float(context.get("social_targets", 0.0)))
    utility = AI_POLICY["utility"]
    target = utility["target"]
    bonuses = utility["routine_bonus"]
    routine = profile.get("routine", "balanced")
    explorer_bonus = float(bonuses["explorer"]) if routine == "explorer" else 0.0
    social_bonus = float(bonuses["social"]) if routine == "social" else 0.0
    home_bonus = float(bonuses["homebody"]) if routine == "homebody" else 0.0
    idle = utility["idle"]
    wander_u = utility["wander"]
    inspect = utility["inspect"]
    social_u = utility["social"]
    return_home = utility["return_home"]
    rest = utility["rest"]
    scores = {
        "idle": float(idle["base"]) + needs["comfort"] * float(idle["comfort"]) + (1.0 - profile["autonomy"]) * float(idle["inverse_autonomy"]),
        "wander": float(wander_u["base"]) + profile["wander"] * float(wander_u["wander"]) + profile["autonomy"] * float(wander_u["autonomy"]) + needs["curiosity"] * float(wander_u["curiosity"]) + explorer_bonus,
        "inspect": float(inspect["base"]) + needs["curiosity"] * float(inspect["curiosity"]) + min(float(target["cap"]), interesting * float(target["step"])) + explorer_bonus,
        "social": float(social_u["base"]) + needs["social"] * float(social_u["social_need"]) + profile["social"] * float(social_u["social_drive"]) + min(float(target["cap"]), social_targets * float(target["step"])) + social_bonus,
        "return_home": (float(return_home["base"]) + profile["home_bias"] * float(return_home["home_bias"]) + home_bonus + (1.0 - needs["comfort"]) * float(return_home["inverse_comfort"]) + (1.0 - needs["energy"]) * float(return_home["inverse_energy"])) if away else 0.0,
        "rest": float(rest["base"]) + (1.0 - needs["energy"]) * float(rest["inverse_energy"]) + (float(rest["home_bonus"]) if not away else float(rest["away_bonus"])),
    }
    for trait_name, effects in AI_POLICY["trait_effects"].items():
        delta = _trait_delta(profile, trait_name)
        for state_name, coefficient in effects.items():
            if state_name in scores:
                scores[state_name] += delta * float(coefficient)
    memory_bias = memory_utility_bias(memory_value, context)
    for state_name, amount in memory_bias.items():
        if state_name in scores:
            scores[state_name] += amount
    affinity_bias = affinity_utility_bias(affinity_value, context, AI_POLICY["long_term_affinity"])
    for state_name, amount in affinity_bias.items():
        if state_name in scores:
            scores[state_name] += amount
    return scores


def choose_state(
    profile: dict[str, Any],
    needs: dict[str, float],
    context: dict[str, Any] | None = None,
    memory_value: Any = None,
    affinity_value: Any = None,
) -> str:
    context = context or {}
    if profile["mobility"] == "disabled":
        return "disabled"
    if profile["mobility"] == "contained" or (profile["mobility"] == "auto" and is_bound_context(context)):
        return "contained"
    away = bool(context.get("away_from_home", False))
    gates = AI_POLICY["hard_gates"]
    if needs["energy"] <= profile["rest_threshold"]:
        return "return_home" if away else "rest"
    if away and needs["comfort"] < float(gates["away_comfort_return"]):
        return "return_home"
    scores = activity_scores(profile, needs, context, memory_value, affinity_value)
    if float(context.get("social_targets", 0.0)) <= 0.0:
        scores["social"] = -1.0
    if float(context.get("interesting_targets", 0.0)) <= 0.0:
        scores["inspect"] *= float(gates["inspect_no_target_multiplier"])
    if profile["autonomy"] < float(gates["autonomy_lock"]):
        scores["wander"] = scores["inspect"] = -1.0
    if needs["energy"] > max(profile["rest_threshold"] + float(gates["rest_energy_margin"]), float(gates["rest_energy_floor"])):
        scores["rest"] *= float(gates["rest_ready_multiplier"])
    order = tuple(str(name) for name in AI_POLICY["state_order"])
    return max(order, key=lambda name: scores.get(name, -1.0))


def step_needs(needs: dict[str, float], state: str, dt: float) -> dict[str, float]:
    minute = max(0.0, min(float(dt), 300.0)) / 60.0
    out = dict(needs)
    rates = AI_POLICY["need_rates_per_minute"]
    if state == "rest":
        selected = rates["rest"]
    elif state == "contained":
        selected = rates["contained"]
    elif state in {"wander", "inspect", "social", "return_home"}:
        selected = dict(rates["active"])
        if state == "inspect":
            selected.update(rates["inspect_override"])
        if state == "social":
            selected.update(rates["social_override"])
    else:
        selected = rates["idle"]
    for key in DEFAULT_NEEDS:
        out[key] = clamp01(out[key] + float(selected.get(key, 0.0)) * minute)
    return out


def step_mind(
    profile_value: dict[str, Any] | None,
    needs_value: dict[str, Any] | None,
    dt: float,
    context: dict[str, Any] | None = None,
    memory_value: Any = None,
    affinity_value: Any = None,
) -> dict[str, Any]:
    profile = merged_profile(profile_value)
    needs = merged_needs(needs_value)
    memory = normalize_short_term_memory(memory_value)
    affinity = normalize_affinity_records(affinity_value, AI_POLICY["long_term_affinity"])
    state = choose_state(profile, needs, context, memory, affinity)
    needs = step_needs(needs, state, dt)
    memory = step_memory(memory, dt)
    next_state = choose_state(profile, needs, context, memory, affinity)
    return {
        "state": next_state,
        "needs": needs,
        "profile": profile,
        "memory": memory,
        "affinity": affinity,
        "favorite_place": favorite_place(affinity, AI_POLICY["long_term_affinity"]),
        "mobile": next_state in MOBILE_STATES,
        "contained": next_state == "contained",
        "animation": ANIMATION_BY_STATE.get(next_state, "idle_breathe"),
        "affect": derive_affect(needs, next_state),
        "utility": activity_scores(profile, needs, context, memory, affinity),
    }
