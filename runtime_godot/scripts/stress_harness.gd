extends SceneTree

## Headless scale smoke for the real VaultCharacterAgent runtime.
const AgentScript = preload("res://scripts/character_agent.gd")
const AGENT_COUNT := 220
const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 180
const MAX_SAMPLE_SECONDS := 20.0
const MIN_MOVED_SHARE := 0.80
const MIN_TRAVEL_PX := 8.0
const MIN_PHASE_SECONDS := 2.0
const TRAIT_NAMES := ["curiosity", "sociability", "boldness", "patience", "resilience"]

var _root: Node2D
var _agents: Array[VaultCharacterAgent] = []
var _start_positions: Dictionary = {}

func _initialize() -> void:
    call_deferred("_run")

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

func _spawn_agents() -> void:
    _root = Node2D.new()
    _root.name = "StressWorld"
    root.add_child(_root)
    _agents.clear()
    _start_positions.clear()
    var columns := 22
    for i in range(AGENT_COUNT):
        var agent := AgentScript.new() as VaultCharacterAgent
        _root.add_child(agent)
        agent.process_mode = Node.PROCESS_MODE_INHERIT
        agent.set_physics_process(true)
        var row := i / columns
        var col := i % columns
        var spawn := Vector2(40.0 + col * 34.0, 60.0 + row * 42.0)
        agent.setup("stress_%03d" % i, spawn, {
            "enabled": true,
            "state": "wander",
            "profile": {
                "mobility": "free", "routine": "explorer", "autonomy": 1.0,
                "wander": 1.0, "walk_speed": 1.0, "traits": _traits_for(i),
            },
            "needs": {"energy": 1.0, "comfort": 0.7, "curiosity": 1.0, "social": 0.35}
        })
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

func _run() -> void:
    _spawn_agents()
    await _wait_physics_frames(WARMUP_FRAMES)
    var started_usec := Time.get_ticks_usec()
    await _wait_physics_frames(SAMPLE_FRAMES)
    var elapsed := float(Time.get_ticks_usec() - started_usec) / 1000000.0
    var fps := float(SAMPLE_FRAMES) / maxf(elapsed, 0.000001)
    var moving := 0
    var moved := 0
    var active := 0
    var facial_active := 0
    var ai_policy_active := 0
    var personality_active := 0
    var total_travel := 0.0
    var total_phase := 0.0
    var state_counts: Dictionary = {}
    var dominant_trait_counts: Dictionary = {}
    for agent in _agents:
        if not is_instance_valid(agent): continue
        active += 1
        if agent.facial_state.enabled: facial_active += 1
        if agent.brain.policy_loaded: ai_policy_active += 1
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
        if travel >= MIN_TRAVEL_PX: moved += 1

    var moved_share := float(moved) / float(AGENT_COUNT)
    var avg_travel := total_travel / float(maxi(active, 1))
    var avg_phase := total_phase / float(maxi(active, 1))
    print("KROLIK_STRESS agents=%d active=%d facial_active=%d ai_policy_active=%d personality_active=%d frames=%d seconds=%.4f avg_fps=%.2f moving=%d moved=%d moved_share=%.3f avg_travel=%.2f avg_phase=%.2f states=%s traits=%s" % [
        AGENT_COUNT, active, facial_active, ai_policy_active, personality_active, SAMPLE_FRAMES, elapsed, fps, moving, moved, moved_share, avg_travel, avg_phase, str(state_counts), str(dominant_trait_counts)
    ])
    print("KROLIK_STRESS_METRIC agents=%d active=%d facial_active=%d ai_policy_active=%d personality_active=%d sample_frames=%d sample_seconds=%.4f sim_fps=%.2f moved_share=%.3f avg_travel_px=%.2f avg_phase=%.2f" % [
        AGENT_COUNT, active, facial_active, ai_policy_active, personality_active, SAMPLE_FRAMES, elapsed, fps, moved_share, avg_travel, avg_phase
    ])

    if active != AGENT_COUNT:
        push_error("KROLIK stress: expected %d live agents, got %d" % [AGENT_COUNT, active]); quit(2); return
    if facial_active != AGENT_COUNT:
        push_error("KROLIK stress: expected %d active facial controllers, got %d" % [AGENT_COUNT, facial_active]); quit(6); return
    if ai_policy_active != AGENT_COUNT:
        push_error("KROLIK stress: expected %d brains on generated AI policy, got %d" % [AGENT_COUNT, ai_policy_active]); quit(7); return
    if personality_active != AGENT_COUNT:
        push_error("KROLIK stress: expected %d non-neutral mixed personalities, got %d" % [AGENT_COUNT, personality_active]); quit(8); return
    if dominant_trait_counts.size() != TRAIT_NAMES.size():
        push_error("KROLIK stress: expected all %d personality trait families, got %s" % [TRAIT_NAMES.size(), str(dominant_trait_counts)]); quit(9); return
    if elapsed > MAX_SAMPLE_SECONDS:
        push_error("KROLIK stress: %d physics frames took %.2fs (> %.2fs budget)" % [SAMPLE_FRAMES, elapsed, MAX_SAMPLE_SECONDS]); quit(3); return
    if avg_phase < MIN_PHASE_SECONDS:
        push_error("KROLIK stress: physics callbacks advanced only %.2fs average phase (need >= %.2fs)" % [avg_phase, MIN_PHASE_SECONDS]); quit(5); return
    if moved_share < MIN_MOVED_SHARE:
        push_error("KROLIK stress: only %.1f%% agents travelled >= %.1fpx (need %.1f%%)" % [moved_share * 100.0, MIN_TRAVEL_PX, MIN_MOVED_SHARE * 100.0]); quit(4); return
    quit(0)
