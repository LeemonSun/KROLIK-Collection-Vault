extends SceneTree

## Rendered 500-agent LOD stress using multiple distinct runtime packages/textures.
## This closes the gap left by the single-package scale benchmark: repeated agents
## no longer share one character texture/cache entry across the entire population.

const AgentScript = preload("res://scripts/character_agent.gd")
const TRAIT_NAMES: Array[String] = ["curiosity", "sociability", "boldness", "patience", "resilience"]

var _agent_count := 500
var _warmup_frames := 30
var _sample_frames := 120
var _max_sample_seconds := 90.0
var _manifest_paths: Array[String] = []
var _screenshot_path := "res://windows_multi_art_artifacts/stress_multi_art_500.png"
var _full_radius := 180.0
var _sleep_radius := 360.0
var _wake_radius := 330.0
var _proxy_max_height := 160

var _world: Node2D
var _lod: VaultPopulationLOD
var _agents: Array[VaultCharacterAgent] = []
var _start_positions: Dictionary = {}
var _spawn_error := ""

func _initialize() -> void:
    call_deferred("_run")

func _env_int(name: String, fallback: int, min_value: int, max_value: int) -> int:
    var raw: String = OS.get_environment(name).strip_edges()
    if raw.is_empty() or not raw.is_valid_int():
        return fallback
    return clampi(int(raw), min_value, max_value)

func _env_float(name: String, fallback: float, min_value: float, max_value: float) -> float:
    var raw: String = OS.get_environment(name).strip_edges()
    if raw.is_empty() or not raw.is_valid_float():
        return fallback
    return clampf(float(raw), min_value, max_value)

func _load_config() -> void:
    _agent_count = _env_int("KROLIK_MULTI_ART_AGENTS", 500, 1, 1000)
    _warmup_frames = _env_int("KROLIK_MULTI_ART_WARMUP_FRAMES", 30, 0, 600)
    _sample_frames = _env_int("KROLIK_MULTI_ART_SAMPLE_FRAMES", 120, 1, 3600)
    _max_sample_seconds = _env_float("KROLIK_MULTI_ART_MAX_SECONDS", 90.0, 0.1, 300.0)
    _full_radius = _env_float("KROLIK_MULTI_ART_FULL_RADIUS", 180.0, 1.0, 5000.0)
    _sleep_radius = _env_float("KROLIK_MULTI_ART_SLEEP_RADIUS", 360.0, _full_radius, 10000.0)
    _wake_radius = _env_float("KROLIK_MULTI_ART_WAKE_RADIUS", 330.0, _full_radius, _sleep_radius)
    _proxy_max_height = _env_int("KROLIK_MULTI_ART_PROXY_MAX_HEIGHT", 160, 48, 512)
    var screenshot_env: String = OS.get_environment("KROLIK_MULTI_ART_SCREENSHOT_PATH").strip_edges()
    if not screenshot_env.is_empty():
        _screenshot_path = screenshot_env

    _manifest_paths.clear()
    var manifest_env: String = OS.get_environment("KROLIK_MULTI_ART_MANIFEST_PATHS").strip_edges()
    for raw_path in manifest_env.split(";", false):
        var clean_path := str(raw_path).strip_edges()
        if not clean_path.is_empty():
            _manifest_paths.append(clean_path)

func _absolute_path(path: String) -> String:
    if path.begins_with("res://") or path.begins_with("user://"):
        return ProjectSettings.globalize_path(path)
    return path

func _traits_for(index: int) -> Dictionary:
    var out := {
        "curiosity": 0.5,
        "sociability": 0.5,
        "boldness": 0.5,
        "patience": 0.5,
        "resilience": 0.5,
    }
    out[TRAIT_NAMES[index % TRAIT_NAMES.size()]] = 0.8
    return out

func _mind_for(index: int) -> Dictionary:
    return {
        "enabled": true,
        "state": "wander",
        "profile": {
            "mobility": "free",
            "routine": "explorer",
            "autonomy": 1.0,
            "wander": 1.0,
            "walk_speed": 1.0,
            "traits": _traits_for(index),
        },
        "needs": {"energy": 1.0, "comfort": 0.7, "curiosity": 1.0, "social": 0.35},
        "memory": [{
            "kind": "interesting",
            "subject": "multi-art-stress-%03d" % index,
            "valence": 0.2,
            "importance": 0.5,
            "age": 0.0,
            "ttl": 600.0,
        }],
    }

func _spawn_point(index: int, columns: int) -> Vector2:
    var row := index / columns
    var col := index % columns
    return Vector2(36.0 + col * 34.0, 52.0 + row * 40.0)

func _world_focus(columns: int) -> Vector2:
    var rows := int(ceil(float(_agent_count) / float(maxi(columns, 1))))
    var min_point := Vector2(36.0, 52.0)
    var max_point := Vector2(
        36.0 + float(maxi(columns - 1, 0)) * 34.0,
        52.0 + float(maxi(rows - 1, 0)) * 40.0
    )
    return (min_point + max_point) * 0.5

func _spawn_agents() -> void:
    _world = Node2D.new()
    _world.name = "MultiArtLODStressWorld"
    root.add_child(_world)
    _agents.clear()
    _start_positions.clear()
    _spawn_error = ""

    if _manifest_paths.size() < 2:
        _spawn_error = "multi-art benchmark requires at least two runtime manifests"
        return
    var absolute_manifests: Array[String] = []
    for path in _manifest_paths:
        var absolute := _absolute_path(path)
        if absolute.is_empty() or not FileAccess.file_exists(absolute):
            _spawn_error = "runtime manifest missing: " + absolute
            return
        absolute_manifests.append(absolute)

    var columns := maxi(1, int(ceil(sqrt(float(_agent_count) * 2.2))))
    var focus := _world_focus(columns)
    _lod = VaultPopulationLOD.new()
    _world.add_child(_lod)
    _lod.configure({
        "enabled": true,
        "resource_residency": true,
        "focus_position": focus,
        "full_radius": _full_radius,
        "sleep_radius": _sleep_radius,
        "wake_radius": _wake_radius,
        "proxy_max_height": _proxy_max_height,
        "reassess_interval": 0.10,
    })

    for i in range(_agent_count):
        var spawn := _spawn_point(i, columns)
        var manifest_abs: String = absolute_manifests[i % absolute_manifests.size()]
        var needs_full_resources := spawn.distance_to(focus) <= _full_radius
        var agent := AgentScript.new() as VaultCharacterAgent
        _world.add_child(agent)
        var mind := _mind_for(i)
        agent.setup("multi_art_%03d" % i, spawn, mind)
        if not agent.load_runtime_manifest(manifest_abs, needs_full_resources):
            _spawn_error = "runtime manifest rejected for multi-art agent %d" % i
            return
        agent.character_id = "multi_art_%03d" % i
        agent.brain.apply_snapshot(mind)
        agent.position = spawn
        agent.home_position = spawn
        agent.target_position = spawn
        agent.collision_layer = 0
        agent.collision_mask = 0
        var direction := -1.0 if (i % 2) == 0 else 1.0
        var target := spawn + Vector2(direction * 96.0, 24.0 + float(i % 3) * 8.0)
        agent.target_position = target
        agent.world_targets = [target]
        _agents.append(agent)
        _start_positions[agent.get_instance_id()] = spawn
        if not _lod.register_agent(agent, manifest_abs):
            _spawn_error = "failed to register multi-art LOD agent %d" % i
            return

    _lod.force_reassess()

func _wait_physics_frames(count: int) -> void:
    for _i in range(count):
        await physics_frame

func _capture_render_evidence() -> Dictionary:
    await process_frame
    var viewport := root.get_viewport()
    if viewport == null or viewport.get_texture() == null:
        return {"saved": false, "sampled_foreground": 0, "error": "viewport texture unavailable"}
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return {"saved": false, "sampled_foreground": 0, "error": "viewport image empty"}
    var reference := image.get_pixel(0, 0)
    var foreground := 0
    var stride := 4
    for y in range(0, image.get_height(), stride):
        for x in range(0, image.get_width(), stride):
            var c := image.get_pixel(x, y)
            var delta := absf(c.r - reference.r) + absf(c.g - reference.g) + absf(c.b - reference.b)
            if delta > 0.08:
                foreground += 1
    var output_path := _screenshot_path
    if output_path.begins_with("res://") or output_path.begins_with("user://"):
        output_path = ProjectSettings.globalize_path(output_path)
    var dir_err := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
    if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
        return {"saved": false, "sampled_foreground": foreground, "error": "unable to create screenshot folder"}
    var save_err := image.save_png(output_path)
    return {
        "saved": save_err == OK,
        "sampled_foreground": foreground,
        "path": output_path,
        "width": image.get_width(),
        "height": image.get_height(),
        "error": "" if save_err == OK else "save_png=" + str(save_err),
    }

func _run() -> void:
    _load_config()
    VaultRuntimePackageCache.reset_cache()
    _spawn_agents()
    if not _spawn_error.is_empty():
        push_error("KROLIK MULTI ART scale: " + _spawn_error)
        quit(11)
        return

    await _wait_physics_frames(_warmup_frames)
    var sleeping_positions: Dictionary = {}
    for agent in _agents:
        if _lod.is_sleeping(agent):
            sleeping_positions[agent.get_instance_id()] = agent.global_position

    var started_usec := Time.get_ticks_usec()
    await _wait_physics_frames(_sample_frames)
    var elapsed := float(Time.get_ticks_usec() - started_usec) / 1000000.0
    var fps := float(_sample_frames) / maxf(elapsed, 0.000001)
    var tiers := _lod.tier_snapshot()

    var awake := 0
    var awake_moved := 0
    var sleeping_drift_max := 0.0
    var residency_shape_errors := 0
    var ai_policy_active := 0
    var memory_active := 0
    var package_counts: Dictionary = {}
    for i in range(_agents.size()):
        var agent: VaultCharacterAgent = _agents[i]
        if not is_instance_valid(agent):
            continue
        var package_index := i % _manifest_paths.size()
        package_counts[package_index] = int(package_counts.get(package_index, 0)) + 1
        if agent.brain.policy_loaded:
            ai_policy_active += 1
        if not agent.brain.memory_snapshot().is_empty():
            memory_active += 1
        var tier := _lod.tier_for(agent)
        var resource_mode := _lod.resource_mode_for(agent)
        if tier == VaultPopulationLOD.TIER_FULL:
            if resource_mode != VaultPopulationLOD.RESIDENT or agent.skinned_visual == null or agent.collision_rig == null:
                residency_shape_errors += 1
        elif tier == VaultPopulationLOD.TIER_REDUCED:
            if resource_mode != VaultPopulationLOD.PROXY or agent.skinned_visual != null or agent.collision_rig != null or agent.character_texture == null:
                residency_shape_errors += 1
        elif tier == VaultPopulationLOD.TIER_SLEEP:
            if resource_mode != VaultPopulationLOD.RELEASED or agent.character_texture != null or agent.skinned_visual != null or agent.collision_rig != null:
                residency_shape_errors += 1

        var start: Vector2 = _start_positions.get(agent.get_instance_id(), agent.global_position)
        if tier != VaultPopulationLOD.TIER_SLEEP:
            awake += 1
            if agent.global_position.distance_to(start) >= 8.0:
                awake_moved += 1
        elif sleeping_positions.has(agent.get_instance_id()):
            var before: Vector2 = sleeping_positions[agent.get_instance_id()]
            sleeping_drift_max = maxf(sleeping_drift_max, agent.global_position.distance_to(before))

    var awake_moved_share := float(awake_moved) / float(maxi(awake, 1))
    var cache := VaultRuntimePackageCache.stats_snapshot()
    var renderer_name := RenderingServer.get_video_adapter_name()
    var static_mib := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
    var static_max_mib := float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576.0
    var render_evidence := await _capture_render_evidence()

    print("KROLIK_MULTI_ART_SCALE_METRIC agents=%d unique_packages=%d full=%d reduced=%d sleeping=%d resident=%d proxy=%d released=%d sample_frames=%d sample_seconds=%.4f sim_fps=%.2f awake=%d awake_moved=%d awake_moved_share=%.3f sleep_drift_max=%.3f cache_entries=%d cache_texture_entries=%d cache_limit=%d cache_parses=%d cache_decodes=%d cache_evictions=%d cache_hits=%d static_mib=%.2f static_max_mib=%.2f renderer=%s" % [
        _agent_count, _manifest_paths.size(), int(tiers.get("full", 0)), int(tiers.get("reduced", 0)), int(tiers.get("sleeping", 0)), int(tiers.get("resident", 0)), int(tiers.get("proxy", 0)), int(tiers.get("released", 0)), _sample_frames, elapsed, fps, awake, awake_moved, awake_moved_share, sleeping_drift_max, int(cache.get("entries", 0)), int(cache.get("texture_entries", 0)), int(cache.get("texture_limit", 0)), int(cache.get("manifest_parses", 0)), int(cache.get("texture_decodes", 0)), int(cache.get("texture_evictions", 0)), int(cache.get("hits", 0)), static_mib, static_max_mib, renderer_name
    ])
    print("KROLIK_MULTI_ART_RENDER saved=%s foreground=%d width=%d height=%d path=%s" % [
        str(bool(render_evidence.get("saved", false))), int(render_evidence.get("sampled_foreground", 0)), int(render_evidence.get("width", 0)), int(render_evidence.get("height", 0)), str(render_evidence.get("path", ""))
    ])

    if int(tiers.get("registered", 0)) != _agent_count:
        push_error("KROLIK MULTI ART scale: registered population mismatch"); quit(2); return
    if int(tiers.get("full", 0)) <= 0 or int(tiers.get("reduced", 0)) <= 0 or int(tiers.get("sleeping", 0)) <= 0:
        push_error("KROLIK MULTI ART scale: all LOD tiers must be populated"); quit(3); return
    if residency_shape_errors != 0:
        push_error("KROLIK MULTI ART scale: residency shape errors=%d" % residency_shape_errors); quit(4); return
    if ai_policy_active != _agent_count or memory_active != _agent_count:
        push_error("KROLIK MULTI ART scale: AI/memory population mismatch"); quit(5); return
    if awake_moved_share < 0.95:
        push_error("KROLIK MULTI ART scale: awake movement share too low %.3f" % awake_moved_share); quit(6); return
    if sleeping_drift_max > 0.01:
        push_error("KROLIK MULTI ART scale: sleeping agents drifted %.3f" % sleeping_drift_max); quit(7); return
    var cache_entries := int(cache.get("entries", 0))
    var cache_texture_entries := int(cache.get("texture_entries", 0))
    var cache_texture_limit := int(cache.get("texture_limit", 0))
    var cache_decodes := int(cache.get("texture_decodes", 0))
    if cache_entries != _manifest_paths.size() or int(cache.get("manifest_parses", 0)) != _manifest_paths.size():
        push_error("KROLIK MULTI ART scale: manifest cache shape mismatch: " + str(cache)); quit(8); return
    if cache_texture_limit <= 0 or cache_texture_entries > cache_texture_limit:
        push_error("KROLIK MULTI ART scale: decoded texture cache exceeded its bound: " + str(cache)); quit(13); return
    if cache_decodes > awake:
        push_error("KROLIK MULTI ART scale: full texture decodes exceeded awake population: " + str(cache)); quit(14); return
    if _manifest_paths.size() > cache_texture_limit and cache_decodes >= _manifest_paths.size():
        push_error("KROLIK MULTI ART scale: lazy texture decode did not reduce unique-package residency: " + str(cache)); quit(15); return
    for package_index in range(_manifest_paths.size()):
        if int(package_counts.get(package_index, 0)) <= 0:
            push_error("KROLIK MULTI ART scale: package %d received no agents" % package_index); quit(9); return
    if elapsed > _max_sample_seconds:
        push_error("KROLIK MULTI ART scale: sample exceeded time ceiling %.3f" % elapsed); quit(10); return
    if not bool(render_evidence.get("saved", false)) or int(render_evidence.get("sampled_foreground", 0)) < 20:
        push_error("KROLIK MULTI ART scale: render evidence invalid " + str(render_evidence)); quit(12); return

    _lod.clear(false)
    _world.queue_free()
    await process_frame
    quit(0)
