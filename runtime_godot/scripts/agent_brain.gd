class_name VaultAgentBrain
extends RefCounted

var enabled := true
var state := "idle"
var mobility := "auto"
var autonomy := 0.75
var wander := 0.65
var social_drive := 0.45
var rest_threshold := 0.24
var energy := 0.82
var comfort := 0.72
var curiosity := 0.35
var social := 0.45
var mood := "calm"

func apply_snapshot(data: Dictionary) -> void:
    enabled = bool(data.get("enabled", enabled))
    state = str(data.get("state", state))
    var p: Dictionary = data.get("profile", {})
    var n: Dictionary = data.get("needs", {})
    mobility = str(p.get("mobility", mobility))
    autonomy = clampf(float(p.get("autonomy", autonomy)), 0.0, 1.0)
    wander = clampf(float(p.get("wander", wander)), 0.0, 1.0)
    social_drive = clampf(float(p.get("social", social_drive)), 0.0, 1.0)
    rest_threshold = clampf(float(p.get("rest_threshold", rest_threshold)), 0.0, 1.0)
    energy = clampf(float(n.get("energy", energy)), 0.0, 1.0)
    comfort = clampf(float(n.get("comfort", comfort)), 0.0, 1.0)
    curiosity = clampf(float(n.get("curiosity", curiosity)), 0.0, 1.0)
    social = clampf(float(n.get("social", social)), 0.0, 1.0)
    _update_mood()

func step(delta: float, is_contained: bool) -> String:
    var minute := clampf(delta, 0.0, 5.0) / 60.0
    state = choose_state(is_contained)
    match state:
        "rest":
            energy = clampf(energy + 0.055 * minute, 0.0, 1.0)
            comfort = clampf(comfort + 0.018 * minute, 0.0, 1.0)
        "contained":
            energy = clampf(energy - 0.004 * minute, 0.0, 1.0)
            comfort = clampf(comfort - 0.006 * minute, 0.0, 1.0)
            curiosity = clampf(curiosity + 0.020 * minute, 0.0, 1.0)
        "wander", "inspect", "social", "return_home":
            energy = clampf(energy - 0.018 * minute, 0.0, 1.0)
            curiosity = clampf(curiosity - (0.028 if state == "inspect" else 0.008) * minute, 0.0, 1.0)
            social = clampf(social - (0.025 if state == "social" else 0.003) * minute, 0.0, 1.0)
        _:
            energy = clampf(energy - 0.005 * minute, 0.0, 1.0)
            curiosity = clampf(curiosity + 0.008 * minute, 0.0, 1.0)
            social = clampf(social + 0.005 * minute, 0.0, 1.0)
    state = choose_state(is_contained)
    _update_mood()
    return state

func choose_state(is_contained: bool) -> String:
    if not enabled or mobility == "disabled":
        return "disabled"
    if mobility == "contained" or (mobility == "auto" and is_contained):
        return "contained"
    if energy <= rest_threshold:
        return "rest"
    if curiosity >= 0.72 and autonomy > 0.2:
        return "inspect"
    if social >= 0.76 and social_drive >= 0.45:
        return "social"
    if wander >= 0.35 and autonomy >= 0.35:
        return "wander"
    return "idle"

func _update_mood() -> void:
    if energy < 0.22:
        mood = "tired"
    elif comfort < 0.28:
        mood = "uneasy"
    elif curiosity > 0.78:
        mood = "alert"
    elif social > 0.78:
        mood = "seeking_company"
    else:
        mood = "calm"
