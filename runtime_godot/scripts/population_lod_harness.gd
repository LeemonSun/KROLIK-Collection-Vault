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
    agent.character_id = "lod-proof"
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
    agent.world_targets = [agent.global_position + Vector2(180.0, 0.0)]
    agent.target_position = agent.world_targets[0]

    if agent.skinned_visual == null or not is_instance_valid(agent.skinned_visual) or agent.flat_sprite != null:
        _fail("production GPU skin was not created before LOD")
        return
    if agent.collision_rig == null or agent.collision_rig.stats().get("capsules", 0) <= 0:
        _fail("production collision rig was not created before LOD")
        return

    var original_skin := agent.skinned_visual
    var original_collision_rig := agent.collision_rig
    var original_facial_enabled := agent.facial_state.enabled
    var original_secondary_enabled := agent.secondary_motion_enabled
    var original_texture_size := agent.character_texture.get_size()

    var lod := VaultPopulationLOD.new()
    root.add_child(lod)
    lod.configure({
        "enabled": true,
        "resource_residency": true,
        "focus_position": agent.global_position,
        "full_radius": 90.0,
        "sleep_radius": 240.0,
        "wake_radius": 180.0,
        "reassess_interval": 0.05,
        "proxy_max_height": 128,
    })
    if not lod.register_agent(agent, manifest_abs):
        _fail("failed to register production agent")
        return
    lod.force_reassess()
    if lod.tier_for(agent) != VaultPopulationLOD.TIER_FULL:
        _fail("near production agent did not start in full tier")
        return
    if lod.resource_mode_for(agent) != VaultPopulationLOD.RESIDENT:
        _fail("full agent did not start resident")
        return

    # Middle-distance tier: keep AI/locomotion live, but release full skin and
    # collision resources and keep only a downscaled visual proxy.
    var reduced_start := agent.global_position
    lod.set_focus_position(agent.global_position + Vector2(150.0, 0.0), true)
    if lod.tier_for(agent) != VaultPopulationLOD.TIER_REDUCED:
        _fail("middle-distance agent did not enter reduced tier")
        return
    if lod.resource_mode_for(agent) != VaultPopulationLOD.PROXY:
        _fail("reduced tier did not enter proxy residency mode")
        return
    if not agent.visible or not agent.is_physics_processing():
        _fail("reduced tier incorrectly disabled visible physics")
        return
    if agent.skinned_visual != null or agent.collision_rig != null:
        _fail("reduced tier retained full skin/collision resources")
        return
    if agent.character_texture == null or agent.character_texture.get_height() > 128:
        _fail("reduced tier did not retain only a bounded proxy texture")
        return
    if agent.character_texture.get_size() == original_texture_size:
        _fail("reduced tier proxy was not downscaled")
        return
    if agent.collision_layer != 0 or agent.collision_mask != 0:
        _fail("reduced tier did not drop collision participation")
        return
    if agent.facial_state.enabled or agent.secondary_motion_enabled:
        _fail("reduced tier did not suspend procedural detail layers")
        return
    for _frame in range(24):
        await physics_frame
    var reduced_travel := agent.global_position.distance_to(reduced_start)
    if reduced_travel < 2.0:
        _fail("reduced tier stopped locomotion: " + str(reduced_travel))
        return

    # Far tier: release even the proxy texture and freeze physical simulation.
    var sleep_start := agent.global_position
    var phase_before_sleep := agent.phase
    var age_before_sleep := _memory_age(agent)
    lod.set_focus_position(agent.global_position + Vector2(1000.0, 0.0), true)
    if lod.tier_for(agent) != VaultPopulationLOD.TIER_SLEEP:
        _fail("far agent did not enter sleep tier")
        return
    if lod.resource_mode_for(agent) != VaultPopulationLOD.RELEASED:
        _fail("sleep tier did not release visual resources")
        return
    if agent.character_texture != null or agent.skinned_visual != null or agent.collision_rig != null:
        _fail("sleep tier retained character texture/skin/collision")
        return
    if agent.visible or agent.is_physics_processing():
        _fail("sleep tier did not disable render/physics")
        return
    for _frame in range(18):
        await physics_frame
    var sleep_drift := agent.global_position.distance_to(sleep_start)
    if sleep_drift > 0.01:
        _fail("sleeping agent moved physically: " + str(sleep_drift))
        return
    if absf(agent.phase - phase_before_sleep) > 0.01:
        _fail("sleeping agent physics phase advanced before wake")
        return
    if lod.pending_sleep_seconds(agent) < 0.15:
        _fail("sleep tier did not accumulate deterministic simulation time")
        return

    # Wake into full detail. Full GPU skin/collision are rebuilt from the same
    # runtime package while the live brain/id/position remain authoritative.
    lod.set_focus_position(agent.global_position, true)
    if lod.tier_for(agent) != VaultPopulationLOD.TIER_FULL:
        _fail("agent did not wake into full tier: " + str(lod.entry_snapshot(agent)))
        return
    if lod.resource_mode_for(agent) != VaultPopulationLOD.RESIDENT:
        _fail("wake did not restore resident resources")
        return
    if not agent.visible or not agent.is_physics_processing():
        _fail("agent did not wake cleanly")
        return
    if agent.character_id != "lod-proof":
        _fail("runtime package reload overwrote live character identity")
        return
    if agent.collision_layer != 5 or agent.collision_mask != 3:
        _fail("wake did not restore collision layers")
        return
    if agent.skinned_visual == null or not is_instance_valid(agent.skinned_visual):
        _fail("wake did not reconstruct GPU skin")
        return
    if agent.collision_rig == null or agent.collision_rig.stats().get("capsules", 0) <= 0:
        _fail("wake did not reconstruct collision rig")
        return
    if agent.character_texture == null or agent.character_texture.get_size() != original_texture_size:
        _fail("wake did not restore full-resolution character texture")
        return
    if agent.skinned_visual == original_skin:
        _fail("wake reused old skin instead of reconstructing released resources")
        return
    if agent.collision_rig == original_collision_rig:
        _fail("wake reused old collision rig instead of reconstructing released resources")
        return
    if agent.facial_state.enabled != original_facial_enabled or agent.secondary_motion_enabled != original_secondary_enabled:
        _fail("wake did not restore detailed animation controller flags")
        return

    var caught_up := agent.phase - phase_before_sleep
    var age_after_sleep := _memory_age(agent)
    if caught_up < 0.15:
        _fail("semantic phase did not catch up after sleep: " + str(caught_up))
        return
    if age_before_sleep < 0.0 or age_after_sleep <= age_before_sleep + 0.10:
        _fail("short-term memory did not age through sleep: before=%s after=%s" % [age_before_sleep, age_after_sleep])
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

    var tiers := lod.tier_snapshot()
    if int(tiers.get("residency_failures", 0)) != 0:
        _fail("resource residency emitted errors: " + str(lod.entry_snapshot(agent)))
        return
    print(
        "KROLIK_POPULATION_LOD status=ok registered=", tiers.get("registered"),
        " full=", tiers.get("full"),
        " reduced=", tiers.get("reduced"),
        " sleeping=", tiers.get("sleeping"),
        " resident=", tiers.get("resident"),
        " proxy=", tiers.get("proxy"),
        " released=", tiers.get("released"),
        " reduced_travel=", snappedf(reduced_travel, 0.01),
        " caught_up=", snappedf(caught_up, 0.001),
        " memory_age_before=", snappedf(age_before_sleep, 0.001),
        " memory_age_after=", snappedf(age_after_sleep, 0.001),
        " sleep_drift=", snappedf(sleep_drift, 0.001),
        " wake_travel=", snappedf(wake_travel, 0.01),
        " gpu_skin_reconstructed=true collision_reconstructed=true"
    )
    lod.clear(true)
    agent.queue_free()
    lod.queue_free()
    await process_frame
    quit(0)
