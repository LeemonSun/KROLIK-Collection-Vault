class_name VaultAgentBrain
extends RefCounted

## Realtime mirror of life_sim.py.  Keep formulas and tie-break order aligned so
## editor-side simulation and the Godot world make the same state decisions.

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

var energy := 0.82
var comfort := 0.72
var curiosity := 0.35
var social := 0.45
var mood := "calm"
var last_utility: Dictionary = {}

func apply_snapshot(data: Dictionary) -> void:
    enabled = bool(data.get("enabled", enabled))
    state = str(data.get("state", state))
    var p: Dictionary = data.get("profile", {})
    var n: Dictionary = data.get("needs", {})
    mobility = str(p.get("mobility", mobility))
    if mobility not in ["auto", "free", "contained", "disabled"]:
        mobility = "auto"
    routine = str(p.get("routine", routine))
    if routine not in ["balanced", "homebody", "explorer", "social"]:
        routine = "balanced"
    autonomy = clampf(float(p.get("autonomy", autonomy)), 0.0, 1.0)
    wander = clampf(float(p.get("wander", wander)), 0.0, 1.0)
    social_drive = clampf(float(p.get("social", social_drive)), 0.0, 1.0)
    rest_threshold = clampf(float(p.get("rest_threshold", rest_threshold)), 0.0, 1.0)
    curiosity_threshold = clampf(float(p.get("curiosity_threshold", curiosity_threshold)), 0.0, 1.0)
    home_bias = clampf(float(p.get("home_bias", home_bias)), 0.0, 1.0)
    walk_speed = clampf(float(p.get("walk_speed", walk_speed)), 0.05, 4.0)
    energy = clampf(float(n.get("energy", energy)), 0.0, 1.0)
    comfort = clampf(float(n.get("comfort", comfort)), 0.0, 1.0)
    curiosity = clampf(float(n.get("curiosity", curiosity)), 0.0, 1.0)
    social = clampf(float(n.get("social", social)), 0.0, 1.0)
    _update_mood()

func activity_scores(context: Dictionary = {}) -> Dictionary:
    var away := bool(context.get("away_from_home", false))
    var interesting := maxf(0.0, float(context.get("interesting_targets", 0.0)))
    var social_targets := maxf(0.0, float(context.get("social_targets", 0.0)))
    var explorer_bonus := 0.18 if routine == "explorer" else 0.0
    var social_bonus := 0.18 if routine == "social" else 0.0
    var home_bonus := 0.20 if routine == "homebody" else 0.0
    return {
        "idle": 0.20 + comfort * 0.12 + (1.0 - autonomy) * 0.18,
        "wander": 0.16 + wander * 0.42 + autonomy * 0.20 + curiosity * 0.16 + explorer_bonus,
        "inspect": 0.12 + curiosity * 0.58 + minf(0.18, interesting * 0.06) + explorer_bonus,
        "social": 0.10 + social * 0.48 + social_drive * 0.28 + minf(0.18, social_targets * 0.06) + social_bonus,
        "return_home": (0.08 + home_bias * 0.35 + home_bonus + (1.0 - comfort) * 0.32 + (1.0 - energy) * 0.26) if away else 0.0,
        "rest": 0.12 + (1.0 - energy) * 0.88 + (0.18 if not away else -0.25),
    }

func _is_bound(context: Dictionary) -> bool:
    if bool(context.get("locked", false)) or bool(context.get("bound", false)):
        return true
    return str(context.get("interaction_mode", "")).to_lower() in ["bound", "anchored", "contained", "restrained"]

func choose_state(context: Dictionary = {}) -> String:
    if not enabled or mobility == "disabled":
        return "disabled"
    if mobility == "contained" or (mobility == "auto" and _is_bound(context)):
        return "contained"
    var away := bool(context.get("away_from_home", false))
    if energy <= rest_threshold:
        return "return_home" if away else "rest"
    if away and comfort < 0.22:
        return "return_home"

    var scores := activity_scores(context)
    if float(context.get("social_targets", 0.0)) <= 0.0:
        scores["social"] = -1.0
    if float(context.get("interesting_targets", 0.0)) <= 0.0:
        scores["inspect"] = float(scores["inspect"]) * 0.82
    if autonomy < 0.2:
        scores["wander"] = -1.0
        scores["inspect"] = -1.0
    if energy > maxf(rest_threshold + 0.20, 0.50):
        scores["rest"] = float(scores["rest"]) * 0.35
    last_utility = scores.duplicate(true)

    var order := ["return_home", "rest", "social", "inspect", "wander", "idle"]
    var best := "idle"
    var best_score := -INF
    for name in order:
        var score := float(scores.get(name, -1.0))
        if score > best_score:
            best_score = score
            best = name
    return best

func step(delta: float, context_value: Variant = {}) -> String:
    var context: Dictionary = {}
    if typeof(context_value) == TYPE_DICTIONARY:
        context = context_value
    elif typeof(context_value) == TYPE_BOOL and bool(context_value):
        context = {"bound": true, "interaction_mode": "contained"}
    var minute := clampf(delta, 0.0, 300.0) / 60.0
    state = choose_state(context)
    match state:
        "rest":
            energy = clampf(energy + 0.055 * minute, 0.0, 1.0)
            comfort = clampf(comfort + 0.018 * minute, 0.0, 1.0)
            curiosity = clampf(curiosity + 0.012 * minute, 0.0, 1.0)
        "contained":
            energy = clampf(energy - 0.004 * minute, 0.0, 1.0)
            comfort = clampf(comfort - 0.006 * minute, 0.0, 1.0)
            curiosity = clampf(curiosity + 0.020 * minute, 0.0, 1.0)
            social = clampf(social + 0.010 * minute, 0.0, 1.0)
        "wander", "inspect", "social", "return_home":
            energy = clampf(energy - 0.018 * minute, 0.0, 1.0)
            comfort = clampf(comfort - 0.004 * minute, 0.0, 1.0)
            curiosity = clampf(curiosity - (0.028 if state == "inspect" else 0.008) * minute, 0.0, 1.0)
            social = clampf(social - (0.025 if state == "social" else 0.003) * minute, 0.0, 1.0)
        _:
            energy = clampf(energy - 0.005 * minute, 0.0, 1.0)
            curiosity = clampf(curiosity + 0.008 * minute, 0.0, 1.0)
            social = clampf(social + 0.005 * minute, 0.0, 1.0)
    state = choose_state(context)
    _update_mood()
    return state

func _update_mood() -> void:
    if state == "rest" or energy < 0.22:
        mood = "tired"
    elif comfort < 0.28:
        mood = "uneasy"
    elif curiosity > 0.78:
        mood = "alert"
    elif social > 0.78:
        mood = "seeking_company"
    else:
        mood = "calm"

func snapshot() -> Dictionary:
    return {
        "state": state,
        "profile": {
            "mobility": mobility, "routine": routine, "autonomy": autonomy,
            "wander": wander, "social": social_drive, "rest_threshold": rest_threshold,
            "curiosity_threshold": curiosity_threshold, "home_bias": home_bias, "walk_speed": walk_speed,
        },
        "needs": {"energy": energy, "comfort": comfort, "curiosity": curiosity, "social": social},
        "affect": {"mood": mood},
        "utility": last_utility.duplicate(true),
    }
