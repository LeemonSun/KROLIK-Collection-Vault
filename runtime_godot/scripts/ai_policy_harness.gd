extends SceneTree

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("KROLIK_AI_POLICY_FAIL " + message)
    quit(1)

func _run() -> void:
    var brain := VaultAgentBrain.new()
    if not brain.policy_loaded:
        _fail("default generated policy was not loaded")
        return
    if brain.policy_source != VaultAgentBrain.DEFAULT_POLICY_PATH:
        _fail("unexpected policy source: " + brain.policy_source)
        return

    var social_snapshot := {
        "enabled": true,
        "state": "idle",
        "profile": {
            "mobility": "auto", "routine": "social", "autonomy": 0.75,
            "wander": 0.2, "social": 0.9, "rest_threshold": 0.24,
            "curiosity_threshold": 0.72, "home_bias": 0.35, "walk_speed": 1.0,
        },
        "needs": {"energy": 0.8, "comfort": 0.7, "curiosity": 0.7, "social": 0.8},
    }
    brain.apply_snapshot(social_snapshot)
    var default_state := brain.choose_state({"social_targets": 2.0})
    if default_state != "social":
        _fail("generated default policy did not select social; got " + default_state)
        return

    var file := FileAccess.open(VaultAgentBrain.DEFAULT_POLICY_PATH, FileAccess.READ)
    if file == null:
        _fail("cannot reopen bundled policy")
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("bundled policy JSON is not an object")
        return
    var custom: Dictionary = parsed.duplicate(true)
    custom["utility"]["idle"]["base"] = 10.0
    custom["utility"]["social"]["base"] = -10.0
    custom["utility"]["wander"]["base"] = -10.0
    custom["utility"]["inspect"]["base"] = -10.0
    custom["utility"]["rest"]["base"] = -10.0
    custom["need_rates_per_minute"]["idle"]["energy"] = 0.10
    if not brain.configure_policy(custom, "harness-custom"):
        _fail("valid custom policy was rejected")
        return
    brain.apply_snapshot(social_snapshot)
    var overridden_state := brain.choose_state({"social_targets": 2.0})
    if overridden_state != "idle":
        _fail("custom policy did not alter runtime decision; got " + overridden_state)
        return

    brain.energy = 0.50
    brain.step(60.0, {"social_targets": 2.0})
    if absf(brain.energy - 0.60) > 0.0001:
        _fail("custom need rate was not consumed; energy=" + str(brain.energy))
        return

    var invalid := custom.duplicate(true)
    invalid["schema"] = "broken"
    if brain.configure_policy(invalid, "invalid"):
        _fail("invalid policy was accepted")
        return
    if brain.policy_source != "harness-custom":
        _fail("invalid policy mutated active policy source")
        return

    var agent := VaultCharacterAgent.new()
    root.add_child(agent)
    agent.setup("AI-POLICY-CI", Vector2.ZERO, social_snapshot)
    if not agent.brain.policy_loaded:
        _fail("production CharacterAgent brain did not load generated policy")
        agent.queue_free()
        return
    var production_state := agent.brain.choose_state({"social_targets": 2.0})
    if production_state != "social":
        _fail("production CharacterAgent policy decision mismatch: " + production_state)
        agent.queue_free()
        return

    print(
        "KROLIK_AI_POLICY schema=", custom.get("schema", ""),
        " source=", brain.policy_source,
        " default_state=", default_state,
        " overridden_state=", overridden_state,
        " energy_after_rate=", "%.3f" % brain.energy,
        " production_state=", production_state,
        " production_loaded=", agent.brain.policy_loaded
    )
    agent.queue_free()
    await process_frame
    quit(0)
