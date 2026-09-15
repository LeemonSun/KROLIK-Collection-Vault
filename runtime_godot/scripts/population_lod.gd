class_name VaultPopulationLOD
extends Node

## Distance-based population LOD for large Vault scenes.
##
## full: production VaultCharacterAgent behavior is untouched.
## reduced: AI + locomotion stay live, but deformable skin/collision/face/secondary
##          are replaced by a small flat proxy.
## sleep: render + physics are suspended and visual resources may be released.
##
## When a sealed runtime manifest path is available, reduced/sleep tiers use
## resource residency: full textures/skin/collision are actually released and
## reconstructed from the runtime package on wake. If no manifest is available,
## the manager falls back to the older hide/suspend behavior for compatibility.

const TIER_FULL := "full"
const TIER_REDUCED := "reduced"
const TIER_SLEEP := "sleep"

const RESIDENT := "resident"
const PROXY := "proxy"
const RELEASED := "released"
const LEGACY := "legacy"

var enabled := true
var resource_residency_enabled := true
var focus_position := Vector2.ZERO
var full_radius := 320.0
var sleep_radius := 720.0
var wake_radius := 640.0
var reassess_interval := 0.25
var proxy_max_height := 160
var default_manifest_path := ""

var _elapsed := 0.0
var _entries: Dictionary = {}

func configure(doc: Dictionary = {}) -> void:
    enabled = bool(doc.get("enabled", enabled))
    resource_residency_enabled = bool(doc.get("resource_residency", resource_residency_enabled))
    sleep_radius = maxf(1.0, float(doc.get("sleep_radius", sleep_radius)))
    full_radius = clampf(float(doc.get("full_radius", full_radius)), 0.0, sleep_radius)
    wake_radius = clampf(float(doc.get("wake_radius", wake_radius)), full_radius, sleep_radius)
    reassess_interval = clampf(float(doc.get("reassess_interval", reassess_interval)), 0.05, 5.0)
    proxy_max_height = clampi(int(doc.get("proxy_max_height", proxy_max_height)), 48, 512)
    default_manifest_path = str(doc.get("runtime_manifest_path", default_manifest_path)).strip_edges()
    if default_manifest_path.is_empty():
        default_manifest_path = OS.get_environment("KROLIK_LOD_MANIFEST_PATH").strip_edges()
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

func register_agent(agent: VaultCharacterAgent, runtime_manifest_path: String = "") -> bool:
    if agent == null or not is_instance_valid(agent):
        return false
    var key := agent.get_instance_id()
    if _entries.has(key):
        return true
    var manifest_path := runtime_manifest_path.strip_edges()
    if manifest_path.is_empty():
        manifest_path = default_manifest_path
    var can_reside := resource_residency_enabled and not manifest_path.is_empty() and FileAccess.file_exists(manifest_path)
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
        "manifest_path": manifest_path,
        "resource_residency": can_reside,
        "resource_mode": RESIDENT if can_reside else LEGACY,
        "last_error": "",
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

func resource_mode_for(agent: VaultCharacterAgent) -> String:
    if agent == null:
        return ""
    var entry = _entries.get(agent.get_instance_id(), null)
    if typeof(entry) != TYPE_DICTIONARY:
        return ""
    return str(entry.get("resource_mode", LEGACY))

func pending_sleep_seconds(agent: VaultCharacterAgent) -> float:
    if agent == null:
        return 0.0
    var entry = _entries.get(agent.get_instance_id(), null)
    if typeof(entry) != TYPE_DICTIONARY:
        return 0.0
    return float(entry.get("sleep_elapsed", 0.0))

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

func _resource_count(name: String) -> int:
    var count := 0
    for entry_value in _entries.values():
        var entry: Dictionary = entry_value
        var agent: VaultCharacterAgent = entry.get("agent")
        if agent != null and is_instance_valid(agent) and str(entry.get("resource_mode", "")) == name:
            count += 1
    return count

func _error_count() -> int:
    var count := 0
    for entry_value in _entries.values():
        var entry: Dictionary = entry_value
        if not str(entry.get("last_error", "")).is_empty():
            count += 1
    return count

func tier_snapshot() -> Dictionary:
    return {
        "registered": registered_count(),
        "active": active_count(),
        "full": full_count(),
        "reduced": reduced_count(),
        "sleeping": sleeping_count(),
        "resident": _resource_count(RESIDENT),
        "proxy": _resource_count(PROXY),
        "released": _resource_count(RELEASED),
        "legacy": _resource_count(LEGACY),
        "residency_failures": _error_count(),
        "focus": focus_position,
        "full_radius": full_radius,
        "sleep_radius": sleep_radius,
        "wake_radius": wake_radius,
        "reassess_interval": reassess_interval,
        "proxy_max_height": proxy_max_height,
    }

func entry_snapshot(agent: VaultCharacterAgent) -> Dictionary:
    if agent == null:
        return {}
    var entry = _entries.get(agent.get_instance_id(), null)
    if typeof(entry) != TYPE_DICTIONARY:
        return {}
    return {
        "tier": str(entry.get("tier", TIER_FULL)),
        "sleep_source_tier": str(entry.get("sleep_source_tier", TIER_FULL)),
        "sleep_elapsed": float(entry.get("sleep_elapsed", 0.0)),
        "resource_mode": str(entry.get("resource_mode", LEGACY)),
        "manifest_path": str(entry.get("manifest_path", "")),
        "last_error": str(entry.get("last_error", "")),
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

func _uses_residency(entry: Dictionary) -> bool:
    return bool(entry.get("resource_residency", false))

func _mark_error(entry: Dictionary, message: String) -> void:
    entry["last_error"] = message

func _ensure_visual_root(agent: VaultCharacterAgent) -> Node2D:
    if agent.visual_root != null and is_instance_valid(agent.visual_root):
        return agent.visual_root
    var root_node := Node2D.new()
    root_node.name = "CharacterVisual"
    agent.add_child(root_node)
    agent.visual_root = root_node
    return root_node

func _clear_runtime_visuals(agent: VaultCharacterAgent, clear_texture: bool = true) -> void:
    if agent.collision_rig != null:
        agent.collision_rig.clear()
        agent.collision_rig = null
    if agent.visual_root != null and is_instance_valid(agent.visual_root):
        for child in agent.visual_root.get_children():
            agent.visual_root.remove_child(child)
            child.queue_free()
    agent.skinned_visual = null
    agent.flat_sprite = null
    if clear_texture:
        agent.character_texture = null
    agent.queue_redraw()

func _manifest_image_path(manifest_path: String) -> String:
    if manifest_path.is_empty() or not FileAccess.file_exists(manifest_path):
        return ""
    var file := FileAccess.open(manifest_path, FileAccess.READ)
    if file == null:
        return ""
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return ""
    var visual: Dictionary = parsed.get("visual", {})
    var image_name := str(visual.get("file", "character.png"))
    if image_name.is_empty() or image_name.get_file() != image_name:
        return ""
    return manifest_path.get_base_dir().path_join(image_name)

func _proxy_payload(entry: Dictionary) -> Dictionary:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return {}
    var image: Image = null
    if agent.character_texture != null:
        image = agent.character_texture.get_image()
    if image == null or image.is_empty():
        var image_path := _manifest_image_path(str(entry.get("manifest_path", "")))
        if image_path.is_empty():
            return {}
        image = Image.new()
        if image.load(image_path) != OK:
            return {}
    if image.is_empty():
        return {}
    var original_size := Vector2(image.get_width(), image.get_height())
    var proxy_image := image.duplicate()
    if proxy_image.get_height() > proxy_max_height:
        var scale := float(proxy_max_height) / float(maxi(1, proxy_image.get_height()))
        var target_width := maxi(1, int(round(float(proxy_image.get_width()) * scale)))
        proxy_image.resize(target_width, proxy_max_height, Image.INTERPOLATE_BILINEAR)
    var texture := ImageTexture.create_from_image(proxy_image)
    if texture == null:
        return {}
    return {"texture": texture, "original_size": original_size}

func _install_resident_proxy(entry: Dictionary) -> bool:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return false
    var payload := _proxy_payload(entry)
    if payload.is_empty():
        _mark_error(entry, "unable to build reduced proxy texture")
        return false
    var texture: Texture2D = payload.get("texture")
    var original_size: Vector2 = payload.get("original_size", Vector2.ONE)
    _clear_runtime_visuals(agent, true)
    agent.character_texture = texture
    var root_node := _ensure_visual_root(agent)
    var proxy := Sprite2D.new()
    proxy.name = "LODReducedProxy"
    proxy.texture = texture
    proxy.centered = true
    var proxy_size := texture.get_size()
    proxy.position = Vector2(0.0, -original_size.y * 0.5)
    proxy.scale = Vector2(
        original_size.x / maxf(1.0, proxy_size.x),
        original_size.y / maxf(1.0, proxy_size.y)
    )
    root_node.add_child(proxy)
    entry["reduced_proxy"] = proxy
    entry["resource_mode"] = PROXY
    entry["last_error"] = ""
    agent._apply_visual_transform()
    return true

func _release_resident_resources(entry: Dictionary) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return
    _clear_runtime_visuals(agent, true)
    entry["reduced_proxy"] = null
    entry["resource_mode"] = RELEASED

func _restore_resident_full(entry: Dictionary) -> bool:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return false
    var manifest_path := str(entry.get("manifest_path", ""))
    if manifest_path.is_empty() or not FileAccess.file_exists(manifest_path):
        _mark_error(entry, "runtime manifest missing during wake: " + manifest_path)
        return false

    var brain_snapshot := agent.brain.snapshot()
    var live_character_id := agent.character_id
    var live_position := agent.position
    var live_home := agent.home_position
    var live_target := agent.target_position
    var live_world_targets := agent.world_targets.duplicate()
    var live_contained := agent.contained
    var live_facing := agent.facing
    var live_phase := agent.phase
    var live_velocity := agent.velocity

    if not agent.load_runtime_manifest(manifest_path):
        _mark_error(entry, "runtime manifest reload failed: " + manifest_path)
        return false

    agent.character_id = live_character_id
    agent.brain.apply_snapshot(brain_snapshot)
    agent.position = live_position
    agent.home_position = live_home
    agent.target_position = live_target
    agent.world_targets = live_world_targets
    agent.contained = live_contained
    agent.facing = live_facing
    agent.phase = live_phase
    agent.velocity = live_velocity
    agent.facial_state.enabled = bool(entry.get("saved_facial_enabled", agent.facial_state.enabled))
    agent.secondary_motion_enabled = bool(entry.get("saved_secondary_enabled", agent.secondary_motion_enabled))
    agent.collision_layer = int(entry.get("saved_collision_layer", 1))
    agent.collision_mask = int(entry.get("saved_collision_mask", 1))
    entry["reduced_proxy"] = null
    entry["resource_mode"] = RESIDENT
    entry["last_error"] = ""
    agent._apply_visual_transform()
    return agent.skinned_visual != null and is_instance_valid(agent.skinned_visual) and agent.collision_rig != null

func _make_legacy_proxy(agent: VaultCharacterAgent) -> Sprite2D:
    if agent.character_texture == null:
        return null
    var root_node := _ensure_visual_root(agent)
    var proxy := Sprite2D.new()
    proxy.name = "LODReducedProxy"
    proxy.texture = agent.character_texture
    proxy.centered = true
    proxy.position = Vector2(0.0, -agent.character_texture.get_height() * 0.5)
    root_node.add_child(proxy)
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

    if _uses_residency(entry):
        agent.collision_layer = 0
        agent.collision_mask = 0
        agent.facial_state.enabled = false
        agent.secondary_motion_enabled = false
        if not _install_resident_proxy(entry):
            # A malformed package must not destroy the currently working visual.
            # Disable aggressive residency for this entry and fall back to legacy.
            entry["resource_residency"] = false
            entry["resource_mode"] = LEGACY
        else:
            entry["tier"] = TIER_REDUCED
            return

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
        entry["reduced_proxy"] = _make_legacy_proxy(agent)
        agent.skinned_visual = null
    agent.facial_state.enabled = false
    agent.secondary_motion_enabled = false
    entry["tier"] = TIER_REDUCED

func _enter_full(entry: Dictionary) -> void:
    var agent: VaultCharacterAgent = entry.get("agent")
    if agent == null or not is_instance_valid(agent):
        return
    var tier := str(entry.get("tier", TIER_FULL))
    if tier == TIER_FULL and str(entry.get("resource_mode", RESIDENT)) in [RESIDENT, LEGACY]:
        return
    if tier == TIER_SLEEP:
        _wake_entry(entry, TIER_FULL)
        return

    if _uses_residency(entry):
        if not _restore_resident_full(entry):
            return
        entry["tier"] = TIER_FULL
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

    if _uses_residency(entry):
        if tier == TIER_FULL:
            entry["saved_collision_layer"] = agent.collision_layer
            entry["saved_collision_mask"] = agent.collision_mask
            entry["saved_facial_enabled"] = agent.facial_state.enabled
            entry["saved_secondary_enabled"] = agent.secondary_motion_enabled
        agent.collision_layer = 0
        agent.collision_mask = 0
        agent.facial_state.enabled = false
        agent.secondary_motion_enabled = false
        _release_resident_resources(entry)
    elif tier == TIER_FULL:
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
    entry["sleep_elapsed"] = 0.0
    agent.visible = true
    agent.set_physics_process(true)

    if _uses_residency(entry):
        if target_tier == TIER_FULL:
            if _restore_resident_full(entry):
                entry["tier"] = TIER_FULL
            else:
                agent.visible = false
                agent.set_physics_process(false)
                entry["tier"] = TIER_SLEEP
        else:
            agent.collision_layer = 0
            agent.collision_mask = 0
            agent.facial_state.enabled = false
            agent.secondary_motion_enabled = false
            if _install_resident_proxy(entry):
                entry["tier"] = TIER_REDUCED
            else:
                agent.visible = false
                agent.set_physics_process(false)
                entry["tier"] = TIER_SLEEP
        return

    var source_tier := str(entry.get("sleep_source_tier", TIER_FULL))
    entry["tier"] = source_tier
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
    elif _uses_residency(entry) and str(entry.get("resource_mode", RESIDENT)) != RESIDENT:
        _restore_resident_full(entry)
    else:
        agent.visible = true
        agent.set_physics_process(true)
        agent.collision_layer = int(entry.get("saved_collision_layer", agent.collision_layer))
        agent.collision_mask = int(entry.get("saved_collision_mask", agent.collision_mask))
        if agent.collision_rig != null:
            agent.collision_rig.set_enabled(true)
