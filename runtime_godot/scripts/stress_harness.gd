extends SceneTree

## Headless performance/behavior smoke for the actual VaultCharacterAgent runtime.
## Instantiates real CharacterBody2D agents and forces sustained locomotion.

const AgentScript = preload("res://scripts/character_agent.gd")
const AGENT_COUNT := 220
const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 180
const MAX_SAMPLE_SECONDS := 20.0
const MIN_MOVED_SHARE := 0.80
const MIN_TRAVEL_PX := 8.0

var _root: Node2D
var _agents: Array[VaultCharacterAgent] = []
var _start_positions: Dictionary = {}

func _initialize() -> void:
    call_deferred("_run")

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
        var row := i / columns
        var col := i % columns
        var spawn := Vector2(40.0 + col * 34.0, 60.0 + row * 42.0)
        agent.setup("stress_%03d" % i, spawn, {
            "enabled": true,
            "state": "wander",
            "profile": {"mobility": "free", "autonomy": 1.0, "wander": 1.0},
            "needs": {"energy": 1.0, "comfort": 0.7, "curiosity": 1.0, "social": 0.35}
        })
        var direction := -1.0 if (i % 2) == 0 else 1.0
        agent.home_position = spawn
        agent.target_position = spawn + Vector2(direction * 420.0, 90.0 + float(i % 5) * 18.0)
        agent.world_targets = [agent.target_position]
        agent.brain.state = "wander"
        _agents.append(agent)
        _start_positions[agent.get_instance_id()] = spawn

func _run() -> void:
    _spawn_agents()
    for _i in range(WARMUP_FRAMES):
        await physics_frame

    var started_usec := Time.get_ticks_usec()
    for _i in range(SAMPLE_FRAMES):
        await physics_frame
    var elapsed := float(Time.get_ticks_usec() - started_usec) / 1000000.0
    var fps := float(SAMPLE_FRAMES) / maxf(elapsed, 0.000001)
    var moving := 0
    var moved := 0
    var active := 0
    var total_travel := 0.0
    for agent in _agents:
        if not is_instance_valid(agent):
            continue
        active += 1
        if agent.velocity.length_squared() > 0.01:
            moving += 1
        var start: Vector2 = _start_positions.get(agent.get_instance_id(), agent.global_position)
        var travel := agent.global_position.distance_to(start)
        total_travel += travel
        if travel >= MIN_TRAVEL_PX:
            moved += 1

    var moved_share := float(moved) / float(AGENT_COUNT)
    var avg_travel := total_travel / float(maxi(active, 1))
    print("KROLIK_STRESS agents=%d active=%d frames=%d seconds=%.4f avg_fps=%.2f moving=%d moved=%d moved_share=%.3f avg_travel=%.2f" % [
        AGENT_COUNT, active, SAMPLE_FRAMES, elapsed, fps, moving, moved, moved_share, avg_travel
    ])

    if active != AGENT_COUNT:
        push_error("KROLIK stress: expected %d live agents, got %d" % [AGENT_COUNT, active])
        quit(2)
        return
    if elapsed > MAX_SAMPLE_SECONDS:
        push_error("KROLIK stress: %d frames took %.2fs (> %.2fs budget)" % [SAMPLE_FRAMES, elapsed, MAX_SAMPLE_SECONDS])
        quit(3)
        return
    if moved_share < MIN_MOVED_SHARE:
        push_error("KROLIK stress: only %.1f%% agents travelled >= %.1fpx (need %.1f%%)" % [moved_share * 100.0, MIN_TRAVEL_PX, MIN_MOVED_SHARE * 100.0])
        quit(4)
        return
    quit(0)
