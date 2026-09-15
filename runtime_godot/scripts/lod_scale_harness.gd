extends SceneTree

## Production-like rendered scale benchmark for the three-tier population LOD.
## It intentionally mirrors stress_harness.gd's character/mind/animation workload,
## then adds VaultPopulationLOD over the same production runtime package.

const AgentScript = preload("res://scripts/character_agent.gd")
const TRAIT_NAMES := ["curiosity", "sociability", "boldness", "patience", "resilience"]

var _agent_count := 500
var _warmup_frames := 30
var _sample_frames := 120
var _max_sample_seconds := 60.0
var _manifest_path := "res://.ci_windows_lod/exports/runtime/ci_core_slice/manifest.json"
var _screenshot_path := "res://windows_lod_artifacts/stress_lod_500.png"
var _full_radius := 180.0
var _sleep_radius := 360.0
var _wake_radius := 330.0

var _world: Node2D
var _lod: VaultPopulationLOD
var _agents: Array[VaultCharacterAgent] = []
var _start_positions: Dictionary = {}
var _spawn_error := ""

func _initialize() -> void:
    call_deferred("_run")

func _env_int(name: String, fallback: int, min_value: int, max_value: int) -> int:
    var raw := OS.get_environment(name).strip_edges()
    if raw.is_empty() or not raw.is_valid_int():
        return fallback
    return clampi(int(raw), min_value, max_value)

func _env_float(name: String, fallback: float, min_value: float, max_value: float) -> float:
    var raw := OS.get_environment(name).strip_edges()
    if raw.is_empty() or not raw.is_valid_float():
        return fallback
    return clampf(float(raw), min_value, max_value)

func _load_config() -> void:
    _agent_count = _env_int("KROLIK_LOD_AGENTS", 500, 1, 1000)
    _warmup_frames = _env_int("KROLIK_LOD_WARMUP_FRAMES", 30, 0, 600)
    _sample_frames = _env_int("KROLIK_LOD_SAMPLE_FRAMES", 120, 1, 3600)
    _max_sample_seconds = _env_float("KROLIK_LOD_MAX_SECONDS", 60.0, 0.1, 300.0)
    _full_radius = _env_float("KROLIK_LOD_FULL_RADIUS", 180.0, 1.0, 5000.0)
    _sleep_radius = _env_float("KROLIK_LOD_SLEEP_RADIUS", 360.0, _full_radius, 10000.0)
    _wake_radius = _env_float("KROLIK_LOD_WAKE_RADIUS", 330.0, _full_radius, _sleep_radius)
    var manifest_env := OS.get_environment("KROLIK_LOD_MANIFEST_PATH").strip_edges()
    if not manifest_env.is_empty():
        _manifest_path = manifest_env
    var screenshot_env := OS.get_environment("KROLIK_LOD_SCREENSHOT_PATH").strip_edges()
    if not screenshot_env.is_empty():
        _screenshot_path = screenshot_env

func _manifest_absolute_path() -> String:
    if _manifest_path.begins_with("res://") or _manifest_path.begins_with("user://"):
        return ProjectSettings.globalize_path(_manifest_path)
    return _manifest_path

func _facial_config() -> Dictionary:
    return {
        "procedural_blink": {"enabled": true, "min_interval": 2.1, "max_interval": 6.4, "duration": 0.12},
        "look_at": {"enabled": true, "max_head_deg": 16.0, "max_eye": 0.06},
    }

func _traits_for(index: int) -> Dictionary:
    var out := {
        "curiosity": 0.5, "sociability": 0.5, "boldness": 0.5,
        "patience": 0.5, "resilience": 0.5,
    }
    out[str(TRAIT_NAMES[index % TRAIT_NAMES.size()])] = 0.8
    return out

func _mind_for(index: int) -> Dictionary:
    return {
        "enabled": true,
        "state": "wander",
        "profile": {
            "mobility": "free", "routine": "explorer", "autonomy": 1.0,
            "wander": 1.0, "walk_speed": 1.0, "traits": _traits_for(index),
        },
        "needs": {"energy": 1.0, "comfort": 0.7, "curiosity": 1.0, "social": 0.35},
        "memory": [{
            "kind": "interesting", "subject": "lod-stress-%03d" % index,
            "valence": 0.2, "importance": 0.5, "age": 0.0, "ttl": 600.0,
        }],
    }

func _spawn_agents() -> void:
    _world = Node2D.new()
    _world.name = "LODStressWorld"
    root.add_child(_world)
    _agents.clear()
    _start_positions.clear()
    _spawn_error = ""

    var manifest_abs := _manifest_absolute_path()
    if manifest_abs.is_empty() or not FileAccess.file_exists(manifest_abs):
        _spawn_error = "production manifest missing: " + manifest_abs
        return

    var columns := maxi(1, int(ceil(sqrt(float(_agent_count) * 2.2))))
    var min_point := Vector2(INF, INF)
    var max_point := Vector2(-INF, -INF)
    for i in range(_agent_count):
        var row := i / columns
        var col := i % columns
        var spawn := Vector2(36.0 + col * 34.0, 52.0 + row * 40.0)
        min_point.x = minf(min_point.x, spawn.x)
        min_point.y = minf(min_point.y, spawn.y)
        max_point.x = maxf(max_point.x, spawn.x)
        max_point.y = maxf(max_point.y, spawn.y)

        var agent := AgentScript.new() as VaultCharacterAgent
        _world.add_child(agent)
        var mind := _mind_for(i)
        agent.setup("lod_stress_%03d" % i, spawn, mind)
        if not agent.load_runtime_manifest(manifest_abs):
            _spawn_error = "production manifest rejected for LOD agent %d" % i
            return
        agent.brain.apply_snapshot(mind)
        agent.position = spawn
        agent.home_position = spawn
        agent.target_position = spawn
        if agent.skinned_visual == null or not is_instance_valid(agent.skinned_visual) or agent.flat_sprite != null:
            _spawn_error = "agent %d did not create production GPU skin" % i
            return
        if agent.collision_rig == null:
            _spawn_error = "agent %d did not create production collision rig" % i
            return

        agent.facial_state.configure(_facial_config(), i + 1)
        var look_x := -1.0 + 2.0 * float(i % 11) / 10.0
        var look_y := -0.5 + float(i % 7) / 6.0
        agent.set_look_target(Vector2(look_x, look_y))
        # Match the existing rendered baseline: bodies do not collide with each
        # other, but full-tier collision proxy transforms are still updated.
        agent.collision_layer = 0
        agent.collision_mask = 0
        var direction := -1.0 if (i % 2) == 0 else 1.0
        var target := spawn + Vector2(direction * 96.0, 24.0 + float(i % 3) * 8.0)
        agent.target_position = target
        agent.world_targets = [target]
        _agents.append(agent)
        _start_positions[agent.get_instance_id()] = spawn

    _lod = VaultPopulationLOD.new()
    _world.add_child(_lod)
    _lod.configure({
        "enabled": true,
        "focus_position": (min_point + max_point) * 0.5,
        "full_radius": _full_radius,
        "sleep_radius": _sleep_radius,
        "wake_radius": _wake_radius,
        "reassess_interval": 0.10,
    })
    for agent in _agents:
        if not _lod.register_agent(agent):
            _spawn_error = "failed to register agent with population LOD"
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
    var err := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
    if err != OK and err != ERR_ALREADY_EXISTS:
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
    _spawn_agents()
    if not _spawn_error.is_empty():
        push_error("KROLIK LOD scale: " + _spawn_error)
        quit(11)
        return

    await _wait_physics_frames(_warmup_frames)
    var tiers_before := _lod.tier_snapshot()
    var sleeping_positions: Dictionary = {}
    for agent in _agents:
        if _lod.is_sleeping(agent):
            sleeping_positions[agent.get_instance_id()] = agent.global_position

    var started_usec := Time.get_ticks_usec()
    await _wait_physics_frames(_sample_frames)
    var elapsed := float(Time.get_ticks_usec() - started_usec) / 1000000.0
    var fps := float(_sample_frames) / maxf(elapsed, 0.000001)
    var tiers := _lod.tier_snapshot()

    var ai_policy_active := 0
    var personality_active := 0
    var memory_active := 0
    var awake := 0
    var awake_moved := 0
    var sleeping_drift_max := 0.0
    var dominant_trait_counts: Dictionary = {}
    for agent in _agents:
        if not is_instance_valid(agent):
            continue
        if agent.brain.policy_loaded:
            ai_policy_active += 1
        if not agent.brain.memory_snapshot().is_empty():
            memory_active += 1
        var dominant := "neutral"
        for raw_name in TRAIT_NAMES:
            var trait_name := str(raw_name)
            if absf(float(agent.brain.traits.get(trait_name, 0.5)) - 0.5) > 0.001:
                dominant = trait_name
                break
        if dominant != "neutral":
            personality_active += 1
        dominant_trait_counts[dominant] = int(dominant_trait_counts.get(dominant, 0)) + 1

        var start: Vector2 = _start_positions.get(agent.get_instance_id(), agent.global_position)
        if not _lod.is_sleeping(agent):
            awake += 1
            if agent.global_position.distance_to(start) >= 8.0:
                awake_moved += 1
        elif sleeping_positions.has(agent.get_instance_id()):
            sleeping_drift_max = maxf(
                sleeping_drift_max,
                agent.global_position.distance_to(sleeping_positions[agent.get_instance_id()])
            )

    var awake_moved_share := float(awake_moved) / float(maxi(awake, 1))
    var renderer_name := RenderingServer.get_video_adapter_name()
    print("KROLIK_LOD_SCALE agents=%d full=%d reduced=%d sleeping=%d frames=%d seconds=%.4f avg_fps=%.2f awake=%d awake_moved=%d awake_moved_share=%.3f sleep_drift_max=%.3f renderer=%s" % [
        _agent_count, int(tiers.get("full", 0)), int(tiers.get("reduced", 0)), int(tiers.get("sleeping", 0)),
        _sample_frames, elapsed, fps, awake, awake_moved, awake_moved_share, sleeping_drift_max, renderer_name
    ])
    print("KROLIK_LOD_SCALE_METRIC agents=%d full=%d reduced=%d sleeping=%d sample_frames=%d sample_seconds=%.4f sim_fps=%.2f awake_moved_share=%.3f sleep_drift_max=%.3f renderer=%s" % [
        _agent_count, int(tiers.get("full", 0)), int(tiers.get("reduced", 0)), int(tiers.get("sleeping", 0)),
        _sample_frames, elapsed, fps, awake_moved_share, sleeping_drift_max, renderer_name
    ])

    if int(tiers.get("registered", 0)) != _agent_count:
        push_error("KROLIK LOD scale: registered population mismatch"); quit(2); return
    if int(tiers.get("full", 0)) <= 0 or int(tiers.get("reduced", 0)) <= 0 or int(tiers.get("sleeping", 0)) <= 0:
        push_error("KROLIK LOD scale: all three tiers must be populated: " + str(tiers)); quit(3); return
    if int(tiers_before.get("sleeping", 0)) <= 0:
        push_error("KROLIK LOD scale: warmup produced no sleeping population"); quit(4); return
    if ai_policy_active != _agent_count or personality_active != _agent_count or memory_active != _agent_count:
        push_error("KROLIK LOD scale: semantic state missing policy=%d personality=%d memory=%d" % [ai_policy_active, personality_active, memory_active]); quit(5); return
    if dominant_trait_counts.size() != TRAIT_NAMES.size():
        push_error("KROLIK LOD scale: personality families missing: " + str(dominant_trait_counts)); quit(6); return
    if elapsed > _max_sample_seconds:
        push_error("KROLIK LOD scale: sample exceeded %.2fs budget: %.2fs" % [_max_sample_seconds, elapsed]); quit(7); return
    if awake_moved_share < 0.75:
        push_error("KROLIK LOD scale: awake movement share too low: %.3f" % awake_moved_share); quit(8); return
    if sleeping_drift_max > 0.01:
        push_error("KROLIK LOD scale: sleeping population drifted physically: %.3f" % sleeping_drift_max); quit(9); return

    var render_evidence := await _capture_render_evidence()
    if not bool(render_evidence.get("saved", false)) or int(render_evidence.get("sampled_foreground", 0)) < 500:
        push_error("KROLIK LOD scale: rendered evidence failed: " + str(render_evidence)); quit(10); return
    print("KROLIK_LOD_RENDER_STRESS saved=true sampled_foreground=%d size=%dx%d path=%s renderer=%s" % [
        int(render_evidence.get("sampled_foreground", 0)), int(render_evidence.get("width", 0)),
        int(render_evidence.get("height", 0)), str(render_evidence.get("path", "")), renderer_name
    ])
    quit(0)
