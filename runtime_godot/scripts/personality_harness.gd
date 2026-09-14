extends SceneTree

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("KROLIK_PERSONALITY_FAIL " + message)
    quit(1)

func _snapshot(trait_name: String = "", trait_value: float = 0.5) -> Dictionary:
    var profile := {
        "mobility": "auto", "routine": "balanced", "autonomy": 0.6,
        "wander": 0.5, "social": 0.5, "rest_threshold": 0.24,
        "curiosity_threshold": 0.72, "home_bias": 0.35, "walk_speed": 1.0,
    }
    if not trait_name.is_empty():
        profile["traits"] = {trait_name: trait_value}
    return {
        "enabled": true,
        "state": "idle",
        "profile": profile,
        "needs": {"energy": 0.8, "comfort": 0.7, "curiosity": 0.55, "social": 0.55},
    }

func _decision(trait_name: String) -> String:
    var brain := VaultAgentBrain.new()
    brain.apply_snapshot(_snapshot(trait_name, 1.0))
    return brain.choose_state({"interesting_targets": 1.0, "social_targets": 1.0})

func _run() -> void:
    var legacy := VaultAgentBrain.new()
    legacy.apply_snapshot(_snapshot())
    for name in ["curiosity", "sociability", "boldness", "patience", "resilience"]:
        if absf(float(legacy.traits.get(name, -1.0)) - 0.5) > 0.0001:
            _fail("legacy profile did not receive neutral trait " + name)
            return

    var curious := _decision("curiosity")
    var sociable := _decision("sociability")
    var bold := _decision("boldness")
    var patient := _decision("patience")
    if curious != "inspect":
        _fail("curious profile expected inspect, got " + curious)
        return
    if sociable != "social":
        _fail("sociable profile expected social, got " + sociable)
        return
    if bold != "wander":
        _fail("bold profile expected wander, got " + bold)
        return
    if patient != "idle":
        _fail("patient profile expected idle, got " + patient)
        return

    var clamped := VaultAgentBrain.new()
    clamped.apply_snapshot(_snapshot("curiosity", 9.0))
    if absf(float(clamped.traits["curiosity"]) - 1.0) > 0.0001:
        _fail("trait upper bound was not clamped")
        return

    var agent := VaultCharacterAgent.new()
    root.add_child(agent)
    agent.setup("PERSONALITY-CI", Vector2.ZERO, _snapshot("sociability", 1.0))
    var production_state := agent.brain.choose_state({"interesting_targets": 1.0, "social_targets": 1.0})
    if production_state != "social":
        _fail("production CharacterAgent personality not applied: " + production_state)
        agent.queue_free()
        return
    var roundtrip: Dictionary = agent.brain.snapshot()
    var roundtrip_traits: Dictionary = roundtrip.get("profile", {}).get("traits", {})
    if absf(float(roundtrip_traits.get("sociability", -1.0)) - 1.0) > 0.0001:
        _fail("personality traits were not preserved in brain snapshot")
        agent.queue_free()
        return

    print(
        "KROLIK_PERSONALITY legacy_neutral=true curious=", curious,
        " sociable=", sociable,
        " bold=", bold,
        " patient=", patient,
        " production=", production_state,
        " traits=", roundtrip_traits.size()
    )
    agent.queue_free()
    await process_frame
    quit(0)
