class_name VaultPopulationLOD
extends Node

## Distance-based population LOD for large Vault scenes.
##
## full: production VaultCharacterAgent behavior is untouched.
## reduced: AI + locomotion stay live, but expensive deformable skin/collision
##          proxies and procedural face/secondary layers are suspended; a cheap
##          flat proxy remains visible and follows the agent's root animation.
## sleep: render, physics and collision are suspended. Simulation time is
##        accumulated deterministically from physics delta and applied to the
##        semantic brain once the agent wakes, preserving needs/memory aging.

const TIER_FULL := "full"
const TIER_REDUCED := "reduced"
const TIER_SLEEP := "sleep"

var enabled := true
var focus_position := Vector2.ZERO
var full_radius := 320.0
var sleep_radius := 720.0
var wake_radius := 640.0
var reassess_interval := 0.25

var _elapsed := 0.0
var _entries: Dictionary = {}

func configure(doc: Dictionary = {}) -> void:
    enabled = bool(doc.get("enabled", enabled))
    sleep_radius = maxf(1.0, float(doc.get("sleep_radius", sleep_radius)))
    full_radius = clampf(float(doc.get("full_radius", full_radius)), 0.0, sleep_radius)
    wake_radius = clampf(float(doc.get("wake_radius", wake_radius)), full_radius, sleep_radius)
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
        "tier": TIER_FULL,
        "sleep_source_tier": TIER_FULL,
        "sleep_elapsed": 0.0,
        "saved_collision_layer": agent.collision_layer,
        "saved_collision_mask": agent.collision_mask,
        "saved_facial_enabled": agent.facial_state.enabled,
        "saved_secondary_enabled": agent.secondary_motion_enabled,
        "saved_skinned_visual": null,
        "saved_collision_rig": null,
        "reduced_proxy": null,
    }
    _evaluate_entry(_entries[key])
    return true

func unregister_agent(agent: VaultCharacterAgent, restore_full_before_remove: bool = true) -> bool:
    if agent == null:
        return false
    var key := agent.get_instance_id()
    if not _entries.has(key):
        return false
    var entry: Dictionary = _entries[key]
    if restore_full_before_remove and is_instance_valid(agent):
        _restore_entry_full(entry)
    _entries.erase(key)
    return true

func clear(restore_full: bool = true) -> void:
    if restore_full:
        for key in _entries.keys():
            var entry: Dictionary = _entries[key]
            var agent: VaultCharacterAgent = entry.get("agent")
            if agent != null and is_instance_valid(agent):
                _restore_entry_full(entry)
    _entries.clear()

func registered_count() -> int:
    return _entries.size()

func tier_for(agent: VaultCharacterAgent) -> String:
    if agent == null:
        return ""
    var entry = _entries.get(agent.get_instance_id(), null)
    if typeof(entry) != TYPE_DICTIONARY:
        return ""
    return str(entry.get("tier", TIER_FULL))

func is_sleeping(agent: VaultCharacterAgent) -> bool:
    return tier_for(agent) == TIER_SLEEP

func is_reduced(agent: VaultCharacterAgent) -> bool:
    return tier_for(agent) == TIER_REDUCED

func sleeping_count() -> int:
    return _tier_count(TIER_SLEEP)

func reduced_count() -> int:
    return _tier_count(TIER_REDUCED)

func full_count() -> int:
    return _tier_count(TIER_FULL)

func active_count() -> int:
    return full_count() + reduced_count()

func _tier_count(name: String) -> int:
    var count := 0
    for entry_value in _entries.values():
        var entry: Dictionary = entry_value
        var agent: VaultCharacterAgent = entry.get("agent")
        if agent != null and is_instance_valid(agent) and str(entry.get("tier", "")) == name:
            count += 1
    return count

func tier_snapshot() -> Dictionary:
    return {
        "registered": registered_count(),
        "active": active_count(),
        "full": full_count(),
        "reduced": reduced_count(),
        "sleeping": sleeping_count(),
        "focus": focus_position,
        "full_radius": full_radius,
        "sleep_radius": sleep_radius,
        "wake_radius": wake_radius,
        "reassess_interval": reassess_interval,
    }

func force_reassess() -> void:
    _elapsed = 0.0
    _prune_invalid()
    if not enabled:
        for entry_value in _entries.values():
            _restore_entry_full(entry_value)
        return
    _reassess_all()

func _physics_process(delta: float) -> void:
    if _entries.is_empty():
        return
    var simulation_delta := clampf(delta, 0.0, 1.0)
    for entry_value in _entries.values():
        var entry: Dictionary = entry_value
        if str(entry.get("tier", TIER_FULL)) == TIER_SLEEP:
            entry["sleep_elapsed"] = minf(300.0, float(entry.get("sleep_elapsed", 0.0)) + simulation_delta)
    if not enabled:
        return
    _elapsed += simulation_delta
    if _elapsed < reassess_interval:
        return
    _elapsed = fmod(_elapsed, reassess_interval)
    _prune_invalid()
    _reassess_all()

func _reassess_all() -> void:
    for entry_value in _entries.values():
        _evaluate_entry(entry_value)

func _prune_invalid() -> void:
    var dead: Array = []
    for key in _entries.keys():
        var entry: Dictionary = _entries[key]
        var agent: VaultCharacterAgent = entry.get("agent")
        if agent == null or not is_instance_valid(agent):
            dead.append(key)
    for key in dead:
        _entries.erase(key)

func _target_awake_tier(distance: float) -> String:
    return TIER_FULL if distance <= full_radius else TIER_REDUCED

func _evaluate_entry(entry: Dictionary) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return
    var tier := str(entry.get("tier", TIER_FULL))
    var distance := agent.global_position.distance_to(focus_position)
    if tier == TIER_SLEEP:
        if distance <= wake_radius:
            _wake_entry(entry, _target_awake_tier(distance))
        return
    if distance >= sleep_radius:
        _enter_sleep(entry)
    elif distance <= full_radius:
        _enter_full(entry)
    else:
        _enter_reduced(entry)

func _make_reduced_proxy(agent: VaultCharacterAgent) -> Sprite2D:
    if agent.character_texture == null or agent.visual_root == null:
        return null
    var proxy := Sprite2D.new()
    proxy.name = "LODReducedProxy"
    proxy.texture = agent.character_texture
    proxy.centered = true
    proxy.position = Vector2(0.0, -agent.character_texture.get_height() * 0.5)
    agent.visual_root.add_child(proxy)
    return proxy

func _enter_reduced(entry: Dictionary) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return
    var tier := str(entry.get("tier", TIER_FULL))
    if tier == TIER_REDUCED:
        return
    if tier == TIER_SLEEP:
        _wake_entry(entry, TIER_REDUCED)
        return

    entry["saved_collision_layer"] = agent.collision_layer
    entry["saved_collision_mask"] = agent.collision_mask
    entry["saved_facial_enabled"] = agent.facial_state.enabled
    entry["saved_secondary_enabled"] = agent.secondary_motion_enabled
    entry["saved_skinned_visual"] = agent.skinned_visual
    entry["saved_collision_rig"] = agent.collision_rig

    var saved_rig = entry.get("saved_collision_rig")
    if saved_rig != null:
        saved_rig.set_enabled(false)
    agent.collision_layer = 0
    agent.collision_mask = 0
    agent.collision_rig = null

    var saved_skin = entry.get("saved_skinned_visual")
    if saved_skin != null and is_instance_valid(saved_skin):
        saved_skin.visible = false
        var proxy := _make_reduced_proxy(agent)
        entry["reduced_proxy"] = proxy
        agent.skinned_visual = null

    agent.facial_state.enabled = false
    agent.secondary_motion_enabled = false
    entry["tier"] = TIER_REDUCED

func _enter_full(entry: Dictionary) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return
    var tier := str(entry.get("tier", TIER_FULL))
    if tier == TIER_FULL:
        return
    if tier == TIER_SLEEP:
        _wake_entry(entry, TIER_FULL)
        return

    var proxy = entry.get("reduced_proxy")
    if proxy != null and is_instance_valid(proxy):
        proxy.queue_free()
    entry["reduced_proxy"] = null

    var saved_skin = entry.get("saved_skinned_visual")
    if saved_skin != null and is_instance_valid(saved_skin):
        agent.skinned_visual = saved_skin
        saved_skin.visible = true
        if not agent.solved_joints.is_empty():
            saved_skin.apply_joint_pose(agent.solved_joints)
    entry["saved_skinned_visual"] = null

    var saved_rig = entry.get("saved_collision_rig")
    if saved_rig != null:
        agent.collision_rig = saved_rig
        saved_rig.set_enabled(true)
        if not agent.solved_joints.is_empty():
            saved_rig.apply_joint_pose(agent.solved_joints, agent.texture_scale, agent.facing)
    entry["saved_collision_rig"] = null

    agent.facial_state.enabled = bool(entry.get("saved_facial_enabled", true))
    agent.secondary_motion_enabled = bool(entry.get("saved_secondary_enabled", agent.secondary_motion_enabled))
    agent.collision_layer = int(entry.get("saved_collision_layer", 1))
    agent.collision_mask = int(entry.get("saved_collision_mask", 1))
    entry["tier"] = TIER_FULL

func _enter_sleep(entry: Dictionary) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return
    var tier := str(entry.get("tier", TIER_FULL))
    if tier == TIER_SLEEP:
        return
    entry["sleep_source_tier"] = tier
    entry["sleep_elapsed"] = 0.0
    if tier == TIER_FULL:
        entry["saved_collision_layer"] = agent.collision_layer
        entry["saved_collision_mask"] = agent.collision_mask
        if agent.collision_rig != null:
            agent.collision_rig.set_enabled(false)
        agent.collision_layer = 0
        agent.collision_mask = 0
    agent.velocity = Vector2.ZERO
    agent.visible = false
    agent.set_physics_process(false)
    entry["tier"] = TIER_SLEEP

func _semantic_context(agent: VaultCharacterAgent) -> Dictionary:
    return {
        "bound": agent.contained,
        "interaction_mode": "contained" if agent.contained else "",
        "away_from_home": agent.global_position.distance_to(agent.home_position) > 36.0,
        "interesting_targets": float(agent.world_targets.size()),
        "social_targets": 0.0,
    }

func _wake_entry(entry: Dictionary, target_tier: String) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent) or str(entry.get("tier", "")) != TIER_SLEEP:
        return
    var slept_seconds := clampf(float(entry.get("sleep_elapsed", 0.0)), 0.0, 300.0)
    if slept_seconds > 0.0:
        agent.brain.state = agent.brain.step(slept_seconds, _semantic_context(agent))
        agent.phase += slept_seconds

    var source_tier := str(entry.get("sleep_source_tier", TIER_FULL))
    entry["tier"] = source_tier
    entry["sleep_elapsed"] = 0.0
    agent.visible = true
    agent.set_physics_process(true)

    if source_tier == TIER_FULL:
        agent.collision_layer = int(entry.get("saved_collision_layer", 1))
        agent.collision_mask = int(entry.get("saved_collision_mask", 1))
        if agent.collision_rig != null:
            agent.collision_rig.set_enabled(true)

    if target_tier == TIER_FULL:
        _enter_full(entry)
    else:
        _enter_reduced(entry)

func _restore_entry_full(entry: Dictionary) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return
    var tier := str(entry.get("tier", TIER_FULL))
    if tier == TIER_SLEEP:
        _wake_entry(entry, TIER_FULL)
    elif tier == TIER_REDUCED:
        _enter_full(entry)
    else:
        agent.visible = true
        agent.set_physics_process(true)
        agent.collision_layer = int(entry.get("saved_collision_layer", agent.collision_layer))
        agent.collision_mask = int(entry.get("saved_collision_mask", agent.collision_mask))
        if agent.collision_rig != null:
            agent.collision_rig.set_enabled(true)
