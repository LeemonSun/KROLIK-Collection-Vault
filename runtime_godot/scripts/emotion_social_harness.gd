extends SceneTree

func _fail(message: String) -> void:
    push_error("KROLIK_D5_EMOTION_SOCIAL_FAIL %s" % message)
    quit(1)

func _init() -> void:
    var timid := VaultAgentBrain.new()
    timid.apply_snapshot({
        "profile": {"traits": {"boldness": 0.05, "resilience": 0.10, "patience": 0.4}},
        "needs": {"energy": 0.8, "comfort": 0.7, "curiosity": 0.4, "social": 0.4},
    })
    timid.step(1.0, {"bound": true, "interaction_mode": "restrained", "constraint_kind": "shackles", "constraint_severity": 0.95, "constraint_novelty": 0.8, "threat": 0.72, "witnesses": 3})
    var timid_affect := timid.affect_snapshot()

    var defiant := VaultAgentBrain.new()
    defiant.apply_snapshot({
        "profile": {"traits": {"boldness": 0.95, "resilience": 0.95, "patience": 0.2}},
        "needs": {"energy": 0.8, "comfort": 0.7, "curiosity": 0.4, "social": 0.4},
    })
    defiant.step(1.0, {"bound": true, "interaction_mode": "restrained", "constraint_kind": "shackles", "constraint_severity": 0.95, "constraint_novelty": 0.8, "threat": 0.72, "witnesses": 3})
    var defiant_affect := defiant.affect_snapshot()
    if float(timid_affect.get("fear", 0.0)) <= float(defiant_affect.get("fear", 0.0)):
        _fail("personality did not reduce fear")
        return
    if float(defiant_affect.get("anger", 0.0)) <= float(timid_affect.get("anger", 0.0)):
        _fail("bold personality did not redirect reaction toward anger")
        return
    timid.step(0.5, {"released": true, "safe": true})
    if float(timid.affect_snapshot().get("relief", 0.0)) <= 0.25:
        _fail("release did not produce relief")
        return

    var face := VaultFacialState.new()
    face.configure({}, 7)
    if not face.set_mood(str(timid_affect.get("facial_mood", "calm")), 0.9, 0.1):
        _fail("semantic emotion has no facial preset")
        return

    var root := Node2D.new()
    get_root().add_child(root)
    var a := VaultCharacterAgent.new()
    var b := VaultCharacterAgent.new()
    root.add_child(a)
    root.add_child(b)
    a.setup("alice", Vector2(100, 100), {"profile": {"routine": "social", "social": 0.95, "traits": {"sociability": 0.9}}, "needs": {"energy": 0.8, "comfort": 0.8, "curiosity": 0.3, "social": 0.95}})
    b.setup("boris", Vector2(125, 100), {"profile": {"routine": "social", "social": 0.95, "traits": {"sociability": 0.8}}, "needs": {"energy": 0.8, "comfort": 0.8, "curiosity": 0.3, "social": 0.95}})
    a.brain.state = "social"
    b.brain.state = "social"
    var manager := VaultSocialEncounterManager.new()
    manager.scan_interval = 0.1
    manager.encounter_duration = 0.4
    var agents: Array = [a, b]
    for _step in range(12):
        manager.step(0.1, agents)
        a.brain.state = "social"
        b.brain.state = "social"
    if manager.completed_total < 1:
        _fail("close social agents never completed encounter")
        return
    var rel_a := a.relationship_to("boris")
    var rel_b := b.relationship_to("alice")
    if rel_a.is_empty() or rel_b.is_empty():
        _fail("encounter did not enter D4 durable relationship memory")
        return
    if int(rel_a.get("interactions", 0)) < 1 or int(rel_b.get("interactions", 0)) < 1:
        _fail("relationship interaction count missing")
        return
    if manager.last_neighbor_checks > 36:
        _fail("two-agent bounded neighbor budget violated")
        return
    print("KROLIK_D5_EMOTION_SOCIAL status=ok timid_mood=%s timid_fear=%.3f defiant_mood=%s defiant_anger=%.3f encounters=%d affinity_a=%.3f affinity_b=%.3f neighbor_checks=%d" % [str(timid_affect.get("mood", "")), float(timid_affect.get("fear", 0.0)), str(defiant_affect.get("mood", "")), float(defiant_affect.get("anger", 0.0)), manager.completed_total, float(rel_a.get("affinity", 0.0)), float(rel_b.get("affinity", 0.0)), manager.last_neighbor_checks])
    root.free()
    quit(0)
