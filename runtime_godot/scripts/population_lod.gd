class_name VaultPopulationLOD
extends Node

## Distance-based population sleeping for large Vault scenes.
##
## Full agents keep the existing VaultCharacterAgent path unchanged. Far agents
## are hidden and have physics processing disabled. Their semantic brain state is
## advanced once when they wake, so needs/memory time is not silently lost.
## A small hysteresis band avoids sleep/wake thrashing near the threshold.

var enabled := true
var focus_position := Vector2.ZERO
var sleep_radius := 720.0
var wake_radius := 640.0
var reassess_interval := 0.25

var _elapsed := 0.0
var _entries: Dictionary = {}

func configure(doc: Dictionary = {}) -> void:
    enabled = bool(doc.get("enabled", enabled))
    sleep_radius = maxf(1.0, float(doc.get("sleep_radius", sleep_radius)))
    wake_radius = clampf(float(doc.get("wake_radius", wake_radius)), 0.0, sleep_radius)
    reassess_interval = clampf(float(doc.get("reassess_interval", reassess_interval)), 0.05, 5.0)
    var raw_focus = doc.get("focus_position", focus_position)
    if typeof(raw_focus) == TYPE_VECTOR2:
        focus_position = raw_focus
    elif typeof(raw_focus) == TYPE_DICTIONARY:
        focus_position = Vector2(float(raw_focus.get("x", 0.0)), float(raw_focus.get("y", 0.0)))
    force_reassess()

func set_focus_position(value: Vector2, reassess_now: bool = false) -> void:
    focus_position = value
    if reassess_now:
        force_reassess()

func register_agent(agent: VaultCharacterAgent) -> bool:
    if agent == null or not is_instance_valid(agent):
        return false
    var key := agent.get_instance_id()
    if _entries.has(key):
        return true
    _entries[key] = {
        "agent": agent,
        "sleeping": false,
        "sleep_started_usec": 0,
        "saved_collision_layer": agent.collision_layer,
        "saved_collision_mask": agent.collision_mask,
    }
    _evaluate_entry(_entries[key], Time.get_ticks_usec())
    return true

func unregister_agent(agent: VaultCharacterAgent, wake_before_remove: bool = true) -> bool:
    if agent == null:
        return false
    var key := agent.get_instance_id()
    if not _entries.has(key):
        return false
    var entry: Dictionary = _entries[key]
    if wake_before_remove and bool(entry.get("sleeping", false)) and is_instance_valid(agent):
        _wake_entry(entry, Time.get_ticks_usec())
    _entries.erase(key)
    return true

func clear(wake_agents: bool = true) -> void:
    var now := Time.get_ticks_usec()
    if wake_agents:
        for key in _entries.keys():
            var entry: Dictionary = _entries[key]
            var agent: VaultCharacterAgent = entry.get("agent")
            if agent != null and is_instance_valid(agent) and bool(entry.get("sleeping", false)):
                _wake_entry(entry, now)
    _entries.clear()

func registered_count() -> int:
    return _entries.size()

func sleeping_count() -> int:
    var count := 0
    for entry_value in _entries.values():
        var entry: Dictionary = entry_value
        var agent: VaultCharacterAgent = entry.get("agent")
        if agent != null and is_instance_valid(agent) and bool(entry.get("sleeping", false)):
            count += 1
    return count

func active_count() -> int:
    return registered_count() - sleeping_count()

func tier_snapshot() -> Dictionary:
    return {
        "registered": registered_count(),
        "active": active_count(),
        "sleeping": sleeping_count(),
        "focus": focus_position,
        "sleep_radius": sleep_radius,
        "wake_radius": wake_radius,
        "reassess_interval": reassess_interval,
    }

func is_sleeping(agent: VaultCharacterAgent) -> bool:
    if agent == null:
        return false
    var entry = _entries.get(agent.get_instance_id(), null)
    return typeof(entry) == TYPE_DICTIONARY and bool(entry.get("sleeping", false))

func force_reassess() -> void:
    _elapsed = 0.0
    _prune_invalid()
    if not enabled:
        var now_disabled := Time.get_ticks_usec()
        for entry_value in _entries.values():
            var entry: Dictionary = entry_value
            if bool(entry.get("sleeping", false)):
                _wake_entry(entry, now_disabled)
        return
    var now := Time.get_ticks_usec()
    for entry_value in _entries.values():
        _evaluate_entry(entry_value, now)

func _physics_process(delta: float) -> void:
    if not enabled or _entries.is_empty():
        return
    _elapsed += maxf(0.0, delta)
    if _elapsed < reassess_interval:
        return
    _elapsed = fmod(_elapsed, reassess_interval)
    force_reassess()

func _prune_invalid() -> void:
    var dead: Array = []
    for key in _entries.keys():
        var entry: Dictionary = _entries[key]
        var agent: VaultCharacterAgent = entry.get("agent")
        if agent == null or not is_instance_valid(agent):
            dead.append(key)
    for key in dead:
        _entries.erase(key)

func _evaluate_entry(entry: Dictionary, now_usec: int) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return
    var sleeping := bool(entry.get("sleeping", false))
    var distance := agent.global_position.distance_to(focus_position)
    if sleeping:
        if distance <= wake_radius:
            _wake_entry(entry, now_usec)
    elif distance >= sleep_radius:
        _sleep_entry(entry, now_usec)

func _sleep_entry(entry: Dictionary, now_usec: int) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent) or bool(entry.get("sleeping", false)):
        return
    entry["saved_collision_layer"] = agent.collision_layer
    entry["saved_collision_mask"] = agent.collision_mask
    entry["sleep_started_usec"] = now_usec
    entry["sleeping"] = true
    agent.velocity = Vector2.ZERO
    agent.collision_layer = 0
    agent.collision_mask = 0
    agent.visible = false
    agent.set_physics_process(false)

func _wake_entry(entry: Dictionary, now_usec: int) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent) or not bool(entry.get("sleeping", false)):
        return
    var started := int(entry.get("sleep_started_usec", now_usec))
    var slept_seconds := clampf(float(maxi(0, now_usec - started)) / 1000000.0, 0.0, 300.0)
    if slept_seconds > 0.0:
        var context := {
            "bound": agent.contained,
            "interaction_mode": "contained" if agent.contained else "",
            "away_from_home": agent.global_position.distance_to(agent.home_position) > 36.0,
            "interesting_targets": float(agent.world_targets.size()),
            "social_targets": 0.0,
        }
        agent.brain.state = agent.brain.step(slept_seconds, context)
        agent.phase += slept_seconds
    agent.collision_layer = int(entry.get("saved_collision_layer", 1))
    agent.collision_mask = int(entry.get("saved_collision_mask", 1))
    agent.visible = true
    agent.set_physics_process(true)
    entry["sleep_started_usec"] = 0
    entry["sleeping"] = false
