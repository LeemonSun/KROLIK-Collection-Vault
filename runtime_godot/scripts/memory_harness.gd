extends SceneTree

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("KROLIK_MEMORY_FAIL " + message)
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

func _run() -> void:
    var brain := VaultAgentBrain.new()
    if not brain.policy_loaded:
        _fail("generated policy was not loaded")
        return

    var snapshot := _borderline_snapshot()
    brain.apply_snapshot(snapshot)
    var context := {"interesting_targets": 1.0, "social_targets": 1.0}
    var legacy_state := brain.choose_state(context)
    if legacy_state != "idle":
        _fail("empty memory changed legacy baseline: " + legacy_state)
        return

    if not brain.remember_event("social", "alice", 0.2, 0.2, 120.0):
        _fail("valid social memory was rejected")
        return
    if not brain.remember_event("social", "alice", 0.9, 0.9, 120.0):
        _fail("memory refresh was rejected")
        return
    var deduped := brain.memory_snapshot()
    if deduped.size() != 1 or absf(float(deduped[0]["valence"]) - 0.9) > 0.0001:
        _fail("same kind+subject did not refresh in-place")
        return

    brain.clear_memory()
    brain.remember_event("interesting", "weak", 1.0, 0.01, 120.0)
    for index in range(8):
        brain.remember_event("interesting", "strong-%d" % index, 1.0, 0.8, 120.0)
    var bounded := brain.memory_snapshot()
    if bounded.size() != 8:
        _fail("memory capacity is not 8: " + str(bounded.size()))
        return
    for entry in bounded:
        if str(entry.get("subject", "")) == "weak":
            _fail("deterministic eviction kept weakest memory")
            return

    brain.clear_memory()
    brain.remember_event("home", "room-a", 1.0, 1.0, 1.0)
    brain.step(0.5, {})
    var halfway := brain.memory_snapshot()
    if halfway.size() != 1 or absf(float(halfway[0]["age"]) - 0.5) > 0.02:
        _fail("memory did not age analytically")
        return
    brain.step(0.5, {})
    if not brain.memory_snapshot().is_empty():
        _fail("memory did not expire at TTL")
        return

    brain.apply_snapshot(snapshot)
    brain.remember_event("social", "alice", 1.0, 1.0, 180.0)
    var unfocused_state := brain.choose_state(context)
    var focused_context := context.duplicate(true)
    focused_context["memory_subject"] = "alice"
    var focused_state := brain.choose_state(focused_context)
    if unfocused_state != "idle" or focused_state != "social":
        _fail("subject relevance mismatch unfocused=%s focused=%s" % [unfocused_state, focused_state])
        return

    brain.apply_snapshot({
        "profile": {"mobility": "auto"},
        "needs": {"energy": 0.1, "comfort": 0.7, "curiosity": 0.8, "social": 0.5},
    })
    brain.remember_event("interesting", "door", 1.0, 1.0, 180.0)
    var hard_gate := brain.choose_state({"bound": true, "interesting_targets": 9.0, "memory_subject": "door"})
    if hard_gate != "contained":
        _fail("memory overrode contained hard gate: " + hard_gate)
        return
    var exhausted := brain.choose_state({"interesting_targets": 9.0, "memory_subject": "door"})
    if exhausted != "rest":
        _fail("memory overrode exhaustion hard gate: " + exhausted)
        return

    brain.apply_snapshot(snapshot)
    for _index in range(6):
        if not brain.reinforce_relationship("alice", 1.0, 1.0):
            _fail("valid long-term relationship update was rejected")
            return
    var durable := brain.long_term_snapshot()
    var relationships: Array = durable.get("relationships", [])
    if relationships.size() != 1 or float(relationships[0].get("affinity", 0.0)) < 0.9 or int(relationships[0].get("interactions", 0)) != 6:
        _fail("long-term relationship did not learn/deduplicate")
        return
    var long_context := context.duplicate(true)
    long_context["social_subject"] = "alice"
    var long_social_state := brain.choose_state(long_context)
    if long_social_state != "social":
        _fail("positive long-term affinity did not bias social choice: " + long_social_state)
        return

    for _index in range(6):
        if not brain.remember_place_visit("library", 1.0, 1.0):
            _fail("valid place visit was rejected")
            return
    durable = brain.long_term_snapshot()
    var places: Array = durable.get("places", [])
    if places.size() != 1 or str(durable.get("favorite_place", "")) != "library" or int(places[0].get("visits", 0)) != 6:
        _fail("favorite-place learning failed")
        return
    var place_state := brain.choose_state({"interesting_targets": 1.0, "target_place": "library"})
    if place_state != "wander":
        _fail("favorite target place did not bias movement: " + place_state)
        return
    brain.step(60.0, {})
    durable = brain.long_term_snapshot()
    relationships = durable.get("relationships", [])
    places = durable.get("places", [])
    if relationships.is_empty() or places.is_empty() or float(relationships[0].get("hours_since_contact", 0.0)) <= 0.0 or float(places[0].get("hours_since_visit", 0.0)) <= 0.0:
        _fail("long-term memory did not age")
        return

    var agent := VaultCharacterAgent.new()
    root.add_child(agent)
    var production := _borderline_snapshot()
    production["memory"] = [{
        "kind": "social", "subject": "alice", "valence": 1.0,
        "importance": 1.0, "age": 0.0, "ttl": 180.0,
    }]
    production["long_term_memory"] = durable.duplicate(true)
    agent.setup("MEMORY-CI", Vector2.ZERO, production)
    var production_memory := agent.brain.memory_snapshot()
    var production_state := agent.brain.choose_state(focused_context)
    if production_memory.size() != 1 or production_state != "social":
        _fail("production CharacterAgent did not consume memory snapshot")
        agent.queue_free()
        return
    var roundtrip := agent.brain.snapshot()
    if typeof(roundtrip.get("memory", null)) != TYPE_ARRAY or roundtrip["memory"].size() != 1:
        _fail("memory did not round-trip through brain snapshot")
        agent.queue_free()
        return
    var roundtrip_long = roundtrip.get("long_term_memory", null)
    if typeof(roundtrip_long) != TYPE_DICTIONARY or roundtrip_long.get("relationships", []).size() != 1 or str(roundtrip_long.get("favorite_place", "")) != "library":
        _fail("long-term memory did not round-trip through production CharacterAgent")
        agent.queue_free()
        return

    print(
        "KROLIK_MEMORY capacity=", bounded.size(),
        " dedupe=true expired=true legacy=", legacy_state,
        " unfocused=", unfocused_state,
        " focused=", focused_state,
        " hard_gate=", hard_gate,
        " production_entries=", production_memory.size(),
        " production_state=", production_state,
        " long_social=", long_social_state,
        " favorite_place=", str(roundtrip_long.get("favorite_place", ""))
    )
    agent.queue_free()
    await process_frame
    quit(0)
