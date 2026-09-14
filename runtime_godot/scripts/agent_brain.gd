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

var policy_loaded := false
var policy_source := "fallback"
var _policy: Dictionary = {}

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
    for key in ["defaults", "valid", "hard_gates", "utility", "trait_effects", "need_rates_per_minute", "affect_thresholds"]:
        if typeof(doc.get(key, null)) != TYPE_DICTIONARY:
            return {}
    if typeof(doc.get("state_order", null)) != TYPE_ARRAY:
        return {}
    _default_policy_cache = doc
    return _default_policy_cache

func configure_policy(doc: Dictionary, source: String = "runtime") -> bool:
    if str(doc.get("schema", "")) != POLICY_SCHEMA or int(doc.get("format_version", 0)) != POLICY_FORMAT_VERSION:
        return false
    for key in ["defaults", "valid", "hard_gates", "utility", "trait_effects", "need_rates_per_minute", "affect_thresholds"]:
        if typeof(doc.get(key, null)) != TYPE_DICTIONARY:
            return false
    if typeof(doc.get("state_order", null)) != TYPE_ARRAY:
        return false
    _policy = doc.duplicate(true)
    policy_loaded = true
    policy_source = source
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

func _trait_delta(name: String) -> float:
    return clampf(float(traits.get(name, 0.5)), 0.0, 1.0) - 0.5

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
    energy = clampf(float(n.get("energy", energy)), 0.0, 1.0)
    comfort = clampf(float(n.get("comfort", comfort)), 0.0, 1.0)
    curiosity = clampf(float(n.get("curiosity", curiosity)), 0.0, 1.0)
    social = clampf(float(n.get("social", social)), 0.0, 1.0)
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
    var scores := {
        "idle": float(idle.get("base", 0.20)) + comfort * float(idle.get("comfort", 0.12)) + (1.0 - autonomy) * float(idle.get("inverse_autonomy", 0.18)),
        "wander": float(wander_u.get("base", 0.16)) + wander * float(wander_u.get("wander", 0.42)) + autonomy * float(wander_u.get("autonomy", 0.20)) + curiosity * float(wander_u.get("curiosity", 0.16)) + explorer_bonus,
        "inspect": float(inspect.get("base", 0.12)) + curiosity * float(inspect.get("curiosity", 0.58)) + minf(float(target.get("cap", 0.18)), interesting * float(target.get("step", 0.06))) + explorer_bonus,
        "social": float(social_u.get("base", 0.10)) + social * float(social_u.get("social_need", 0.48)) + social_drive * float(social_u.get("social_drive", 0.28)) + minf(float(target.get("cap", 0.18)), social_targets * float(target.get("step", 0.06))) + social_bonus,
        "return_home": (float(return_home.get("base", 0.08)) + home_bias * float(return_home.get("home_bias", 0.35)) + home_bonus + (1.0 - comfort) * float(return_home.get("inverse_comfort", 0.32)) + (1.0 - energy) * float(return_home.get("inverse_energy", 0.26))) if away else 0.0,
        "rest": float(rest.get("base", 0.12)) + (1.0 - energy) * float(rest.get("inverse_energy", 0.88)) + (float(rest.get("home_bonus", 0.18)) if not away else float(rest.get("away_bonus", -0.25))),
    }
    var trait_effects := _section("trait_effects")
    for raw_name in trait_effects.keys():
        var name := str(raw_name)
        var effects = trait_effects[raw_name]
        if typeof(effects) != TYPE_DICTIONARY:
            continue
        var delta := _trait_delta(name)
        for raw_state in effects.keys():
            var state_name := str(raw_state)
            if scores.has(state_name):
                scores[state_name] = float(scores[state_name]) + delta * float(effects[raw_state])
    return scores

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
    var order = _policy.get("state_order", ["return_home", "rest", "social", "inspect", "wander", "idle"])
    if typeof(order) != TYPE_ARRAY or order.is_empty():
        order = ["return_home", "rest", "social", "inspect", "wander", "idle"]
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
    var minute := clampf(delta, 0.0, 300.0) / 60.0
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
        "affect": {"mood": mood},
        "utility": last_utility.duplicate(true),
    }
