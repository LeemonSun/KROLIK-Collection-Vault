extends SceneTree

const PACKAGE_ROOT := "res://.ci_vertical_slice/exports/runtime"
const MANIFEST_PATH := "res://.ci_vertical_slice/exports/runtime/ci_core_slice/manifest.json"
const SAVE_PATH := "user://krolik-world-state-scale-ci.json"
const AGENT_COUNT := 500
const EXPECTED_FULL := 80
const EXPECTED_REDUCED := 160
const EXPECTED_SLEEP := 260
const FOCUS := Vector2(100.0, 100.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("KROLIK_WORLD_STATE_SCALE_FAIL " + message)
    quit(1)

func _stage(name: String) -> void:
    print("KROLIK_WORLD_STATE_SCALE_STAGE ", name)

func _mind(subject: String, memory_age: float) -> Dictionary:
    return {
        "enabled": true,
        "state": "idle",
        "profile": {
            "mobility": "auto",
            "routine": "balanced",
            "autonomy": 0.0,
            "wander": 0.0,
            "social": 0.0,
            "walk_speed": 1.0,
            "traits": {
                "curiosity": 0.5,
                "sociability": 0.5,
                "boldness": 0.5,
                "patience": 0.5,
                "resilience": 0.5,
            },
        },
        "needs": {
            "energy": 0.9,
            "comfort": 0.8,
            "curiosity": 0.1,
            "social": 0.1,
        },
        "memory": [{
            "kind": "scale-fixture",
            "subject": subject,
            "valence": 0.15,
            "importance": 0.4,
            "age": memory_age,
            "ttl": 300.0,
        }],
    }

func _position_for(index: int) -> Vector2:
    var radius := 0.0
    if index < EXPECTED_FULL:
        radius = 36.0 + float(index % 8)
    elif index < EXPECTED_FULL + EXPECTED_REDUCED:
        radius = 130.0 + float(index % 12)
    else:
        radius = 310.0 + float(index % 20)
    var angle := TAU * fmod(float(index) * 0.61803398875, 1.0)
    return FOCUS + Vector2(cos(angle), sin(angle)) * radius

func _spawn_character(parent: Node, manifest_abs: String, index: int) -> VaultCharacterAgent:
    var character_id := "scale-%03d" % index
    var position := _position_for(index)
    var agent := VaultCharacterAgent.new()
    parent.add_child(agent)
    agent.setup(character_id, position, {})
    var needs_full_resources := index < EXPECTED_FULL
    if not agent.load_runtime_manifest(manifest_abs, needs_full_resources):
        agent.queue_free()
        return null
    agent.character_id = character_id
    agent.brain.apply_snapshot(_mind(character_id, float(index % 17) * 0.1))
    agent.position = position
    agent.home_position = position
    agent.target_position = position
    var no_targets: Array[Vector2] = []
    agent.world_targets = no_targets
    agent.phase = float(index % 31) * 0.13
    agent.velocity = Vector2.ZERO
    return agent

func _elapsed_ms(start_usec: int) -> float:
    return float(Time.get_ticks_usec() - start_usec) / 1000.0

func _run() -> void:
    _stage("start")
    VaultRuntimePackageCache.reset_cache()
    var manifest_abs := ProjectSettings.globalize_path(MANIFEST_PATH)
    var package_root_abs := ProjectSettings.globalize_path(PACKAGE_ROOT)
    if not FileAccess.file_exists(manifest_abs):
        _fail("production runtime package is missing")
        return

    var world := Node2D.new()
    world.name = "ScaleWorldBeforeSave"
    root.add_child(world)
    var lod := VaultPopulationLOD.new()
    world.add_child(lod)
    lod.configure({
        "enabled": true,
        "resource_residency": true,
        "focus_position": FOCUS,
        "full_radius": 90.0,
        "sleep_radius": 240.0,
        "wake_radius": 180.0,
        "reassess_interval": 0.05,
        "proxy_max_height": 128,
    })

    var agents: Array[VaultCharacterAgent] = []
    var spawn_start := Time.get_ticks_usec()
    for index in range(AGENT_COUNT):
        var agent := _spawn_character(world, manifest_abs, index)
        if agent == null:
            _fail("failed to load production package at index %d" % index)
            return
        if not lod.register_agent(agent, manifest_abs):
            _fail("failed to register LOD at index %d" % index)
            return
        agents.append(agent)
        if (index + 1) % 100 == 0:
            _stage("spawned_%d" % (index + 1))
    lod.force_reassess()
    var spawn_ms := _elapsed_ms(spawn_start)
    var cache_after_spawn := VaultRuntimePackageCache.stats_snapshot()
    if int(cache_after_spawn.get("manifest_parses", -1)) != 1 or int(cache_after_spawn.get("texture_decodes", -1)) != 1:
        _fail("runtime package cache did not collapse repeated package IO: " + str(cache_after_spawn))
        return
    if int(cache_after_spawn.get("hits", 0)) < AGENT_COUNT - 1:
        _fail("runtime package cache hit count too low: " + str(cache_after_spawn))
        return
    _stage("spawn_complete")

    if lod.full_count() != EXPECTED_FULL or lod.reduced_count() != EXPECTED_REDUCED or lod.sleeping_count() != EXPECTED_SLEEP:
        _fail("unexpected initial tier distribution: " + str(lod.tier_snapshot()))
        return

    for _frame in range(12):
        await physics_frame
    _stage("simulation_ready")

    var persistence := VaultWorldState.new()
    var capture_start := Time.get_ticks_usec()
    var doc := persistence.capture("ci-scale-world", agents, lod, package_root_abs)
    var capture_ms := _elapsed_ms(capture_start)
    if doc.is_empty() or int(doc.get("characters", []).size()) != AGENT_COUNT:
        _fail("capture failed or lost characters: " + persistence.last_error)
        return
    _stage("captured")

    var save_start := Time.get_ticks_usec()
    if not persistence.save_atomic(SAVE_PATH, doc):
        _fail("save failed: " + persistence.last_error)
        return
    var save_ms := _elapsed_ms(save_start)
    var saved_file := ProjectSettings.globalize_path(SAVE_PATH)
    var save_text := FileAccess.get_file_as_string(saved_file)
    var save_bytes := save_text.to_utf8_buffer().size()
    if save_bytes <= 0:
        _fail("save file is empty")
        return
    _stage("saved")

    lod.clear(false)
    world.queue_free()
    await process_frame
    await process_frame
    _stage("destroyed")

    var load_start := Time.get_ticks_usec()
    var loaded := persistence.load_file(SAVE_PATH)
    var load_ms := _elapsed_ms(load_start)
    if loaded.is_empty() or int(loaded.get("characters", []).size()) != AGENT_COUNT:
        _fail("load failed or lost characters: " + persistence.last_error)
        return
    _stage("loaded")

    var restored_world := Node2D.new()
    restored_world.name = "ScaleWorldAfterReload"
    root.add_child(restored_world)
    var restore_start := Time.get_ticks_usec()
    var restored := persistence.restore(loaded, restored_world, package_root_abs)
    var restore_ms := _elapsed_ms(restore_start)
    if restored.is_empty():
        _fail("restore failed: " + persistence.last_error)
        return
    _stage("restored")

    var restored_agents: Array = restored.get("agents", [])
    var restored_lod := restored.get("lod") as VaultPopulationLOD
    if restored_agents.size() != AGENT_COUNT or restored_lod == null:
        _fail("restored population shape is wrong")
        return
    if restored_lod.full_count() != EXPECTED_FULL or restored_lod.reduced_count() != EXPECTED_REDUCED or restored_lod.sleeping_count() != EXPECTED_SLEEP:
        _fail("restored tier distribution changed: " + str(restored_lod.tier_snapshot()))
        return

    var restored_first := restored_agents[0] as VaultCharacterAgent
    var restored_last := restored_agents[restored_agents.size() - 1] as VaultCharacterAgent
    if restored_first == null or restored_last == null:
        _fail("restored agent references are invalid")
        return
    if restored_first.character_id != "scale-000" or restored_last.character_id != "scale-499":
        _fail("deterministic character ordering changed")
        return
    if restored_first.skinned_visual == null or restored_first.collision_rig == null:
        _fail("full-tier resources missing after scale restore")
        return
    if restored_last.character_texture != null or restored_last.skinned_visual != null or restored_last.collision_rig != null:
        _fail("sleep-tier resources were not released after scale restore")
        return

    var cache_final := VaultRuntimePackageCache.stats_snapshot()
    print(
        "KROLIK_WORLD_STATE_SCALE status=ok agents=", AGENT_COUNT,
        " full=", EXPECTED_FULL,
        " reduced=", EXPECTED_REDUCED,
        " sleeping=", EXPECTED_SLEEP,
        " spawn_ms=", snappedf(spawn_ms, 0.01),
        " capture_ms=", snappedf(capture_ms, 0.01),
        " save_ms=", snappedf(save_ms, 0.01),
        " load_ms=", snappedf(load_ms, 0.01),
        " restore_ms=", snappedf(restore_ms, 0.01),
        " save_bytes=", save_bytes,
        " cache_parses=", int(cache_final.get("manifest_parses", -1)),
        " cache_decodes=", int(cache_final.get("texture_decodes", -1)),
        " cache_hits=", int(cache_final.get("hits", -1))
    )

    restored_lod.clear(false)
    restored_world.queue_free()
    if FileAccess.file_exists(saved_file):
        DirAccess.remove_absolute(saved_file)
    await process_frame
    quit(0)
