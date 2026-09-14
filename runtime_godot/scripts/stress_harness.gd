extends SceneTree

## Headless performance/behavior smoke for the actual VaultCharacterAgent runtime.
## This intentionally instantiates real CharacterBody2D agents (brain, animation,
## navigation agent and physics processing), not lightweight test doubles.

const AgentScript = preload("res://scripts/character_agent.gd")
const AGENT_COUNT := 220
const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 180
const MAX_SAMPLE_SECONDS := 20.0

var _root: Node2D
var _agents: Array[VaultCharacterAgent] = []

func _initialize() -> void:
    call_deferred("_run")

func _spawn_agents() -> void:
    _root = Node2D.new()
    _root.name = "StressWorld"
    root.add_child(_root)
    _agents.clear()
    var columns := 22
    for i in range(AGENT_COUNT):
        var agent := AgentScript.new() as VaultCharacterAgent
        _root.add_child(agent)
        var row := i / columns
        var col := i % columns
        agent.setup("stress_%03d" % i, Vector2(40.0 + col * 34.0, 60.0 + row * 42.0), {
            "enabled": true,
            "state": "idle",
            "profile": {"mobility": "free", "autonomy": 0.7, "wander": 0.65},
            "needs": {"energy": 0.8, "comfort": 0.7, "curiosity": 0.65, "social": 0.35}
        })
        agent.home_position = agent.position
        agent.target_position = agent.position + Vector2(24.0, 0.0)
        _agents.append(agent)

func _run() -> void:
    _spawn_agents()
    for _i in range(WARMUP_FRAMES):
        await process_frame

    var started_usec := Time.get_ticks_usec()
    for _i in range(SAMPLE_FRAMES):
        await process_frame
    var elapsed := float(Time.get_ticks_usec() - started_usec) / 1000000.0
    var fps := float(SAMPLE_FRAMES) / maxf(elapsed, 0.000001)
    var moving := 0
    var active := 0
    for agent in _agents:
        if is_instance_valid(agent):
            active += 1
            if agent.velocity.length_squared() > 0.01:
                moving += 1

    print("KROLIK_STRESS agents=%d active=%d frames=%d seconds=%.4f avg_fps=%.2f moving=%d" % [
        AGENT_COUNT, active, SAMPLE_FRAMES, elapsed, fps, moving
    ])

    if active != AGENT_COUNT:
        push_error("KROLIK stress: expected %d live agents, got %d" % [AGENT_COUNT, active])
        quit(2)
        return
    if elapsed > MAX_SAMPLE_SECONDS:
        push_error("KROLIK stress: %d frames took %.2fs (> %.2fs budget)" % [SAMPLE_FRAMES, elapsed, MAX_SAMPLE_SECONDS])
        quit(3)
        return
    quit(0)
