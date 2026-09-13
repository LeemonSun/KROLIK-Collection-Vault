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

func choose_state(contained: bool) -> String:
    if not enabled or mobility == "disabled":
        return "disabled"
    if mobility == "contained" or (mobility == "auto" and contained):
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
