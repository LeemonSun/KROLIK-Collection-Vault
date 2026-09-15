extends SceneTree

## Scale smoke for the real VaultCharacterAgent runtime.
## Defaults preserve the existing 220-agent Linux/headless regression. Optional
## environment variables turn the same workload into a rendered production-skin
## benchmark on Windows without maintaining a second easier stress implementation.
const AgentScript = preload("res://scripts/character_agent.gd")
const TRAIT_NAMES := ["curiosity", "sociability", "boldness", "patience", "resilience"]

var _agent_count := 220
var _warmup_frames := 30
var _sample_frames := 180
var _max_sample_seconds := 20.0
var _min_moved_share := 0.80
var _min_travel_px := 8.0
var _min_phase_seconds := 2.0
var _manifest_path := ""
var _require_visuals := false
var _screenshot_path := ""

var _root: Node2D
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
    _agent_count = _env_int("KROLIK_STRESS_AGENTS", 220, 1, 1000)
    _warmup_frames = _env_int("KROLIK_STRESS_WARMUP_FRAMES", 30, 0, 600)
    _sample_frames = _env_int("KROLIK_STRESS_SAMPLE_FRAMES", 180, 1, 3600)
    _max_sample_seconds = _env_float("KROLIK_STRESS_MAX_SECONDS", 20.0, 0.1, 300.0)
    _min_moved_share = _env_float("KROLIK_STRESS_MIN_MOVED_SHARE", 0.80, 0.0, 1.0)
    _min_travel_px = _env_float("KROLIK_STRESS_MIN_TRAVEL_PX", 8.0, 0.0, 10000.0)
    _min_phase_seconds = _env_float("KROLIK_STRESS_MIN_PHASE_SECONDS", 2.0, 0.0, 120.0)
    _manifest_path = OS.get_environment("KROLIK_STRESS_MANIFEST_PATH").strip_edges()
    _require_visuals = OS.get_environment("KROLIK_STRESS_REQUIRE_VISUALS").strip_edges() == "1"
    _screenshot_path = OS.get_environment("KROLIK_STRESS_SCREENSHOT_PATH").strip_edges()

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
    var name := str(TRAIT_NAMES[index % TRAIT_NAMES.size()])
    out[name] = 0.8
    return out

func _memory_for(index: int) -> Array:
    return [{
        "kind": "interesting",
        "subject": "stress-%03d" % index,
        "valence": 0.2,
        "importance": 0.5,
        "age": 0.0,
        "ttl": 600.0,
    }]

func _mind_for(index: int) -> Dictionary:
    return {
        "enabled": true,
        "state": "wander",
        "profile": {
            "mobility": "free", "routine": "explorer", "autonomy": 1.0,
            "wander": 1.0, "walk_speed": 1.0, "traits": _traits_for(index),
        },
        "needs": {"energy": 1.0, "comfort": 0.7, "curiosity": 1.0, "social": 0.35},
        "memory": _memory_for(index),
    }

func _manifest_absolute_path() -> String:
    if _manifest_path.is_empty():
        return ""
    if _manifest_path.begins_with("res://") or _manifest_path.begins_with("user://"):
        return ProjectSettings.globalize_path(_manifest_path)
    return _manifest_path

func _spawn_agents() -> void:
    _root = Node2D.new()
    _root.name = "StressWorld"
    root.add_child(_root)
    _agents.clear()
    _start_positions.clear()
    _spawn_error = ""

    var columns := maxi(1, int(ceil(sqrt(float(_agent_count) * 2.2))))
    var manifest_abs := _manifest_absolute_path()
    for i in range(_agent_count):
        var agent := AgentScript.new() as VaultCharacterAgent
        _root.add_child(agent)
        agent.process_mode = Node.PROCESS_MODE_INHERIT
        agent.set_physics_process(true)
        var row := i / columns
        var col := i % columns
        var spawn := Vector2(36.0 + col * 34.0, 52.0 + row * 40.0)
        var mind := _mind_for(i)
        agent.setup("stress_%03d" % i, spawn, mind)

        if not manifest_abs.is_empty():
            if not agent.load_runtime_manifest(manifest_abs):
                _spawn_error = "production manifest rejected for stress agent %d: %s" % [i, manifest_abs]
                return
            # Loading a runtime package intentionally restores its persisted mind.
            # Stress needs the same deterministic mixed workload for every visual
            # instance, so reapply the stress snapshot after the visual/rig package.
            agent.brain.apply_snapshot(mind)
            agent.position = spawn
            agent.home_position = spawn
            agent.target_position = spawn

        agent.facial_state.configure(_facial_config(), i + 1)
        var look_x := -1.0 + 2.0 * float(i % 11) / 10.0
        var look_y := -0.5 + float(i % 7) / 6.0
        agent.set_look_target(Vector2(look_x, look_y))
        agent.collision_layer = 0
        agent.collision_mask = 0
        var direction := -1.0 if (i % 2) == 0 else 1.0
        var target := spawn + Vector2(direction * 96.0, 24.0 + float(i % 3) * 8.0)
        agent.home_position = spawn
        agent.target_position = target
        agent.world_targets = [target]
        _agents.append(agent)
        _start_positions[agent.get_instance_id()] = spawn

func _wait_physics_frames(count: int) -> void:
    for _i in range(count):
        await physics_frame

func _capture_render_evidence() -> Dictionary:
    if _screenshot_path.is_empty():
        return {"saved": false, "sampled_foreground": 0}
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
        push_error("KROLIK stress: " + _spawn_error)
        quit(11)
        return

    await _wait_physics_frames(_warmup_frames)
    var started_usec := Time.get_ticks_usec()
    await _wait_physics_frames(_sample_frames)
    var elapsed := float(Time.get_ticks_usec() - started_usec) / 1000000.0
    var fps := float(_sample_frames) / maxf(elapsed, 0.000001)
    var moving := 0
    var moved := 0
    var active := 0
    var facial_active := 0
    var ai_policy_active := 0
    var personality_active := 0
    var memory_active := 0
    var visual_active := 0
    var total_travel := 0.0
    var total_phase := 0.0
    var state_counts: Dictionary = {}
    var dominant_trait_counts: Dictionary = {}
    for agent in _agents:
        if not is_instance_valid(agent): continue
        active += 1
        if agent.facial_state.enabled: facial_active += 1
        if agent.brain.policy_loaded: ai_policy_active += 1
        if not agent.brain.memory_snapshot().is_empty(): memory_active += 1
        if agent.skinned_visual != null and is_instance_valid(agent.skinned_visual) and agent.flat_sprite == null:
            visual_active += 1
        var varied := false
        var dominant := "neutral"
        for raw_name in TRAIT_NAMES:
            var trait_name := str(raw_name)
            if absf(float(agent.brain.traits.get(trait_name, 0.5)) - 0.5) > 0.001:
                varied = true
                dominant = trait_name
                break
        if varied: personality_active += 1
        dominant_trait_counts[dominant] = int(dominant_trait_counts.get(dominant, 0)) + 1
        total_phase += agent.phase
        var state_name := agent.brain.state
        state_counts[state_name] = int(state_counts.get(state_name, 0)) + 1
        if agent.velocity.length_squared() > 0.01: moving += 1
        var start: Vector2 = _start_positions.get(agent.get_instance_id(), agent.global_position)
        var travel := agent.global_position.distance_to(start)
        total_travel += travel
        if travel >= _min_travel_px: moved += 1

    var moved_share := float(moved) / float(_agent_count)
    var avg_travel := total_travel / float(maxi(active, 1))
    var avg_phase := total_phase / float(maxi(active, 1))
    var renderer_name := RenderingServer.get_video_adapter_name()
    print("KROLIK_STRESS agents=%d active=%d facial_active=%d ai_policy_active=%d personality_active=%d memory_active=%d visual_active=%d frames=%d seconds=%.4f avg_fps=%.2f moving=%d moved=%d moved_share=%.3f avg_travel=%.2f avg_phase=%.2f states=%s traits=%s renderer=%s" % [
        _agent_count, active, facial_active, ai_policy_active, personality_active, memory_active, visual_active, _sample_frames, elapsed, fps, moving, moved, moved_share, avg_travel, avg_phase, str(state_counts), str(dominant_trait_counts), renderer_name
    ])
    print("KROLIK_STRESS_METRIC agents=%d active=%d facial_active=%d ai_policy_active=%d personality_active=%d memory_active=%d visual_active=%d sample_frames=%d sample_seconds=%.4f sim_fps=%.2f moved_share=%.3f avg_travel_px=%.2f avg_phase=%.2f renderer=%s" % [
        _agent_count, active, facial_active, ai_policy_active, personality_active, memory_active, visual_active, _sample_frames, elapsed, fps, moved_share, avg_travel, avg_phase, renderer_name
    ])

    if active != _agent_count:
        push_error("KROLIK stress: expected %d live agents, got %d" % [_agent_count, active]); quit(2); return
    if facial_active != _agent_count:
        push_error("KROLIK stress: expected %d active facial controllers, got %d" % [_agent_count, facial_active]); quit(6); return
    if ai_policy_active != _agent_count:
        push_error("KROLIK stress: expected %d brains on generated AI policy, got %d" % [_agent_count, ai_policy_active]); quit(7); return
    if personality_active != _agent_count:
        push_error("KROLIK stress: expected %d non-neutral mixed personalities, got %d" % [_agent_count, personality_active]); quit(8); return
    if memory_active != _agent_count:
        push_error("KROLIK stress: expected %d brains with bounded short-term memory, got %d" % [_agent_count, memory_active]); quit(10); return
    if _require_visuals and visual_active != _agent_count:
        push_error("KROLIK stress: expected %d GPU-skinned visuals, got %d" % [_agent_count, visual_active]); quit(12); return
    if dominant_trait_counts.size() != TRAIT_NAMES.size():
        push_error("KROLIK stress: expected all %d personality trait families, got %s" % [TRAIT_NAMES.size(), str(dominant_trait_counts)]); quit(9); return
    if elapsed > _max_sample_seconds:
        push_error("KROLIK stress: %d physics frames took %.2fs (> %.2fs budget)" % [_sample_frames, elapsed, _max_sample_seconds]); quit(3); return
    if avg_phase < _min_phase_seconds:
        push_error("KROLIK stress: physics callbacks advanced only %.2fs average phase (need >= %.2fs)" % [avg_phase, _min_phase_seconds]); quit(5); return
    if moved_share < _min_moved_share:
        push_error("KROLIK stress: only %.1f%% agents travelled >= %.1fpx (need %.1f%%)" % [moved_share * 100.0, _min_travel_px, _min_moved_share * 100.0]); quit(4); return

    var render_evidence := await _capture_render_evidence()
    if _require_visuals:
        if not bool(render_evidence.get("saved", false)):
            push_error("KROLIK stress: rendered screenshot evidence failed: " + str(render_evidence)); quit(13); return
        if int(render_evidence.get("sampled_foreground", 0)) < 500:
            push_error("KROLIK stress: rendered evidence appears blank: " + str(render_evidence)); quit(14); return
        print("KROLIK_RENDER_STRESS saved=true sampled_foreground=%d size=%dx%d path=%s renderer=%s" % [
            int(render_evidence.get("sampled_foreground", 0)), int(render_evidence.get("width", 0)), int(render_evidence.get("height", 0)), str(render_evidence.get("path", "")), renderer_name
        ])
    quit(0)
