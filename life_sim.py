from __future__ import annotations

from copy import deepcopy
import math
from typing import Any


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
    # D4 long-term memory keeps compact durable preferences instead of raw event logs.
    # It is intentionally bounded so hundreds of agents remain cheap to save and score.
    "long_term_memory": {
        "relationship_capacity": 32,
        "place_capacity": 16,
        "max_id_length": 64,
        "relationship_learning_rate": 0.35,
        "place_learning_rate": 0.30,
        "familiarity_gain": 0.18,
        "affinity_decay_per_hour": 0.0025,
        "preference_decay_per_hour": 0.0015,
        "familiarity_decay_per_hour": 0.0005,
        "max_abs_state_bias": 0.30,
        "relationship_effects": {"social": 0.42, "return_home": -0.16},
        "current_place_effects": {"idle": 0.14, "rest": 0.12},
        "target_place_effects": {"wander": 0.18, "inspect": 0.10},
        "favorite_home_return_bonus": 0.16,
    },
    # D5 emotion model is a compact semantic state, not a cosmetic label.
    # It reacts to personality, social encounters and physical constraints while
    # remaining bounded and cheap enough for hundreds of agents.
    "emotion_model": {
        "channels": ["fear", "anger", "sadness", "joy", "trust", "shame", "hope", "frustration", "relief", "curiosity"],
        "response_per_second": 3.2,
        "max_dt": 10.0,
        "constraint_profiles": {
            "none": {"loss_of_control": 0.0, "discomfort": 0.0, "social_exposure": 0.0, "immobility": 0.0},
            "generic": {"loss_of_control": 0.50, "discomfort": 0.30, "social_exposure": 0.20, "immobility": 0.45},
            "contained": {"loss_of_control": 0.58, "discomfort": 0.24, "social_exposure": 0.16, "immobility": 0.62},
            "shackles": {"loss_of_control": 0.68, "discomfort": 0.34, "social_exposure": 0.24, "immobility": 0.60},
            "ankle_shackles": {"loss_of_control": 0.58, "discomfort": 0.30, "social_exposure": 0.20, "immobility": 0.52},
            "cuffs": {"loss_of_control": 0.62, "discomfort": 0.30, "social_exposure": 0.24, "immobility": 0.48},
            "tether": {"loss_of_control": 0.55, "discomfort": 0.22, "social_exposure": 0.24, "immobility": 0.42},
            "rope": {"loss_of_control": 0.66, "discomfort": 0.38, "social_exposure": 0.28, "immobility": 0.66},
            "harness": {"loss_of_control": 0.70, "discomfort": 0.35, "social_exposure": 0.30, "immobility": 0.68},
            "restraint_stool": {"loss_of_control": 0.72, "discomfort": 0.40, "social_exposure": 0.42, "immobility": 0.82},
            "restraint_chair": {"loss_of_control": 0.82, "discomfort": 0.44, "social_exposure": 0.38, "immobility": 0.90},
            "stocks": {"loss_of_control": 0.90, "discomfort": 0.48, "social_exposure": 0.62, "immobility": 0.94},
            "cage": {"loss_of_control": 0.72, "discomfort": 0.28, "social_exposure": 0.34, "immobility": 0.76},
            "wall_anchor": {"loss_of_control": 0.88, "discomfort": 0.46, "social_exposure": 0.45, "immobility": 0.92}
        },
        "facial_moods": ["calm", "tired", "uneasy", "alert", "seeking_company", "terrified", "afraid", "furious", "angry", "sad", "ashamed", "frustrated", "hopeful", "relieved", "happy", "content", "curious", "lonely", "anxious", "determined", "defiant", "resigned"]
    },
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


def _long_term_policy() -> dict[str, Any]:
    return AI_POLICY["long_term_memory"]


def _bounded_identifier(value: Any) -> str:
    limit = int(_long_term_policy()["max_id_length"])
    return str(value or "")[:limit]


def _sanitize_relationship(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    subject = _bounded_identifier(raw.get("subject"))
    if not subject:
        return None
    return {
        "subject": subject,
        "affinity": max(-1.0, min(1.0, _finite_float(raw.get("affinity"), 0.0))),
        "familiarity": clamp01(_finite_float(raw.get("familiarity"), 0.0)),
        "interactions": max(0, min(1_000_000, int(_finite_float(raw.get("interactions"), 0.0)))),
        "hours_since_contact": max(0.0, min(1_000_000.0, _finite_float(raw.get("hours_since_contact"), 0.0))),
    }


def _sanitize_place(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    place = _bounded_identifier(raw.get("place"))
    if not place:
        return None
    return {
        "place": place,
        "preference": max(-1.0, min(1.0, _finite_float(raw.get("preference"), 0.0))),
        "familiarity": clamp01(_finite_float(raw.get("familiarity"), 0.0)),
        "visits": max(0, min(1_000_000, int(_finite_float(raw.get("visits"), 0.0)))),
        "hours_since_visit": max(0.0, min(1_000_000.0, _finite_float(raw.get("hours_since_visit"), 0.0))),
    }


def _relationship_strength(entry: dict[str, Any]) -> float:
    return abs(float(entry["affinity"])) * 0.7 + float(entry["familiarity"]) * 0.3


def _place_strength(entry: dict[str, Any]) -> float:
    return abs(float(entry["preference"])) * 0.6 + float(entry["familiarity"]) * 0.4


def _favorite_place(places: list[dict[str, Any]]) -> str:
    if not places:
        return ""
    best = max(
        places,
        key=lambda entry: (
            float(entry["preference"]) * 0.7 + float(entry["familiarity"]) * 0.3,
            float(entry["familiarity"]),
            -float(entry["hours_since_visit"]),
            str(entry["place"]),
        ),
    )
    return str(best["place"])


def normalize_long_term_memory(value: Any) -> dict[str, Any]:
    source = value if isinstance(value, dict) else {}
    relationships: list[dict[str, Any]] = []
    by_subject: dict[str, int] = {}
    for raw in source.get("relationships", []) if isinstance(source.get("relationships", []), list) else []:
        entry = _sanitize_relationship(raw)
        if entry is None:
            continue
        subject = str(entry["subject"])
        if subject in by_subject:
            index = by_subject[subject]
            existing = relationships[index]
            if (entry["hours_since_contact"], -entry["familiarity"]) < (existing["hours_since_contact"], -existing["familiarity"]):
                relationships[index] = entry
        else:
            by_subject[subject] = len(relationships)
            relationships.append(entry)
    capacity = int(_long_term_policy()["relationship_capacity"])
    relationships.sort(key=lambda entry: (-_relationship_strength(entry), float(entry["hours_since_contact"]), str(entry["subject"])))
    relationships = relationships[:capacity]
    relationships.sort(key=lambda entry: str(entry["subject"]))

    places: list[dict[str, Any]] = []
    by_place: dict[str, int] = {}
    for raw in source.get("places", []) if isinstance(source.get("places", []), list) else []:
        entry = _sanitize_place(raw)
        if entry is None:
            continue
        place = str(entry["place"])
        if place in by_place:
            index = by_place[place]
            existing = places[index]
            if (entry["hours_since_visit"], -entry["familiarity"]) < (existing["hours_since_visit"], -existing["familiarity"]):
                places[index] = entry
        else:
            by_place[place] = len(places)
            places.append(entry)
    place_capacity = int(_long_term_policy()["place_capacity"])
    places.sort(key=lambda entry: (-_place_strength(entry), float(entry["hours_since_visit"]), str(entry["place"])))
    places = places[:place_capacity]
    places.sort(key=lambda entry: str(entry["place"]))
    return {"relationships": relationships, "places": places, "favorite_place": _favorite_place(places)}


def reinforce_relationship(
    memory_value: Any,
    subject: str,
    *,
    valence: float,
    importance: float = 0.5,
) -> dict[str, Any]:
    memory = normalize_long_term_memory(memory_value)
    subject = _bounded_identifier(subject)
    if not subject:
        return memory
    config = _long_term_policy()
    signal = max(-1.0, min(1.0, _finite_float(valence, 0.0)))
    importance = clamp01(_finite_float(importance, 0.5))
    alpha = clamp01(float(config["relationship_learning_rate"]) * importance)
    familiarity_gain = float(config["familiarity_gain"]) * importance
    relationships = [dict(entry) for entry in memory["relationships"]]
    for entry in relationships:
        if entry["subject"] == subject:
            entry["affinity"] = max(-1.0, min(1.0, float(entry["affinity"]) * (1.0 - alpha) + signal * alpha))
            entry["familiarity"] = clamp01(float(entry["familiarity"]) + familiarity_gain * (1.0 - float(entry["familiarity"])))
            entry["interactions"] = min(1_000_000, int(entry["interactions"]) + 1)
            entry["hours_since_contact"] = 0.0
            return normalize_long_term_memory({"relationships": relationships, "places": memory["places"]})
    relationships.append({
        "subject": subject,
        "affinity": signal * alpha,
        "familiarity": clamp01(familiarity_gain),
        "interactions": 1,
        "hours_since_contact": 0.0,
    })
    return normalize_long_term_memory({"relationships": relationships, "places": memory["places"]})


def remember_place_visit(
    memory_value: Any,
    place: str,
    *,
    preference: float = 0.0,
    importance: float = 0.5,
) -> dict[str, Any]:
    memory = normalize_long_term_memory(memory_value)
    place = _bounded_identifier(place)
    if not place:
        return memory
    config = _long_term_policy()
    signal = max(-1.0, min(1.0, _finite_float(preference, 0.0)))
    importance = clamp01(_finite_float(importance, 0.5))
    alpha = clamp01(float(config["place_learning_rate"]) * importance)
    familiarity_gain = float(config["familiarity_gain"]) * importance
    places = [dict(entry) for entry in memory["places"]]
    for entry in places:
        if entry["place"] == place:
            entry["preference"] = max(-1.0, min(1.0, float(entry["preference"]) * (1.0 - alpha) + signal * alpha))
            entry["familiarity"] = clamp01(float(entry["familiarity"]) + familiarity_gain * (1.0 - float(entry["familiarity"])))
            entry["visits"] = min(1_000_000, int(entry["visits"]) + 1)
            entry["hours_since_visit"] = 0.0
            return normalize_long_term_memory({"relationships": memory["relationships"], "places": places})
    places.append({
        "place": place,
        "preference": signal * alpha,
        "familiarity": clamp01(familiarity_gain),
        "visits": 1,
        "hours_since_visit": 0.0,
    })
    return normalize_long_term_memory({"relationships": memory["relationships"], "places": places})


def step_long_term_memory(memory_value: Any, dt: float) -> dict[str, Any]:
    memory = normalize_long_term_memory(memory_value)
    hours = max(0.0, min(_finite_float(dt, 0.0), 604800.0)) / 3600.0
    if hours <= 0.0:
        return memory
    config = _long_term_policy()
    affinity_decay = float(config["affinity_decay_per_hour"]) * hours
    preference_decay = float(config["preference_decay_per_hour"]) * hours
    familiarity_decay = float(config["familiarity_decay_per_hour"]) * hours
    relationships = []
    for raw in memory["relationships"]:
        entry = dict(raw)
        affinity = float(entry["affinity"])
        entry["affinity"] = math.copysign(max(0.0, abs(affinity) - affinity_decay), affinity) if affinity else 0.0
        entry["familiarity"] = max(0.0, float(entry["familiarity"]) - familiarity_decay)
        entry["hours_since_contact"] = min(1_000_000.0, float(entry["hours_since_contact"]) + hours)
        relationships.append(entry)
    places = []
    for raw in memory["places"]:
        entry = dict(raw)
        preference = float(entry["preference"])
        entry["preference"] = math.copysign(max(0.0, abs(preference) - preference_decay), preference) if preference else 0.0
        entry["familiarity"] = max(0.0, float(entry["familiarity"]) - familiarity_decay)
        entry["hours_since_visit"] = min(1_000_000.0, float(entry["hours_since_visit"]) + hours)
        places.append(entry)
    return normalize_long_term_memory({"relationships": relationships, "places": places})


def long_term_utility_bias(memory_value: Any, context: dict[str, Any] | None = None) -> dict[str, float]:
    memory = normalize_long_term_memory(memory_value)
    context = context or {}
    config = _long_term_policy()
    cap = float(config["max_abs_state_bias"])
    bias = {state: 0.0 for state in AI_POLICY["state_order"]}

    subjects = _focused_memory_subjects(context)
    social_single = context.get("social_subject")
    if social_single is not None and str(social_single):
        subjects.add(str(social_single))
    social_many = context.get("social_subjects")
    if isinstance(social_many, (list, tuple, set)):
        subjects.update(str(item) for item in social_many if str(item))
    relationship_effects = config["relationship_effects"]
    for entry in memory["relationships"]:
        if entry["subject"] not in subjects:
            continue
        strength = float(entry["affinity"]) * float(entry["familiarity"])
        for state_name, coefficient in relationship_effects.items():
            bias[state_name] += strength * float(coefficient)

    current_place = _bounded_identifier(context.get("current_place"))
    target_place = _bounded_identifier(context.get("target_place"))
    home_place = _bounded_identifier(context.get("home_place"))
    favorite = str(memory["favorite_place"])
    for entry in memory["places"]:
        place = str(entry["place"])
        strength = float(entry["preference"]) * float(entry["familiarity"])
        if current_place and place == current_place:
            for state_name, coefficient in config["current_place_effects"].items():
                bias[state_name] += strength * float(coefficient)
        if target_place and place == target_place:
            for state_name, coefficient in config["target_place_effects"].items():
                bias[state_name] += strength * float(coefficient)
    if bool(context.get("away_from_home", False)) and favorite and home_place == favorite:
        bias["return_home"] += float(config["favorite_home_return_bonus"])

    for state_name in bias:
        bias[state_name] = max(-cap, min(cap, bias[state_name]))
    return bias



def _emotion_policy() -> dict[str, Any]:
    return AI_POLICY["emotion_model"]


def neutral_emotion_state() -> dict[str, Any]:
    out: dict[str, Any] = {name: 0.0 for name in _emotion_policy()["channels"]}
    out.update({
        "mood": "calm",
        "facial_mood": "calm",
        "intensity": 0.0,
        "valence": 0.0,
        "arousal": 0.0,
        "dominance": 0.5,
    })
    return out


def normalize_emotion_state(value: Any) -> dict[str, Any]:
    out = neutral_emotion_state()
    if not isinstance(value, dict):
        return out
    for name in _emotion_policy()["channels"]:
        out[name] = clamp01(_finite_float(value.get(name), 0.0))
    mood = str(value.get("mood") or out["mood"])
    facial = str(value.get("facial_mood") or mood)
    allowed = set(_emotion_policy()["facial_moods"])
    out["mood"] = mood
    out["facial_mood"] = facial if facial in allowed else "calm"
    out["intensity"] = clamp01(_finite_float(value.get("intensity"), max(float(out[name]) for name in _emotion_policy()["channels"])))
    out["valence"] = max(-1.0, min(1.0, _finite_float(value.get("valence"), 0.0)))
    out["arousal"] = clamp01(_finite_float(value.get("arousal"), 0.0))
    out["dominance"] = clamp01(_finite_float(value.get("dominance"), 0.5))
    return out


def _constraint_kind(context: dict[str, Any]) -> str:
    raw = str(context.get("constraint_kind") or context.get("fixture_kind") or context.get("interaction_mode") or "").lower()
    aliases = (
        (("ankle", "shackle"), "ankle_shackles"),
        (("shackle",), "shackles"),
        (("cuff",), "cuffs"),
        (("stool",), "restraint_stool"),
        (("chair",), "restraint_chair"),
        (("stock",), "stocks"),
        (("cage",), "cage"),
        (("wall", "anchor"), "wall_anchor"),
        (("harness",), "harness"),
        (("rope",), "rope"),
        (("tether",), "tether"),
        (("chain",), "tether"),
    )
    for needles, resolved in aliases:
        if all(needle in raw for needle in needles):
            return resolved
    if raw in _emotion_policy()["constraint_profiles"]:
        return raw
    if raw in {"bound", "anchored", "restrained", "contained"}:
        return "contained"
    return "generic" if raw else "none"


def step_emotion(
    profile_value: dict[str, Any] | None,
    needs_value: dict[str, Any] | None,
    state: str,
    context: dict[str, Any] | None = None,
    previous_value: Any = None,
    dt: float = 0.0,
) -> dict[str, Any]:
    context = context or {}
    profile = merged_profile(profile_value)
    needs = merged_needs(needs_value)
    previous = normalize_emotion_state(previous_value)
    config = _emotion_policy()
    traits = profile["traits"]
    boldness = float(traits["boldness"])
    resilience = float(traits["resilience"])
    patience = float(traits["patience"])
    sociability = float(traits["sociability"])
    curiosity_trait = float(traits["curiosity"])

    bound = bool(context.get("locked") or context.get("bound")) or str(context.get("interaction_mode") or "").lower() in set(AI_POLICY["valid"]["bound_modes"])
    kind = _constraint_kind(context)
    raw_profile = config["constraint_profiles"].get(kind, config["constraint_profiles"]["generic"])
    severity_default = 1.0 if bound else 0.0
    severity = clamp01(_finite_float(context.get("constraint_severity"), severity_default))
    loss = clamp01(float(raw_profile["loss_of_control"]) * severity)
    discomfort = clamp01(float(raw_profile["discomfort"]) * severity + clamp01(_finite_float(context.get("discomfort"), 0.0)) * 0.5)
    exposure = clamp01(float(raw_profile["social_exposure"]) * severity)
    immobility = clamp01(float(raw_profile["immobility"]) * severity)
    threat = clamp01(max(_finite_float(context.get("threat"), 0.0), _finite_float(context.get("danger"), 0.0)))
    pain = clamp01(_finite_float(context.get("pain"), 0.0))
    novelty = clamp01(_finite_float(context.get("constraint_novelty"), 0.55 if bound else 0.0))
    witnesses = clamp01(max(0.0, _finite_float(context.get("witnesses"), 0.0)) / 4.0)
    social_outcome = max(-1.0, min(1.0, _finite_float(context.get("social_success"), 0.0)))
    social_affinity = max(-1.0, min(1.0, _finite_float(context.get("social_affinity"), 0.0)))
    familiarity = clamp01(_finite_float(context.get("social_familiarity"), 0.0))
    positive_social = max(0.0, social_outcome * 0.75 + social_affinity * 0.25)
    negative_social = max(0.0, -social_outcome * 0.70 + -min(0.0, social_affinity) * 0.30)
    released = bool(context.get("released", False))
    safe = bool(context.get("safe", False))

    targets = {name: 0.0 for name in config["channels"]}
    targets["fear"] = clamp01(threat * (0.68 + (1.0 - boldness) * 0.18) + loss * (0.42 - boldness * 0.16) + novelty * 0.14 - resilience * 0.16)
    targets["anger"] = clamp01(loss * (0.18 + boldness * 0.44) + pain * 0.24 + negative_social * 0.35 + threat * boldness * 0.12 - patience * 0.12)
    targets["sadness"] = clamp01(loss * 0.16 + (1.0 - needs["comfort"]) * 0.24 + negative_social * 0.26 - resilience * 0.18)
    targets["frustration"] = clamp01(loss * (0.30 + (1.0 - patience) * 0.28) + discomfort * 0.34 + immobility * 0.16)
    targets["shame"] = clamp01((exposure + witnesses * 0.35) * (0.34 + (1.0 - boldness) * 0.26) + negative_social * 0.12)
    targets["joy"] = clamp01(positive_social * (0.42 + sociability * 0.30) + (0.16 if safe else 0.0))
    targets["trust"] = clamp01(positive_social * (0.34 + sociability * 0.30) + familiarity * max(0.0, social_affinity) * 0.30)
    targets["hope"] = clamp01((0.54 if released else 0.0) + (0.18 if safe else 0.0) + positive_social * 0.20 - threat * 0.12)
    prior_distress = max(float(previous["fear"]), float(previous["frustration"]), float(previous["sadness"]))
    targets["relief"] = clamp01((0.72 if released else 0.0) * max(0.35, prior_distress) + (0.14 if safe else 0.0))
    targets["curiosity"] = clamp01(novelty * (0.18 + curiosity_trait * 0.62) * (1.0 - threat * 0.55) + max(0.0, needs["curiosity"] - 0.65) * 0.28)

    if state == "contained":
        targets["frustration"] = clamp01(targets["frustration"] + 0.10 * (1.0 - patience))
    if needs["energy"] < 0.22:
        targets["sadness"] = clamp01(targets["sadness"] + (0.22 - needs["energy"]) * 0.7)
    if needs["social"] > 0.82 and not positive_social:
        targets["sadness"] = clamp01(targets["sadness"] + (needs["social"] - 0.82) * 0.8)

    safe_dt = max(0.0, min(_finite_float(dt, 0.0), float(config["max_dt"])))
    alpha = 1.0 if safe_dt <= 0.0 else 1.0 - math.exp(-float(config["response_per_second"]) * safe_dt)
    out = neutral_emotion_state()
    for name in config["channels"]:
        out[name] = clamp01(float(previous[name]) + (float(targets[name]) - float(previous[name])) * alpha)

    strongest = max(config["channels"], key=lambda name: float(out[name]))
    intensity = float(out[strongest])
    if out["fear"] >= 0.72:
        mood = "terrified"
    elif strongest == "fear" and intensity >= 0.28:
        mood = "afraid"
    elif out["anger"] >= 0.72:
        mood = "furious"
    elif strongest == "anger" and intensity >= 0.28:
        mood = "angry"
    elif strongest == "shame" and intensity >= 0.28:
        mood = "ashamed"
    elif strongest == "frustration" and intensity >= 0.28:
        mood = "frustrated"
    elif strongest == "sadness" and intensity >= 0.28:
        mood = "sad"
    elif strongest == "relief" and intensity >= 0.24:
        mood = "relieved"
    elif strongest == "joy" and intensity >= 0.25:
        mood = "happy"
    elif strongest == "hope" and intensity >= 0.24:
        mood = "hopeful"
    elif strongest == "curiosity" and intensity >= 0.30:
        mood = "curious"
    elif strongest == "trust" and intensity >= 0.30:
        mood = "content"
    elif state == "rest" or needs["energy"] < 0.22:
        mood = "tired"
    elif needs["comfort"] < 0.28:
        mood = "uneasy"
    elif needs["social"] > 0.82:
        mood = "lonely"
    elif needs["curiosity"] > 0.78:
        mood = "alert"
    else:
        mood = "calm"

    positive = float(out["joy"]) + float(out["trust"]) + float(out["hope"]) + float(out["relief"])
    negative = float(out["fear"]) + float(out["anger"]) + float(out["sadness"]) + float(out["shame"]) + float(out["frustration"])
    out["mood"] = mood
    out["facial_mood"] = mood if mood in set(config["facial_moods"]) else "calm"
    out["intensity"] = clamp01(intensity)
    out["valence"] = max(-1.0, min(1.0, (positive - negative) / 2.5))
    out["arousal"] = clamp01(max(float(out["fear"]), float(out["anger"]), float(out["frustration"]), float(out["joy"]) * 0.7, float(out["curiosity"]) * 0.6))
    out["dominance"] = clamp01(0.25 + profile["autonomy"] * 0.35 + boldness * 0.28 - loss * 0.48 - float(out["fear"]) * 0.18 + float(out["anger"]) * 0.12)
    return out


def derive_affect(
    needs: dict[str, float],
    state: str,
    profile: dict[str, Any] | None = None,
    context: dict[str, Any] | None = None,
    emotion_value: Any = None,
    dt: float = 0.0,
) -> dict[str, Any]:
    out = step_emotion(profile, needs, state, context, emotion_value, dt)
    out["energy"] = clamp01(needs.get("energy", 0.5))
    out["comfort"] = clamp01(needs.get("comfort", 0.5))
    out["focus"] = max(clamp01(needs.get("curiosity", 0.5)), clamp01(needs.get("social", 0.5)))
    out["animation"] = ANIMATION_BY_STATE.get(state, "idle_breathe")
    return out


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
    long_term_memory_value: Any = None,
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
    long_term_bias = long_term_utility_bias(long_term_memory_value, context)
    for state_name in scores:
        scores[state_name] += memory_bias.get(state_name, 0.0) + long_term_bias.get(state_name, 0.0)
    return scores


def choose_state(
    profile: dict[str, Any],
    needs: dict[str, float],
    context: dict[str, Any] | None = None,
    memory_value: Any = None,
    long_term_memory_value: Any = None,
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
    scores = activity_scores(profile, needs, context, memory_value, long_term_memory_value)
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
    long_term_memory_value: Any = None,
    emotion_value: Any = None,
) -> dict[str, Any]:
    profile = merged_profile(profile_value)
    needs = merged_needs(needs_value)
    memory = normalize_short_term_memory(memory_value)
    long_term_memory = normalize_long_term_memory(long_term_memory_value)
    state = choose_state(profile, needs, context, memory, long_term_memory)
    needs = step_needs(needs, state, dt)
    memory = step_memory(memory, dt)
    long_term_memory = step_long_term_memory(long_term_memory, dt)
    next_state = choose_state(profile, needs, context, memory, long_term_memory)
    affect = derive_affect(needs, next_state, profile, context, emotion_value, dt)
    return {
        "state": next_state,
        "needs": needs,
        "profile": profile,
        "memory": memory,
        "long_term_memory": long_term_memory,
        "mobile": next_state in MOBILE_STATES,
        "contained": next_state == "contained",
        "animation": ANIMATION_BY_STATE.get(next_state, "idle_breathe"),
        "affect": affect,
        "utility": activity_scores(profile, needs, context, memory, long_term_memory),
    }
