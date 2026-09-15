class_name VaultAgentBrain
extends RefCounted

## Realtime mirror of life_sim.py driven by a generated versioned policy asset.

const POLICY_SCHEMA := "krolik.ai-policy/1"
const POLICY_FORMAT_VERSION := 1
const DEFAULT_POLICY_PATH := "res://data/ai_policy_v1.json"
const FALLBACK_TRAITS := {
    "curiosity": 0.5,
    "sociability": 0.5,
    "boldness": 0.5,
    "patience": 0.5,
    "resilience": 0.5,
}
const UTILITY_STATES := ["return_home", "rest", "social", "inspect", "wander", "idle"]
const LONG_TERM_FALLBACK := {
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
}

static var _default_policy_cache: Dictionary = {}
static var _default_policy_checked := false

var enabled := true
var state := "idle"
var mobility := "auto"
var routine := "balanced"
var autonomy := 0.75
var wander := 0.65
var social_drive := 0.45
var rest_threshold := 0.24
var curiosity_threshold := 0.72
var home_bias := 0.35
var walk_speed := 1.0
var traits: Dictionary = FALLBACK_TRAITS.duplicate(true)

var energy := 0.82
var comfort := 0.72
var curiosity := 0.35
var social := 0.45
var mood := "calm"
var last_utility: Dictionary = {}
var memory: Array = []
var long_term_memory: Dictionary = {"relationships": [], "places": [], "favorite_place": ""}

var policy_loaded := false
var policy_source := "fallback"
var _policy: Dictionary = {}

var _trait_bias_idle := 0.0
var _trait_bias_wander := 0.0
var _trait_bias_inspect := 0.0
var _trait_bias_social := 0.0
var _trait_bias_return_home := 0.0
var _trait_bias_rest := 0.0

var _memory_elapsed := 0.0
var _memory_next_expiry := INF
var _memory_base_idle := 0.0
var _memory_slope_idle := 0.0
var _memory_base_wander := 0.0
var _memory_slope_wander := 0.0
var _memory_base_inspect := 0.0
var _memory_slope_inspect := 0.0
var _memory_base_social := 0.0
var _memory_slope_social := 0.0
var _memory_base_return_home := 0.0
var _memory_slope_return_home := 0.0
var _memory_base_rest := 0.0
var _memory_slope_rest := 0.0
var _memory_focus_base: Dictionary = {}
var _memory_focus_slope: Dictionary = {}

func _init() -> void:
    var doc := _default_policy_document()
    if not doc.is_empty() and configure_policy(doc, DEFAULT_POLICY_PATH):
        _apply_policy_defaults()

static func _default_policy_document() -> Dictionary:
    if _default_policy_checked:
        return _default_policy_cache
    _default_policy_checked = true
    var file := FileAccess.open(DEFAULT_POLICY_PATH, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var doc: Dictionary = parsed
    if str(doc.get("schema", "")) != POLICY_SCHEMA or int(doc.get("format_version", 0)) != POLICY_FORMAT_VERSION:
        return {}
    for key in ["defaults", "valid", "hard_gates", "utility", "trait_effects", "short_term_memory", "need_rates_per_minute", "affect_thresholds"]:
        if typeof(doc.get(key, null)) != TYPE_DICTIONARY:
            return {}
    if typeof(doc.get("state_order", null)) != TYPE_ARRAY:
        return {}
    _default_policy_cache = doc
    return _default_policy_cache

func configure_policy(doc: Dictionary, source: String = "runtime") -> bool:
    if str(doc.get("schema", "")) != POLICY_SCHEMA or int(doc.get("format_version", 0)) != POLICY_FORMAT_VERSION:
        return false
    for key in ["defaults", "valid", "hard_gates", "utility", "trait_effects", "short_term_memory", "need_rates_per_minute", "affect_thresholds"]:
        if typeof(doc.get(key, null)) != TYPE_DICTIONARY:
            return false
    if typeof(doc.get("state_order", null)) != TYPE_ARRAY:
        return false
    _materialize_memory()
    _policy = doc.duplicate(true)
    policy_loaded = true
    policy_source = source
    _rebuild_trait_bias()
    memory = _normalize_memory(memory)
    long_term_memory = _normalize_long_term_memory(long_term_memory)
    _rebuild_memory_cache()
    return true

func _valid_values(key: String, fallback: Array) -> Array:
    var valid: Dictionary = _policy.get("valid", {})
    var values = valid.get(key, fallback)
    return values if typeof(values) == TYPE_ARRAY and not values.is_empty() else fallback

func _section(name: String) -> Dictionary:
    var value = _policy.get(name, {})
    return value if typeof(value) == TYPE_DICTIONARY else {}

func _subsection(section: String, name: String) -> Dictionary:
    var parent := _section(section)
    var value = parent.get(name, {})
    return value if typeof(value) == TYPE_DICTIONARY else {}

func _zero_bias() -> Dictionary:
    return {
        "return_home": 0.0,
        "rest": 0.0,
        "social": 0.0,
        "inspect": 0.0,
        "wander": 0.0,
        "idle": 0.0,
    }

func _normalized_traits(raw: Variant) -> Dictionary:
    var out := FALLBACK_TRAITS.duplicate(true)
    var names := _valid_values("traits", FALLBACK_TRAITS.keys())
    if typeof(raw) != TYPE_DICTIONARY:
        return out
    var source: Dictionary = raw
    for raw_name in names:
        var name := str(raw_name)
        if source.has(name):
            out[name] = clampf(float(source[name]), 0.0, 1.0)
    return out

func _add_trait_bias(state_name: String, amount: float) -> void:
    match state_name:
        "idle": _trait_bias_idle += amount
        "wander": _trait_bias_wander += amount
        "inspect": _trait_bias_inspect += amount
        "social": _trait_bias_social += amount
        "return_home": _trait_bias_return_home += amount
        "rest": _trait_bias_rest += amount

func _rebuild_trait_bias() -> void:
    _trait_bias_idle = 0.0
    _trait_bias_wander = 0.0
    _trait_bias_inspect = 0.0
    _trait_bias_social = 0.0
    _trait_bias_return_home = 0.0
    _trait_bias_rest = 0.0
    var trait_effects := _section("trait_effects")
    for raw_name in trait_effects.keys():
        var name := str(raw_name)
        var effects = trait_effects[raw_name]
        if typeof(effects) != TYPE_DICTIONARY:
            continue
        var delta := clampf(float(traits.get(name, 0.5)), 0.0, 1.0) - 0.5
        if absf(delta) <= 0.000001:
            continue
        for raw_state in effects.keys():
            _add_trait_bias(str(raw_state), delta * float(effects[raw_state]))

func _memory_config() -> Dictionary:
    return _section("short_term_memory")

func _memory_effects() -> Dictionary:
    var value = _memory_config().get("effects", {})
    return value if typeof(value) == TYPE_DICTIONARY else {}

func _sanitize_memory_entry(raw: Variant) -> Dictionary:
    if typeof(raw) != TYPE_DICTIONARY:
        return {}
    var source: Dictionary = raw
    var config := _memory_config()
    var effects := _memory_effects()
    var kind := str(source.get("kind", ""))
    if kind.is_empty() or not effects.has(kind):
        return {}
    var max_subject_length := maxi(1, int(config.get("max_subject_length", 64)))
    var subject := str(source.get("subject", ""))
    if subject.length() > max_subject_length:
        subject = subject.substr(0, max_subject_length)
    var valence := clampf(float(source.get("valence", 0.0)), -1.0, 1.0)
    var importance := clampf(float(source.get("importance", 0.5)), 0.0, 1.0)
    var max_ttl := maxf(1.0, float(config.get("max_ttl", 900.0)))
    var default_ttl := clampf(float(config.get("default_ttl", 180.0)), 1.0, max_ttl)
    var ttl := clampf(float(source.get("ttl", default_ttl)), 1.0, max_ttl)
    var age := maxf(0.0, float(source.get("age", 0.0)))
    if age >= ttl:
        return {}
    return {
        "kind": kind,
        "subject": subject,
        "valence": valence,
        "importance": importance,
        "age": age,
        "ttl": ttl,
    }

func _memory_retention(entry: Dictionary) -> float:
    var ttl := maxf(1.0, float(entry.get("ttl", 1.0)))
    return float(entry.get("importance", 0.0)) * maxf(0.0, 1.0 - float(entry.get("age", 0.0)) / ttl)

func _evict_memory(entries: Array) -> Array:
    var capacity := maxi(1, int(_memory_config().get("capacity", 8)))
    var out := entries.duplicate(true)
    while out.size() > capacity:
        var worst_index := 0
        var worst_retention := INF
        var worst_age := -INF
        for index in range(out.size()):
            var entry: Dictionary = out[index]
            var retention := _memory_retention(entry)
            var age := float(entry.get("age", 0.0))
            if retention < worst_retention - 0.000001 or (absf(retention - worst_retention) <= 0.000001 and age > worst_age):
                worst_index = index
                worst_retention = retention
                worst_age = age
        out.remove_at(worst_index)
    return out

func _normalize_memory(raw_value: Variant) -> Array:
    if typeof(raw_value) != TYPE_ARRAY:
        return []
    var out: Array = []
    var index_by_key: Dictionary = {}
    for raw in raw_value:
        var entry := _sanitize_memory_entry(raw)
        if entry.is_empty():
            continue
        var key := str(entry["kind"]) + "\u001f" + str(entry["subject"])
        if index_by_key.has(key):
            var existing_index := int(index_by_key[key])
            var existing: Dictionary = out[existing_index]
            var replace := float(entry["age"]) < float(existing["age"]) - 0.000001
            if absf(float(entry["age"]) - float(existing["age"])) <= 0.000001:
                replace = float(entry["importance"]) > float(existing["importance"])
            if replace:
                out[existing_index] = entry
        else:
            index_by_key[key] = out.size()
            out.append(entry)
    return _evict_memory(out)

func _materialize_memory() -> void:
    if _memory_elapsed <= 0.0:
        return
    var kept: Array = []
    for raw in memory:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = raw.duplicate(true)
        entry["age"] = float(entry.get("age", 0.0)) + _memory_elapsed
        if float(entry["age"]) < float(entry.get("ttl", 0.0)):
            kept.append(entry)
    memory = kept
    _memory_elapsed = 0.0

func _reset_memory_cache() -> void:
    _memory_base_idle = 0.0
    _memory_slope_idle = 0.0
    _memory_base_wander = 0.0
    _memory_slope_wander = 0.0
    _memory_base_inspect = 0.0
    _memory_slope_inspect = 0.0
    _memory_base_social = 0.0
    _memory_slope_social = 0.0
    _memory_base_return_home = 0.0
    _memory_slope_return_home = 0.0
    _memory_base_rest = 0.0
    _memory_slope_rest = 0.0
    _memory_focus_base.clear()
    _memory_focus_slope.clear()
    _memory_next_expiry = INF

func _add_memory_base(state_name: String, base_amount: float, slope_amount: float) -> void:
    match state_name:
        "idle":
            _memory_base_idle += base_amount
            _memory_slope_idle += slope_amount
        "wander":
            _memory_base_wander += base_amount
            _memory_slope_wander += slope_amount
        "inspect":
            _memory_base_inspect += base_amount
            _memory_slope_inspect += slope_amount
        "social":
            _memory_base_social += base_amount
            _memory_slope_social += slope_amount
        "return_home":
            _memory_base_return_home += base_amount
            _memory_slope_return_home += slope_amount
        "rest":
            _memory_base_rest += base_amount
            _memory_slope_rest += slope_amount

func _ensure_focus_cache(subject: String) -> void:
    if not _memory_focus_base.has(subject):
        _memory_focus_base[subject] = _zero_bias()
        _memory_focus_slope[subject] = _zero_bias()

func _rebuild_memory_cache() -> void:
    _reset_memory_cache()
    if memory.is_empty():
        return
    var config := _memory_config()
    var effects := _memory_effects()
    var unfocused_scale := clampf(float(config.get("unfocused_subject_scale", 0.25)), 0.0, 1.0)
    for raw in memory:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = raw
        var kind := str(entry.get("kind", ""))
        if not effects.has(kind) or typeof(effects[kind]) != TYPE_DICTIONARY:
            continue
        var ttl := maxf(1.0, float(entry.get("ttl", 1.0)))
        var age := maxf(0.0, float(entry.get("age", 0.0)))
        var remaining := ttl - age
        if remaining <= 0.0:
            continue
        _memory_next_expiry = minf(_memory_next_expiry, remaining)
        var subject := str(entry.get("subject", ""))
        var relevance := 1.0 if subject.is_empty() else unfocused_scale
        var valence := float(entry.get("valence", 0.0))
        var importance := float(entry.get("importance", 0.0))
        var recency := maxf(0.0, 1.0 - age / ttl)
        var base_strength := valence * importance * recency * relevance
        var slope_strength := -valence * importance * relevance / ttl
        var kind_effects: Dictionary = effects[kind]
        for raw_state in kind_effects.keys():
            var coefficient := float(kind_effects[raw_state])
            _add_memory_base(str(raw_state), base_strength * coefficient, slope_strength * coefficient)
        if subject.is_empty() or unfocused_scale >= 0.999999:
            continue
        _ensure_focus_cache(subject)
        var extra_relevance := 1.0 - unfocused_scale
        var extra_base := valence * importance * recency * extra_relevance
        var extra_slope := -valence * importance * extra_relevance / ttl
        var subject_base: Dictionary = _memory_focus_base[subject]
        var subject_slope: Dictionary = _memory_focus_slope[subject]
        for raw_state in kind_effects.keys():
            var state_name := str(raw_state)
            if subject_base.has(state_name):
                var coefficient := float(kind_effects[raw_state])
                subject_base[state_name] = float(subject_base[state_name]) + extra_base * coefficient
                subject_slope[state_name] = float(subject_slope[state_name]) + extra_slope * coefficient

func _memory_raw_bias(state_name: String) -> float:
    match state_name:
        "idle": return _memory_base_idle + _memory_slope_idle * _memory_elapsed
        "wander": return _memory_base_wander + _memory_slope_wander * _memory_elapsed
        "inspect": return _memory_base_inspect + _memory_slope_inspect * _memory_elapsed
        "social": return _memory_base_social + _memory_slope_social * _memory_elapsed
        "return_home": return _memory_base_return_home + _memory_slope_return_home * _memory_elapsed
        "rest": return _memory_base_rest + _memory_slope_rest * _memory_elapsed
        _: return 0.0

func _focused_subjects(context: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    var single = context.get("memory_subject", null)
    if single != null and not str(single).is_empty():
        out[str(single)] = true
    var many = context.get("memory_subjects", null)
    if typeof(many) == TYPE_ARRAY:
        for raw in many:
            var subject := str(raw)
            if not subject.is_empty():
                out[subject] = true
    return out

func _focused_memory_bias(context: Dictionary) -> Dictionary:
    if _memory_focus_base.is_empty():
        return {}
    var focused := _focused_subjects(context)
    if focused.is_empty():
        return {}
    var out := _zero_bias()
    for subject in focused.keys():
        if not _memory_focus_base.has(subject):
            continue
        var subject_base: Dictionary = _memory_focus_base[subject]
        var subject_slope: Dictionary = _memory_focus_slope.get(subject, {})
        for state_name in UTILITY_STATES:
            out[state_name] = float(out[state_name]) + float(subject_base.get(state_name, 0.0)) + float(subject_slope.get(state_name, 0.0)) * _memory_elapsed
    return out

func _combined_memory_bias(state_name: String, focused_bias: Dictionary) -> float:
    if memory.is_empty():
        return 0.0
    var value := _memory_raw_bias(state_name) + float(focused_bias.get(state_name, 0.0))
    var cap := maxf(0.0, float(_memory_config().get("max_abs_state_bias", 0.35)))
    return clampf(value, -cap, cap)

func remember_event(
    kind: String,
    subject: String = "",
    valence: float = 0.0,
    importance: float = 0.5,
    ttl: float = -1.0
) -> bool:
    _materialize_memory()
    var config := _memory_config()
    var resolved_ttl := float(config.get("default_ttl", 180.0)) if ttl <= 0.0 else ttl
    var entry := _sanitize_memory_entry({
        "kind": kind,
        "subject": subject,
        "valence": valence,
        "importance": importance,
        "age": 0.0,
        "ttl": resolved_ttl,
    })
    if entry.is_empty():
        _rebuild_memory_cache()
        return false
    var found := false
    for index in range(memory.size()):
        var existing: Dictionary = memory[index]
        if str(existing.get("kind", "")) == str(entry["kind"]) and str(existing.get("subject", "")) == str(entry["subject"]):
            memory[index] = entry
            found = true
            break
    if not found:
        memory.append(entry)
    memory = _evict_memory(memory)
    _rebuild_memory_cache()
    return true

func clear_memory() -> void:
    memory.clear()
    _memory_elapsed = 0.0
    _reset_memory_cache()

func memory_snapshot() -> Array:
    var out: Array = []
    for raw in memory:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = raw.duplicate(true)
        entry["age"] = float(entry.get("age", 0.0)) + _memory_elapsed
        if float(entry["age"]) < float(entry.get("ttl", 0.0)):
            out.append(entry)
    return out

func _long_term_config() -> Dictionary:
    var out := LONG_TERM_FALLBACK.duplicate(true)
    var configured := _section("long_term_memory")
    for key in configured.keys():
        out[key] = configured[key]
    return out

func _bounded_long_id(value: Variant) -> String:
    var limit := maxi(1, int(_long_term_config().get("max_id_length", 64)))
    var text := str(value if value != null else "")
    return text.substr(0, limit) if text.length() > limit else text

func _decay_signed(value: float, amount: float) -> float:
    if value > 0.0:
        return maxf(0.0, value - amount)
    if value < 0.0:
        return minf(0.0, value + amount)
    return 0.0

func _sanitize_relationship(raw: Variant) -> Dictionary:
    if typeof(raw) != TYPE_DICTIONARY:
        return {}
    var source: Dictionary = raw
    var subject := _bounded_long_id(source.get("subject", ""))
    if subject.is_empty():
        return {}
    return {
        "subject": subject,
        "affinity": clampf(float(source.get("affinity", 0.0)), -1.0, 1.0),
        "familiarity": clampf(float(source.get("familiarity", 0.0)), 0.0, 1.0),
        "interactions": clampi(int(source.get("interactions", 0)), 0, 1000000),
        "hours_since_contact": clampf(float(source.get("hours_since_contact", 0.0)), 0.0, 1000000.0),
    }

func _sanitize_place(raw: Variant) -> Dictionary:
    if typeof(raw) != TYPE_DICTIONARY:
        return {}
    var source: Dictionary = raw
    var place := _bounded_long_id(source.get("place", ""))
    if place.is_empty():
        return {}
    return {
        "place": place,
        "preference": clampf(float(source.get("preference", 0.0)), -1.0, 1.0),
        "familiarity": clampf(float(source.get("familiarity", 0.0)), 0.0, 1.0),
        "visits": clampi(int(source.get("visits", 0)), 0, 1000000),
        "hours_since_visit": clampf(float(source.get("hours_since_visit", 0.0)), 0.0, 1000000.0),
    }

func _relationship_strength(entry: Dictionary) -> float:
    return absf(float(entry.get("affinity", 0.0))) * 0.7 + float(entry.get("familiarity", 0.0)) * 0.3

func _place_strength(entry: Dictionary) -> float:
    return absf(float(entry.get("preference", 0.0))) * 0.6 + float(entry.get("familiarity", 0.0)) * 0.4

func _favorite_place_from(places: Array) -> String:
    var best_place := ""
    var best_score := -INF
    var best_familiarity := -INF
    var best_age := INF
    for raw in places:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = raw
        var score := float(entry.get("preference", 0.0)) * 0.7 + float(entry.get("familiarity", 0.0)) * 0.3
        var familiarity := float(entry.get("familiarity", 0.0))
        var age := float(entry.get("hours_since_visit", 0.0))
        var place := str(entry.get("place", ""))
        if score > best_score + 0.000001 or (absf(score - best_score) <= 0.000001 and familiarity > best_familiarity + 0.000001) or (absf(score - best_score) <= 0.000001 and absf(familiarity - best_familiarity) <= 0.000001 and age < best_age - 0.000001):
            best_place = place
            best_score = score
            best_familiarity = familiarity
            best_age = age
    return best_place

func _evict_weakest_relationship(entries: Array) -> void:
    if entries.is_empty():
        return
    var worst_index := 0
    var worst_strength := INF
    var worst_age := -INF
    for index in range(entries.size()):
        var entry: Dictionary = entries[index]
        var strength := _relationship_strength(entry)
        var age := float(entry.get("hours_since_contact", 0.0))
        if strength < worst_strength - 0.000001 or (absf(strength - worst_strength) <= 0.000001 and age > worst_age):
            worst_index = index
            worst_strength = strength
            worst_age = age
    entries.remove_at(worst_index)

func _evict_weakest_place(entries: Array) -> void:
    if entries.is_empty():
        return
    var worst_index := 0
    var worst_strength := INF
    var worst_age := -INF
    for index in range(entries.size()):
        var entry: Dictionary = entries[index]
        var strength := _place_strength(entry)
        var age := float(entry.get("hours_since_visit", 0.0))
        if strength < worst_strength - 0.000001 or (absf(strength - worst_strength) <= 0.000001 and age > worst_age):
            worst_index = index
            worst_strength = strength
            worst_age = age
    entries.remove_at(worst_index)

func _normalize_long_term_memory(raw_value: Variant) -> Dictionary:
    var source: Dictionary = raw_value if typeof(raw_value) == TYPE_DICTIONARY else {}
    var relationships: Array = []
    var relationship_index: Dictionary = {}
    var raw_relationships = source.get("relationships", [])
    if typeof(raw_relationships) == TYPE_ARRAY:
        for raw in raw_relationships:
            var entry := _sanitize_relationship(raw)
            if entry.is_empty():
                continue
            var subject := str(entry["subject"])
            if relationship_index.has(subject):
                var index := int(relationship_index[subject])
                var old: Dictionary = relationships[index]
                if float(entry["hours_since_contact"]) < float(old["hours_since_contact"]) or (absf(float(entry["hours_since_contact"]) - float(old["hours_since_contact"])) <= 0.000001 and float(entry["familiarity"]) > float(old["familiarity"])):
                    relationships[index] = entry
            else:
                relationship_index[subject] = relationships.size()
                relationships.append(entry)
    var relationship_capacity := maxi(1, int(_long_term_config().get("relationship_capacity", 32)))
    while relationships.size() > relationship_capacity:
        _evict_weakest_relationship(relationships)
    relationships.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("subject", "")) < str(b.get("subject", "")))

    var places: Array = []
    var place_index: Dictionary = {}
    var raw_places = source.get("places", [])
    if typeof(raw_places) == TYPE_ARRAY:
        for raw in raw_places:
            var entry := _sanitize_place(raw)
            if entry.is_empty():
                continue
            var place := str(entry["place"])
            if place_index.has(place):
                var index := int(place_index[place])
                var old: Dictionary = places[index]
                if float(entry["hours_since_visit"]) < float(old["hours_since_visit"]) or (absf(float(entry["hours_since_visit"]) - float(old["hours_since_visit"])) <= 0.000001 and float(entry["familiarity"]) > float(old["familiarity"])):
                    places[index] = entry
            else:
                place_index[place] = places.size()
                places.append(entry)
    var place_capacity := maxi(1, int(_long_term_config().get("place_capacity", 16)))
    while places.size() > place_capacity:
        _evict_weakest_place(places)
    places.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("place", "")) < str(b.get("place", "")))
    return {"relationships": relationships, "places": places, "favorite_place": _favorite_place_from(places)}

func reinforce_relationship(subject_value: String, valence: float, importance: float = 0.5) -> bool:
    var subject := _bounded_long_id(subject_value)
    if subject.is_empty():
        return false
    var config := _long_term_config()
    var signal := clampf(valence, -1.0, 1.0)
    var weight := clampf(importance, 0.0, 1.0)
    var alpha := clampf(float(config.get("relationship_learning_rate", 0.35)) * weight, 0.0, 1.0)
    var familiarity_gain := float(config.get("familiarity_gain", 0.18)) * weight
    var normalized := _normalize_long_term_memory(long_term_memory)
    var relationships: Array = normalized.get("relationships", []).duplicate(true)
    var found := false
    for entry in relationships:
        if str(entry.get("subject", "")) != subject:
            continue
        entry["affinity"] = clampf(float(entry.get("affinity", 0.0)) * (1.0 - alpha) + signal * alpha, -1.0, 1.0)
        var familiarity := float(entry.get("familiarity", 0.0))
        entry["familiarity"] = clampf(familiarity + familiarity_gain * (1.0 - familiarity), 0.0, 1.0)
        entry["interactions"] = mini(1000000, int(entry.get("interactions", 0)) + 1)
        entry["hours_since_contact"] = 0.0
        found = true
        break
    if not found:
        relationships.append({
            "subject": subject, "affinity": signal * alpha, "familiarity": clampf(familiarity_gain, 0.0, 1.0),
            "interactions": 1, "hours_since_contact": 0.0,
        })
    long_term_memory = _normalize_long_term_memory({"relationships": relationships, "places": normalized.get("places", [])})
    return true

func remember_place_visit(place_value: String, preference: float = 0.0, importance: float = 0.5) -> bool:
    var place := _bounded_long_id(place_value)
    if place.is_empty():
        return false
    var config := _long_term_config()
    var signal := clampf(preference, -1.0, 1.0)
    var weight := clampf(importance, 0.0, 1.0)
    var alpha := clampf(float(config.get("place_learning_rate", 0.30)) * weight, 0.0, 1.0)
    var familiarity_gain := float(config.get("familiarity_gain", 0.18)) * weight
    var normalized := _normalize_long_term_memory(long_term_memory)
    var places: Array = normalized.get("places", []).duplicate(true)
    var found := false
    for entry in places:
        if str(entry.get("place", "")) != place:
            continue
        entry["preference"] = clampf(float(entry.get("preference", 0.0)) * (1.0 - alpha) + signal * alpha, -1.0, 1.0)
        var familiarity := float(entry.get("familiarity", 0.0))
        entry["familiarity"] = clampf(familiarity + familiarity_gain * (1.0 - familiarity), 0.0, 1.0)
        entry["visits"] = mini(1000000, int(entry.get("visits", 0)) + 1)
        entry["hours_since_visit"] = 0.0
        found = true
        break
    if not found:
        places.append({
            "place": place, "preference": signal * alpha, "familiarity": clampf(familiarity_gain, 0.0, 1.0),
            "visits": 1, "hours_since_visit": 0.0,
        })
    long_term_memory = _normalize_long_term_memory({"relationships": normalized.get("relationships", []), "places": places})
    return true

func clear_long_term_memory() -> void:
    long_term_memory = {"relationships": [], "places": [], "favorite_place": ""}

func long_term_snapshot() -> Dictionary:
    return _normalize_long_term_memory(long_term_memory)

func _step_long_term_memory(delta: float) -> void:
    var hours := clampf(delta, 0.0, 604800.0) / 3600.0
    if hours <= 0.0:
        return
    var config := _long_term_config()
    var normalized := _normalize_long_term_memory(long_term_memory)
    var relationships: Array = normalized.get("relationships", []).duplicate(true)
    for entry in relationships:
        entry["affinity"] = _decay_signed(float(entry.get("affinity", 0.0)), float(config.get("affinity_decay_per_hour", 0.0025)) * hours)
        entry["familiarity"] = maxf(0.0, float(entry.get("familiarity", 0.0)) - float(config.get("familiarity_decay_per_hour", 0.0005)) * hours)
        entry["hours_since_contact"] = minf(1000000.0, float(entry.get("hours_since_contact", 0.0)) + hours)
    var places: Array = normalized.get("places", []).duplicate(true)
    for entry in places:
        entry["preference"] = _decay_signed(float(entry.get("preference", 0.0)), float(config.get("preference_decay_per_hour", 0.0015)) * hours)
        entry["familiarity"] = maxf(0.0, float(entry.get("familiarity", 0.0)) - float(config.get("familiarity_decay_per_hour", 0.0005)) * hours)
        entry["hours_since_visit"] = minf(1000000.0, float(entry.get("hours_since_visit", 0.0)) + hours)
    long_term_memory = _normalize_long_term_memory({"relationships": relationships, "places": places})

func _long_term_bias(context: Dictionary) -> Dictionary:
    var out := _zero_bias()
    var normalized := _normalize_long_term_memory(long_term_memory)
    var config := _long_term_config()
    var subjects := _focused_subjects(context)
    var social_single = context.get("social_subject", null)
    if social_single != null and not str(social_single).is_empty():
        subjects[str(social_single)] = true
    var social_many = context.get("social_subjects", null)
    if typeof(social_many) == TYPE_ARRAY:
        for raw in social_many:
            if not str(raw).is_empty():
                subjects[str(raw)] = true
    var relationship_effects = config.get("relationship_effects", {})
    if typeof(relationship_effects) == TYPE_DICTIONARY:
        for raw in normalized.get("relationships", []):
            var entry: Dictionary = raw
            if not subjects.has(str(entry.get("subject", ""))):
                continue
            var strength := float(entry.get("affinity", 0.0)) * float(entry.get("familiarity", 0.0))
            for raw_state in relationship_effects.keys():
                var state_name := str(raw_state)
                if out.has(state_name):
                    out[state_name] = float(out[state_name]) + strength * float(relationship_effects[raw_state])
    var current_place := _bounded_long_id(context.get("current_place", ""))
    var target_place := _bounded_long_id(context.get("target_place", ""))
    var current_effects = config.get("current_place_effects", {})
    var target_effects = config.get("target_place_effects", {})
    for raw in normalized.get("places", []):
        var entry: Dictionary = raw
        var place := str(entry.get("place", ""))
        var strength := float(entry.get("preference", 0.0)) * float(entry.get("familiarity", 0.0))
        if not current_place.is_empty() and place == current_place and typeof(current_effects) == TYPE_DICTIONARY:
            for raw_state in current_effects.keys():
                var state_name := str(raw_state)
                if out.has(state_name):
                    out[state_name] = float(out[state_name]) + strength * float(current_effects[raw_state])
        if not target_place.is_empty() and place == target_place and typeof(target_effects) == TYPE_DICTIONARY:
            for raw_state in target_effects.keys():
                var state_name := str(raw_state)
                if out.has(state_name):
                    out[state_name] = float(out[state_name]) + strength * float(target_effects[raw_state])
    var favorite := str(normalized.get("favorite_place", ""))
    var home_place := _bounded_long_id(context.get("home_place", ""))
    if bool(context.get("away_from_home", false)) and not favorite.is_empty() and favorite == home_place:
        out["return_home"] = float(out["return_home"]) + float(config.get("favorite_home_return_bonus", 0.16))
    var cap := maxf(0.0, float(config.get("max_abs_state_bias", 0.30)))
    for state_name in out.keys():
        out[state_name] = clampf(float(out[state_name]), -cap, cap)
    return out


func _apply_policy_defaults() -> void:
    var defaults: Dictionary = _policy.get("defaults", {})
    var p: Dictionary = defaults.get("profile", {})
    var n: Dictionary = defaults.get("needs", {})
    mobility = str(p.get("mobility", mobility))
    routine = str(p.get("routine", routine))
    autonomy = clampf(float(p.get("autonomy", autonomy)), 0.0, 1.0)
    wander = clampf(float(p.get("wander", wander)), 0.0, 1.0)
    social_drive = clampf(float(p.get("social", social_drive)), 0.0, 1.0)
    rest_threshold = clampf(float(p.get("rest_threshold", rest_threshold)), 0.0, 1.0)
    curiosity_threshold = clampf(float(p.get("curiosity_threshold", curiosity_threshold)), 0.0, 1.0)
    home_bias = clampf(float(p.get("home_bias", home_bias)), 0.0, 1.0)
    walk_speed = clampf(float(p.get("walk_speed", walk_speed)), 0.05, 4.0)
    traits = _normalized_traits(p.get("traits", {}))
    _rebuild_trait_bias()
    energy = clampf(float(n.get("energy", energy)), 0.0, 1.0)
    comfort = clampf(float(n.get("comfort", comfort)), 0.0, 1.0)
    curiosity = clampf(float(n.get("curiosity", curiosity)), 0.0, 1.0)
    social = clampf(float(n.get("social", social)), 0.0, 1.0)

func apply_snapshot(data: Dictionary) -> void:
    enabled = bool(data.get("enabled", enabled))
    state = str(data.get("state", state))
    var p: Dictionary = data.get("profile", {})
    var n: Dictionary = data.get("needs", {})
    mobility = str(p.get("mobility", mobility))
    if mobility not in _valid_values("mobility", ["auto", "free", "contained", "disabled"]):
        mobility = "auto"
    routine = str(p.get("routine", routine))
    if routine not in _valid_values("routine", ["balanced", "homebody", "explorer", "social"]):
        routine = "balanced"
    autonomy = clampf(float(p.get("autonomy", autonomy)), 0.0, 1.0)
    wander = clampf(float(p.get("wander", wander)), 0.0, 1.0)
    social_drive = clampf(float(p.get("social", social_drive)), 0.0, 1.0)
    rest_threshold = clampf(float(p.get("rest_threshold", rest_threshold)), 0.0, 1.0)
    curiosity_threshold = clampf(float(p.get("curiosity_threshold", curiosity_threshold)), 0.0, 1.0)
    home_bias = clampf(float(p.get("home_bias", home_bias)), 0.0, 1.0)
    walk_speed = clampf(float(p.get("walk_speed", walk_speed)), 0.05, 4.0)
    traits = _normalized_traits(p.get("traits", {}))
    _rebuild_trait_bias()
    energy = clampf(float(n.get("energy", energy)), 0.0, 1.0)
    comfort = clampf(float(n.get("comfort", comfort)), 0.0, 1.0)
    curiosity = clampf(float(n.get("curiosity", curiosity)), 0.0, 1.0)
    social = clampf(float(n.get("social", social)), 0.0, 1.0)
    memory = _normalize_memory(data.get("memory", []))
    long_term_memory = _normalize_long_term_memory(data.get("long_term_memory", {}))
    _memory_elapsed = 0.0
    _rebuild_memory_cache()
    _update_mood()

func activity_scores(context: Dictionary = {}) -> Dictionary:
    var away := bool(context.get("away_from_home", false))
    var interesting := maxf(0.0, float(context.get("interesting_targets", 0.0)))
    var social_targets := maxf(0.0, float(context.get("social_targets", 0.0)))
    var idle := _subsection("utility", "idle")
    var wander_u := _subsection("utility", "wander")
    var inspect := _subsection("utility", "inspect")
    var social_u := _subsection("utility", "social")
    var return_home := _subsection("utility", "return_home")
    var rest := _subsection("utility", "rest")
    var target := _subsection("utility", "target")
    var bonus := _subsection("utility", "routine_bonus")
    var explorer_bonus := float(bonus.get("explorer", 0.18)) if routine == "explorer" else 0.0
    var social_bonus := float(bonus.get("social", 0.18)) if routine == "social" else 0.0
    var home_bonus := float(bonus.get("homebody", 0.20)) if routine == "homebody" else 0.0
    var focused_bias := _focused_memory_bias(context)
    var long_bias := _long_term_bias(context)
    return {
        "idle": float(idle.get("base", 0.20)) + comfort * float(idle.get("comfort", 0.12)) + (1.0 - autonomy) * float(idle.get("inverse_autonomy", 0.18)) + _trait_bias_idle + _combined_memory_bias("idle", focused_bias) + float(long_bias.get("idle", 0.0)),
        "wander": float(wander_u.get("base", 0.16)) + wander * float(wander_u.get("wander", 0.42)) + autonomy * float(wander_u.get("autonomy", 0.20)) + curiosity * float(wander_u.get("curiosity", 0.16)) + explorer_bonus + _trait_bias_wander + _combined_memory_bias("wander", focused_bias) + float(long_bias.get("wander", 0.0)),
        "inspect": float(inspect.get("base", 0.12)) + curiosity * float(inspect.get("curiosity", 0.58)) + minf(float(target.get("cap", 0.18)), interesting * float(target.get("step", 0.06))) + explorer_bonus + _trait_bias_inspect + _combined_memory_bias("inspect", focused_bias) + float(long_bias.get("inspect", 0.0)),
        "social": float(social_u.get("base", 0.10)) + social * float(social_u.get("social_need", 0.48)) + social_drive * float(social_u.get("social_drive", 0.28)) + minf(float(target.get("cap", 0.18)), social_targets * float(target.get("step", 0.06))) + social_bonus + _trait_bias_social + _combined_memory_bias("social", focused_bias) + float(long_bias.get("social", 0.0)),
        "return_home": ((float(return_home.get("base", 0.08)) + home_bias * float(return_home.get("home_bias", 0.35)) + home_bonus + (1.0 - comfort) * float(return_home.get("inverse_comfort", 0.32)) + (1.0 - energy) * float(return_home.get("inverse_energy", 0.26))) if away else 0.0) + _trait_bias_return_home + _combined_memory_bias("return_home", focused_bias) + float(long_bias.get("return_home", 0.0)),
        "rest": float(rest.get("base", 0.12)) + (1.0 - energy) * float(rest.get("inverse_energy", 0.88)) + (float(rest.get("home_bonus", 0.18)) if not away else float(rest.get("away_bonus", -0.25))) + _trait_bias_rest + _combined_memory_bias("rest", focused_bias) + float(long_bias.get("rest", 0.0)),
    }

func _is_bound(context: Dictionary) -> bool:
    if bool(context.get("locked", false)) or bool(context.get("bound", false)):
        return true
    return str(context.get("interaction_mode", "")).to_lower() in _valid_values("bound_modes", ["bound", "anchored", "contained", "restrained"])

func choose_state(context: Dictionary = {}) -> String:
    if not enabled or mobility == "disabled":
        return "disabled"
    if mobility == "contained" or (mobility == "auto" and _is_bound(context)):
        return "contained"
    var away := bool(context.get("away_from_home", false))
    var gates := _section("hard_gates")
    if energy <= rest_threshold:
        return "return_home" if away else "rest"
    if away and comfort < float(gates.get("away_comfort_return", 0.22)):
        return "return_home"
    var scores := activity_scores(context)
    if float(context.get("social_targets", 0.0)) <= 0.0:
        scores["social"] = -1.0
    if float(context.get("interesting_targets", 0.0)) <= 0.0:
        scores["inspect"] = float(scores["inspect"]) * float(gates.get("inspect_no_target_multiplier", 0.82))
    if autonomy < float(gates.get("autonomy_lock", 0.20)):
        scores["wander"] = -1.0
        scores["inspect"] = -1.0
    if energy > maxf(rest_threshold + float(gates.get("rest_energy_margin", 0.20)), float(gates.get("rest_energy_floor", 0.50))):
        scores["rest"] = float(scores["rest"]) * float(gates.get("rest_ready_multiplier", 0.35))
    last_utility = scores.duplicate(true)
    var order = _policy.get("state_order", UTILITY_STATES)
    if typeof(order) != TYPE_ARRAY or order.is_empty():
        order = UTILITY_STATES
    var best := "idle"
    var best_score := -INF
    for raw_name in order:
        var name := str(raw_name)
        var score := float(scores.get(name, -1.0))
        if score > best_score:
            best_score = score
            best = name
    return best

func _apply_rate(rate: Dictionary, minute: float) -> void:
    energy = clampf(energy + float(rate.get("energy", 0.0)) * minute, 0.0, 1.0)
    comfort = clampf(comfort + float(rate.get("comfort", 0.0)) * minute, 0.0, 1.0)
    curiosity = clampf(curiosity + float(rate.get("curiosity", 0.0)) * minute, 0.0, 1.0)
    social = clampf(social + float(rate.get("social", 0.0)) * minute, 0.0, 1.0)

func step(delta: float, context_value: Variant = {}) -> String:
    var context: Dictionary = {}
    if typeof(context_value) == TYPE_DICTIONARY:
        context = context_value
    elif typeof(context_value) == TYPE_BOOL and bool(context_value):
        context = {"bound": true, "interaction_mode": "contained"}
    var clamped_delta := clampf(delta, 0.0, 300.0)
    if not memory.is_empty():
        _memory_elapsed += clamped_delta
        if _memory_elapsed >= _memory_next_expiry:
            _materialize_memory()
            _rebuild_memory_cache()
    _step_long_term_memory(clamped_delta)
    var minute := clamped_delta / 60.0
    state = choose_state(context)
    match state:
        "rest": _apply_rate(_subsection("need_rates_per_minute", "rest"), minute)
        "contained": _apply_rate(_subsection("need_rates_per_minute", "contained"), minute)
        "wander", "inspect", "social", "return_home":
            var selected := _subsection("need_rates_per_minute", "active").duplicate(true)
            if state == "inspect": selected.merge(_subsection("need_rates_per_minute", "inspect_override"), true)
            if state == "social": selected.merge(_subsection("need_rates_per_minute", "social_override"), true)
            _apply_rate(selected, minute)
        _: _apply_rate(_subsection("need_rates_per_minute", "idle"), minute)
    state = choose_state(context)
    _update_mood()
    return state

func _update_mood() -> void:
    var affect := _section("affect_thresholds")
    if state == "rest" or energy < float(affect.get("tired_energy", 0.22)): mood = "tired"
    elif comfort < float(affect.get("uneasy_comfort", 0.28)): mood = "uneasy"
    elif curiosity > float(affect.get("alert_curiosity", 0.78)): mood = "alert"
    elif social > float(affect.get("seeking_social", 0.78)): mood = "seeking_company"
    else: mood = "calm"

func snapshot() -> Dictionary:
    return {
        "state": state,
        "profile": {
            "mobility": mobility, "routine": routine, "autonomy": autonomy,
            "wander": wander, "social": social_drive, "rest_threshold": rest_threshold,
            "curiosity_threshold": curiosity_threshold, "home_bias": home_bias, "walk_speed": walk_speed,
            "traits": traits.duplicate(true),
        },
        "needs": {"energy": energy, "comfort": comfort, "curiosity": curiosity, "social": social},
        "memory": memory_snapshot(),
        "long_term_memory": long_term_snapshot(),
        "affect": {"mood": mood},
        "utility": last_utility.duplicate(true),
    }
