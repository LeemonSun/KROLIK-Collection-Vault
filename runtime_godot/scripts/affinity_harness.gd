extends SceneTree

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("KROLIK_AFFINITY_FAIL " + message)
    quit(1)

func _borderline_snapshot() -> Dictionary:
    return {
        "enabled": true,
        "state": "idle",
        "profile": {
            "mobility": "auto", "routine": "balanced", "autonomy": 0.2,
            "wander": 0.2, "social": 0.2, "rest_threshold": 0.24,
            "curiosity_threshold": 0.72, "home_bias": 0.35, "walk_speed": 1.0,
        },
        "needs": {"energy": 0.8, "comfort": 0.7, "curiosity": 0.25, "social": 0.25},
    }

func _count_kind(records: Array, kind: String) -> int:
    var count := 0
    for raw in records:
        if typeof(raw) == TYPE_DICTIONARY and str(raw.get("kind", "")) == kind:
            count += 1
    return count

func _run() -> void:
    var brain := VaultAgentBrain.new()
    if not brain.policy_loaded or brain.affinity_state.config.is_empty():
        _fail("generated long-term affinity policy was not loaded")
        return

    var snapshot := _borderline_snapshot()
    brain.apply_snapshot(snapshot)
    var base_context := {"interesting_targets": 1.0, "social_targets": 1.0}
    var legacy_state := brain.choose_state(base_context)
    if legacy_state != "idle":
        _fail("empty affinity changed legacy baseline: " + legacy_state)
        return

    for _i in range(10):
        if not brain.learn_affinity("character", "alice", 1.0):
            _fail("valid character affinity was rejected")
            return
    var unknown_state := brain.choose_state(base_context)
    var social_context := base_context.duplicate(true)
    social_context["social_subject"] = "alice"
    var matched_state := brain.choose_state(social_context)
    if unknown_state != "idle" or matched_state != "social":
        _fail("character affinity relevance mismatch unknown=%s matched=%s" % [unknown_state, matched_state])
        return

    for _i in range(6):
        brain.learn_affinity("place", "garden", 1.0)
    for _i in range(4):
        brain.learn_affinity("place", "market", 1.0)
    if brain.favorite_place() != "garden":
        _fail("favorite place expected garden, got " + brain.favorite_place())
        return

    brain.apply_snapshot(snapshot)
    for index in range(20):
        brain.learn_affinity("character", "char-%02d" % index, 0.2 + float(index) / 25.0)
    for index in range(12):
        brain.learn_affinity("place", "place-%02d" % index, 0.2 + float(index) / 16.0)
    var bounded := brain.affinity_snapshot()
    var character_count := _count_kind(bounded, "character")
    var place_count := _count_kind(bounded, "place")
    if character_count != 16 or place_count != 8:
        _fail("independent capacities failed characters=%d places=%d" % [character_count, place_count])
        return

    brain.apply_snapshot({
        "profile": {"mobility": "auto"},
        "needs": {"energy": 0.1, "comfort": 0.7, "curiosity": 0.8, "social": 0.8},
        "affinity": [{"kind": "character", "subject": "alice", "affinity": 1.0, "familiarity": 1.0}],
    })
    var hard_gate := brain.choose_state({"bound": true, "social_targets": 9.0, "social_subject": "alice"})
    if hard_gate != "contained":
        _fail("affinity overrode contained hard gate: " + hard_gate)
        return
    var exhausted := brain.choose_state({"social_targets": 9.0, "social_subject": "alice"})
    if exhausted != "rest":
        _fail("affinity overrode exhaustion hard gate: " + exhausted)
        return

    brain.apply_snapshot(snapshot)
    for _i in range(10):
        brain.learn_affinity("character", "alice", 1.0)
    var before_decay: Array = brain.affinity_snapshot()
    brain.decay_affinities(100.0)
    var after_decay: Array = brain.affinity_snapshot()
    if before_decay.is_empty() or after_decay.is_empty():
        _fail("slow decay unexpectedly removed strong affinity")
        return
    if float(after_decay[0].get("affinity", 0.0)) >= float(before_decay[0].get("affinity", 0.0)):
        _fail("affinity did not decay")
        return

    var agent := VaultCharacterAgent.new()
    root.add_child(agent)
    var production := _borderline_snapshot()
    production["affinity"] = [{
        "kind": "character", "subject": "alice", "affinity": 1.0, "familiarity": 1.0,
    }, {
        "kind": "place", "subject": "garden", "affinity": 0.8, "familiarity": 0.9,
    }]
    agent.setup("AFFINITY-CI", Vector2.ZERO, production)
    var production_state := agent.brain.choose_state(social_context)
    var production_affinity := agent.brain.affinity_snapshot()
    var roundtrip := agent.brain.snapshot()
    if production_state != "social" or production_affinity.size() != 2:
        _fail("production CharacterAgent did not consume affinity snapshot")
        agent.queue_free()
        return
    if typeof(roundtrip.get("affinity", null)) != TYPE_ARRAY or roundtrip["affinity"].size() != 2:
        _fail("affinity did not round-trip through production brain snapshot")
        agent.queue_free()
        return
    if str(roundtrip.get("favorite_place", "")) != "garden":
        _fail("derived favorite place did not round-trip")
        agent.queue_free()
        return

    print(
        "KROLIK_AFFINITY legacy=", legacy_state,
        " unknown=", unknown_state,
        " matched=", matched_state,
        " characters=", character_count,
        " places=", place_count,
        " favorite=garden hard_gate=", hard_gate,
        " decay_before=", snappedf(float(before_decay[0]["affinity"]), 0.001),
        " decay_after=", snappedf(float(after_decay[0]["affinity"]), 0.001),
        " production_entries=", production_affinity.size(),
        " production_state=", production_state
    )
    agent.queue_free()
    await process_frame
    quit(0)
