class_name VaultAffinityState
extends RefCounted

## Bounded event-driven long-term affinity/favorite-place state.
## Lookups are rebuilt only when records change; utility reads are O(1).

const VALID_KINDS := ["character", "place"]
const UTILITY_STATES := ["idle", "wander", "inspect", "social", "return_home", "rest"]

var config: Dictionary = {}
var records: Array = []
var _characters: Dictionary = {}
var _places: Dictionary = {}
var _favorite_place := ""

func configure(value: Dictionary) -> bool:
    for key in [
        "character_capacity", "place_capacity", "max_subject_length",
        "learning_rate", "familiarity_gain", "decay_per_hour",
        "familiarity_decay_per_hour", "drop_epsilon", "max_abs_state_bias",
        "character_social_weight", "place_wander_weight", "place_inspect_weight",
        "home_return_weight", "favorite_min_affinity",
    ]:
        if not value.has(key):
            return false
    config = value.duplicate(true)
    records = _normalize(records)
    _rebuild_cache()
    return true

func _capacity(kind: String) -> int:
    if kind == "character":
        return clampi(int(config.get("character_capacity", 16)), 1, 128)
    return clampi(int(config.get("place_capacity", 8)), 1, 64)

func _sanitize(raw: Variant) -> Dictionary:
    if typeof(raw) != TYPE_DICTIONARY:
        return {}
    var source: Dictionary = raw
    var kind := str(source.get("kind", ""))
    if kind not in VALID_KINDS:
        return {}
    var max_len := clampi(int(config.get("max_subject_length", 64)), 1, 256)
    var subject := str(source.get("subject", ""))
    if subject.is_empty():
        return {}
    if subject.length() > max_len:
        subject = subject.substr(0, max_len)
    return {
        "kind": kind,
        "subject": subject,
        "affinity": clampf(float(source.get("affinity", 0.0)), -1.0, 1.0),
        "familiarity": clampf(float(source.get("familiarity", 0.0)), 0.0, 1.0),
    }

func _retention(record: Dictionary) -> float:
    return absf(float(record.get("affinity", 0.0))) * 0.70 + float(record.get("familiarity", 0.0)) * 0.30

func _evict_kind(values: Array, kind: String) -> Array:
    var out := values.duplicate(true)
    while true:
        var count := 0
        for raw in out:
            if typeof(raw) == TYPE_DICTIONARY and str(raw.get("kind", "")) == kind:
                count += 1
        if count <= _capacity(kind):
            return out
        var victim := -1
        var victim_retention := INF
        var victim_familiarity := INF
        var victim_affinity := INF
        var victim_subject := ""
        for index in range(out.size()):
            var record: Dictionary = out[index]
            if str(record.get("kind", "")) != kind:
                continue
            var retention := _retention(record)
            var familiarity := float(record.get("familiarity", 0.0))
            var affinity_abs := absf(float(record.get("affinity", 0.0)))
            var subject := str(record.get("subject", ""))
            var better_victim := victim < 0 or retention < victim_retention - 0.000001
            if not better_victim and absf(retention - victim_retention) <= 0.000001:
                better_victim = familiarity < victim_familiarity - 0.000001
                if not better_victim and absf(familiarity - victim_familiarity) <= 0.000001:
                    better_victim = affinity_abs < victim_affinity - 0.000001
                    if not better_victim and absf(affinity_abs - victim_affinity) <= 0.000001:
                        better_victim = victim_subject.is_empty() or subject < victim_subject
            if better_victim:
                victim = index
                victim_retention = retention
                victim_familiarity = familiarity
                victim_affinity = affinity_abs
                victim_subject = subject
        if victim < 0:
            return out
        out.remove_at(victim)

func _normalize(raw_value: Variant) -> Array:
    if typeof(raw_value) != TYPE_ARRAY:
        return []
    var out: Array = []
    var index_by_key: Dictionary = {}
    for raw in raw_value:
        var record := _sanitize(raw)
        if record.is_empty():
            continue
        var key := str(record["kind"]) + "\u001f" + str(record["subject"])
        if index_by_key.has(key):
            var index := int(index_by_key[key])
            var existing: Dictionary = out[index]
            var replace := float(record["familiarity"]) > float(existing["familiarity"]) + 0.000001
            if not replace and absf(float(record["familiarity"]) - float(existing["familiarity"])) <= 0.000001:
                replace = absf(float(record["affinity"])) > absf(float(existing["affinity"]))
            if replace:
                out[index] = record
        else:
            index_by_key[key] = out.size()
            out.append(record)
    out = _evict_kind(out, "character")
    out = _evict_kind(out, "place")
    return out

func apply_snapshot(value: Variant) -> void:
    records = _normalize(value)
    _rebuild_cache()

func _rebuild_cache() -> void:
    _characters.clear()
    _places.clear()
    _favorite_place = ""
    var favorite_score := -INF
    var favorite_familiarity := -INF
    var favorite_min := clampf(float(config.get("favorite_min_affinity", 0.20)), -1.0, 1.0)
    for raw in records:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var record: Dictionary = raw
        var kind := str(record.get("kind", ""))
        var subject := str(record.get("subject", ""))
        if kind == "character":
            _characters[subject] = record.duplicate(true)
        elif kind == "place":
            _places[subject] = record.duplicate(true)
            var affinity := float(record.get("affinity", 0.0))
            var familiarity := float(record.get("familiarity", 0.0))
            if affinity < favorite_min:
                continue
            var score := affinity * (0.5 + 0.5 * familiarity)
            var better := score > favorite_score + 0.000001
            if not better and absf(score - favorite_score) <= 0.000001:
                better = familiarity > favorite_familiarity + 0.000001
                if not better and absf(familiarity - favorite_familiarity) <= 0.000001:
                    better = _favorite_place.is_empty() or subject < _favorite_place
            if better:
                favorite_score = score
                favorite_familiarity = familiarity
                _favorite_place = subject

func learn(kind: String, subject: String, signal: float) -> bool:
    var candidate := _sanitize({"kind": kind, "subject": subject})
    if candidate.is_empty():
        return false
    var signal_f := clampf(signal, -1.0, 1.0)
    var learning_rate := maxf(0.0, float(config.get("learning_rate", 0.20)))
    var familiarity_gain := maxf(0.0, float(config.get("familiarity_gain", 0.08)))
    var found := false
    for index in range(records.size()):
        var record: Dictionary = records[index]
        if str(record.get("kind", "")) == kind and str(record.get("subject", "")) == str(candidate["subject"]):
            record["affinity"] = clampf(float(record.get("affinity", 0.0)) + signal_f * learning_rate, -1.0, 1.0)
            record["familiarity"] = clampf(float(record.get("familiarity", 0.0)) + absf(signal_f) * familiarity_gain, 0.0, 1.0)
            records[index] = record
            found = true
            break
    if not found:
        candidate["affinity"] = clampf(signal_f * learning_rate, -1.0, 1.0)
        candidate["familiarity"] = clampf(absf(signal_f) * familiarity_gain, 0.0, 1.0)
        records.append(candidate)
    records = _evict_kind(records, kind)
    _rebuild_cache()
    return true

func decay(elapsed_hours: float) -> void:
    var hours := clampf(elapsed_hours, 0.0, 24.0 * 365.0)
    if hours <= 0.0 or records.is_empty():
        return
    var affinity_factor := maxf(0.0, 1.0 - maxf(0.0, float(config.get("decay_per_hour", 0.001))) * hours)
    var familiarity_factor := maxf(0.0, 1.0 - maxf(0.0, float(config.get("familiarity_decay_per_hour", 0.0002))) * hours)
    var epsilon := clampf(float(config.get("drop_epsilon", 0.01)), 0.0, 1.0)
    var kept: Array = []
    for raw in records:
        var record: Dictionary = raw.duplicate(true)
        record["affinity"] = clampf(float(record.get("affinity", 0.0)) * affinity_factor, -1.0, 1.0)
        record["familiarity"] = clampf(float(record.get("familiarity", 0.0)) * familiarity_factor, 0.0, 1.0)
        if absf(float(record["affinity"])) <= epsilon and float(record["familiarity"]) <= epsilon:
            continue
        kept.append(record)
    records = kept
    _rebuild_cache()

func _strength(record: Variant) -> float:
    if typeof(record) != TYPE_DICTIONARY:
        return 0.0
    return float(record.get("affinity", 0.0)) * float(record.get("familiarity", 0.0))

func utility_bias(context: Dictionary = {}) -> Dictionary:
    var out := {
        "idle": 0.0, "wander": 0.0, "inspect": 0.0,
        "social": 0.0, "return_home": 0.0, "rest": 0.0,
    }
    var social_subject := str(context.get("social_subject", ""))
    if not social_subject.is_empty() and _characters.has(social_subject):
        out["social"] = _strength(_characters[social_subject]) * float(config.get("character_social_weight", 0.30))
    var place_subject := str(context.get("place_subject", ""))
    if not place_subject.is_empty() and _places.has(place_subject):
        var place_strength := _strength(_places[place_subject])
        out["wander"] = place_strength * float(config.get("place_wander_weight", 0.12))
        out["inspect"] = place_strength * float(config.get("place_inspect_weight", 0.08))
    var home_subject := str(context.get("home_place_subject", ""))
    if bool(context.get("away_from_home", false)) and not home_subject.is_empty() and _places.has(home_subject):
        out["return_home"] = _strength(_places[home_subject]) * float(config.get("home_return_weight", 0.20))
    var cap := maxf(0.0, float(config.get("max_abs_state_bias", 0.30)))
    for state_name in UTILITY_STATES:
        out[state_name] = clampf(float(out[state_name]), -cap, cap)
    return out

func favorite_place() -> String:
    return _favorite_place

func snapshot() -> Array:
    return records.duplicate(true)

func size() -> int:
    return records.size()
