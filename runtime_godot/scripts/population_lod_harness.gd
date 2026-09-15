extends SceneTree

const MANIFEST_PATH := "res://.ci_vertical_slice/exports/runtime/ci_core_slice/manifest.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("KROLIK_POPULATION_LOD_FAIL " + message)
    quit(1)

func _memory_age(agent: VaultCharacterAgent) -> float:
    var snapshot := agent.brain.memory_snapshot()
    if snapshot.is_empty():
        return -1.0
    var first: Dictionary = snapshot[0]
    return float(first.get("age", -1.0))

func _run() -> void:
    var manifest_abs := ProjectSettings.globalize_path(MANIFEST_PATH)
    if not FileAccess.file_exists(manifest_abs):
        _fail("production vertical-slice manifest missing: " + manifest_abs)
        return

    var agent := VaultCharacterAgent.new()
    root.add_child(agent)
    agent.setup("lod-proof", Vector2(100.0, 120.0), {})
    if not agent.load_runtime_manifest(manifest_abs):
        _fail("production manifest rejected")
        return
    agent.brain.apply_snapshot({
        "enabled": true,
        "state": "wander",
        "profile": {
            "mobility": "free", "routine": "explorer", "autonomy": 1.0,
            "wander": 1.0, "walk_speed": 1.0,
            "traits": {"curiosity": 0.8, "sociability": 0.5, "boldness": 0.5, "patience": 0.5, "resilience": 0.5},
        },
        "needs": {"energy": 1.0, "comfort": 0.7, "curiosity": 1.0, "social": 0.35},
        "memory": [{
            "kind": "interesting", "subject": "lod-proof", "valence": 0.2,
            "importance": 0.5, "age": 0.0, "ttl": 60.0,
        }],
    })
    agent.collision_layer = 5
    agent.collision_mask = 3
    agent.collision_rig.set_deferred("disabled", false) if false else null
    agent.world_targets = [agent.global_position + Vector2(180.0, 0.0)]
    agent.target_position = agent.world_targets[0]

    if agent.skinned_visual == null or not is_instance_valid(agent.skinned_visual) or agent.flat_sprite != null:
        _fail("production GPU skin was not created before LOD")
        return

    var lod := VaultPopulationLOD.new()
    root.add_child(lod)
    lod.configure({
        "enabled": true,
        "focus_position": agent.global_position,
        "sleep_radius": 120.0,
        "wake_radius": 90.0,
        "reassess_interval": 0.05,
    })
    if not lod.register_agent(agent):
        _fail("failed to register production agent")
        return
    lod.force_reassess()
    if lod.is_sleeping(agent) or not agent.visible or not agent.is_physics_processing():
        _fail("near production agent started asleep")
        return

    var start_position := agent.global_position
    var phase_before := agent.phase
    var age_before := _memory_age(agent)
    lod.set_focus_position(agent.global_position + Vector2(1000.0, 0.0), true)
    if not lod.is_sleeping(agent):
        _fail("far agent did not enter sleep tier")
        return
    if agent.visible or agent.is_physics_processing():
        _fail("sleep tier did not disable render/physics")
        return
    if agent.collision_layer != 0 or agent.collision_mask != 0:
        _fail("sleep tier did not disable collisions")
        return

    for _frame in range(18):
        await physics_frame
    var sleep_drift := agent.global_position.distance_to(start_position)
    if sleep_drift > 0.01:
        _fail("sleeping agent moved physically: " + str(sleep_drift))
        return

    lod.set_focus_position(agent.global_position, true)
    if lod.is_sleeping(agent) or not agent.visible or not agent.is_physics_processing():
        _fail("agent did not wake cleanly")
        return
    if agent.collision_layer != 5 or agent.collision_mask != 3:
        _fail("wake did not restore collision layers")
        return
    var caught_up := agent.phase - phase_before
    var age_after := _memory_age(agent)
    if caught_up < 0.15:
        _fail("semantic phase did not catch up after sleep: " + str(caught_up))
        return
    if age_before < 0.0 or age_after <= age_before + 0.10:
        _fail("short-term memory did not age through sleep: before=%s after=%s" % [age_before, age_after])
        return

    var wake_start := agent.global_position
    agent.target_position = wake_start + Vector2(180.0, 0.0)
    agent.world_targets = [agent.target_position]
    for _frame in range(36):
        await physics_frame
    var wake_travel := agent.global_position.distance_to(wake_start)
    if wake_travel < 4.0:
        _fail("woken production agent did not resume movement: " + str(wake_travel))
        return
    if agent.skinned_visual == null or not is_instance_valid(agent.skinned_visual) or not agent.visible:
        _fail("GPU visual was not retained across sleep/wake")
        return

    var tiers := lod.tier_snapshot()
    print(
        "KROLIK_POPULATION_LOD status=ok registered=", tiers.get("registered"),
        " sleeping=", tiers.get("sleeping"),
        " caught_up=", snappedf(caught_up, 0.001),
        " memory_age_before=", snappedf(age_before, 0.001),
        " memory_age_after=", snappedf(age_after, 0.001),
        " sleep_drift=", snappedf(sleep_drift, 0.001),
        " wake_travel=", snappedf(wake_travel, 0.01),
        " gpu_skin=true"
    )
    lod.clear(true)
    agent.queue_free()
    lod.queue_free()
    await process_frame
    quit(0)
