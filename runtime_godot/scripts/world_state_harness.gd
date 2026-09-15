extends SceneTree

const PACKAGE_ROOT := "res://.ci_vertical_slice/exports/runtime"
const MANIFEST_PATH := "res://.ci_vertical_slice/exports/runtime/ci_core_slice/manifest.json"
const SAVE_PATH := "user://krolik-world-state-ci.json"

func _initialize() -> void:
    call_deferred("_run")

func _stage(name: String) -> void:
    print("KROLIK_WORLD_STATE_STAGE " + name)

func _fail(message: String) -> void:
    push_error("KROLIK_WORLD_STATE_FAIL " + message)
    quit(1)

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
                "curiosity": 0.5, "sociability": 0.5, "boldness": 0.5,
                "patience": 0.5, "resilience": 0.5,
            },
        },
        "needs": {"energy": 1.0, "comfort": 1.0, "curiosity": 0.0, "social": 0.0},
        "memory": [{
            "kind": "interesting",
            "subject": subject,
            "valence": 0.2,
            "importance": 0.5,
            "age": memory_age,
            "ttl": 120.0,
        }],
    }

func _memory_age(agent: VaultCharacterAgent) -> float:
    var memory := agent.brain.memory_snapshot()
    if memory.is_empty():
        return -1.0
    return float(memory[0].get("age", -1.0))

func _find_agent(agents: Array, character_id: String) -> VaultCharacterAgent:
    for value in agents:
        var agent := value as VaultCharacterAgent
        if agent != null and is_instance_valid(agent) and agent.character_id == character_id:
            return agent
    return null

func _spawn_character(parent: Node, character_id: String, position: Vector2, phase: float, memory_age: float) -> VaultCharacterAgent:
    var manifest_abs := ProjectSettings.globalize_path(MANIFEST_PATH)
    var agent := VaultCharacterAgent.new()
    parent.add_child(agent)
    agent.setup(character_id, position, {})
    if not agent.load_runtime_manifest(manifest_abs):
        agent.queue_free()
        return null
    agent.character_id = character_id
    agent.brain.apply_snapshot(_mind(character_id, memory_age))
    agent.position = position
    agent.home_position = position
    agent.target_position = position
    var no_targets: Array[Vector2] = []
    agent.world_targets = no_targets
    agent.phase = phase
    agent.velocity = Vector2.ZERO
    return agent

func _run() -> void:
    _stage("start")
    var manifest_abs := ProjectSettings.globalize_path(MANIFEST_PATH)
    var package_root_abs := ProjectSettings.globalize_path(PACKAGE_ROOT)
    if not FileAccess.file_exists(manifest_abs):
        _fail("production runtime package is missing")
        return

    var world := Node2D.new()
    world.name = "WorldBeforeSave"
    root.add_child(world)
    var lod := VaultPopulationLOD.new()
    world.add_child(lod)
    lod.configure({
        "enabled": true,
        "resource_residency": true,
        "focus_position": Vector2(100.0, 100.0),
        "full_radius": 90.0,
        "sleep_radius": 240.0,
        "wake_radius": 180.0,
        "reassess_interval": 0.05,
        "proxy_max_height": 128,
    })

    var agents: Array[VaultCharacterAgent] = []
    var specs := [
        {"id": "world-full", "position": Vector2(100.0, 100.0), "phase": 1.25, "memory_age": 1.0},
        {"id": "world-reduced", "position": Vector2(240.0, 100.0), "phase": 2.50, "memory_age": 2.0},
        {"id": "world-sleep", "position": Vector2(500.0, 100.0), "phase": 3.75, "memory_age": 3.0},
    ]
    for spec_value in specs:
        var spec: Dictionary = spec_value
        var agent := _spawn_character(world, str(spec.get("id")), spec.get("position"), float(spec.get("phase")), float(spec.get("memory_age")))
        if agent == null:
            _fail("failed to load production package for " + str(spec.get("id")))
            return
        if not lod.register_agent(agent, manifest_abs):
            _fail("failed to register " + agent.character_id)
            return
        agents.append(agent)
    lod.force_reassess()
    _stage("spawned")

    if lod.full_count() != 1 or lod.reduced_count() != 1 or lod.sleeping_count() != 1:
        _fail("initial world did not populate all three LOD tiers: " + str(lod.tier_snapshot()))
        return
    for _frame in range(18):
        await physics_frame
    _stage("sleep_time_accumulated")
    var sleep_agent := _find_agent(agents, "world-sleep")
    if sleep_agent == null or lod.pending_sleep_seconds(sleep_agent) < 0.15:
        _fail("sleeping agent did not accumulate pending semantic time")
        return

    var persistence := VaultWorldState.new()
    var doc := persistence.capture("ci-world", agents, lod, package_root_abs)
    if doc.is_empty():
        _fail("capture failed: " + persistence.last_error)
        return
    _stage("captured")
    if str(doc.get("schema")) != VaultWorldState.SCHEMA or int(doc.get("format_version")) != VaultWorldState.FORMAT_VERSION:
        _fail("versioned world-state header missing")
        return
    if not persistence.save_atomic(SAVE_PATH, doc):
        _fail("first save failed: " + persistence.last_error)
        return
    _stage("saved_first")
    if not persistence.save_atomic(SAVE_PATH, doc):
        _fail("overwrite save failed: " + persistence.last_error)
        return
    _stage("saved_overwrite")

    var saved_file := ProjectSettings.globalize_path(SAVE_PATH)
    if not FileAccess.file_exists(saved_file):
        _fail("world-state file was not written")
        return
    if FileAccess.file_exists(saved_file + ".bak"):
        _fail("successful save left stale backup file")
        return

    var traversal_doc: Dictionary = doc.duplicate(true)
    traversal_doc["characters"][0]["package_manifest"] = "../escape/manifest.json"
    if persistence.validate(traversal_doc):
        _fail("path traversal world state passed validation")
        return

    var hash_doc: Dictionary = doc.duplicate(true)
    hash_doc["characters"][0]["manifest_sha256"] = "0".repeat(64)
    if not persistence.validate(hash_doc):
        _fail("hash-tampered document should remain structurally valid")
        return
    var tamper_parent := Node2D.new()
    root.add_child(tamper_parent)
    var before_children := tamper_parent.get_child_count()
    var bad_restore := persistence.restore(hash_doc, tamper_parent, package_root_abs)
    if not bad_restore.is_empty() or tamper_parent.get_child_count() != before_children:
        _fail("hash mismatch mutated scene before rejection")
        return
    tamper_parent.queue_free()
    _stage("security_guards")

    var saved_sleep_record: Dictionary = {}
    for record_value in doc.get("characters", []):
        var record: Dictionary = record_value
        if str(record.get("character_id")) == "world-sleep":
            saved_sleep_record = record
            break
    if saved_sleep_record.is_empty():
        _fail("sleeping record missing from captured document")
        return
    var saved_lod_doc: Dictionary = saved_sleep_record.get("lod", {})
    var saved_brain: Dictionary = saved_sleep_record.get("brain", {})
    var saved_memory: Array = saved_brain.get("memory", [])
    if saved_memory.is_empty():
        _fail("sleeping record lost its memory snapshot")
        return
    var saved_sleep_pending := float(saved_lod_doc.get("sleep_elapsed", 0.0))
    var saved_sleep_phase := float(saved_sleep_record.get("phase", 0.0))
    var saved_sleep_memory := float(saved_memory[0].get("age", -1.0))

    lod.clear(false)
    world.queue_free()
    await process_frame
    await process_frame
    _stage("destroyed_original")

    var loaded := persistence.load_file(SAVE_PATH)
    if loaded.is_empty():
        _fail("load_file rejected its own save: " + persistence.last_error)
        return
    _stage("loaded_file")
    var restored_world := Node2D.new()
    restored_world.name = "WorldAfterReload"
    root.add_child(restored_world)
    var restored := persistence.restore(loaded, restored_world, package_root_abs)
    if restored.is_empty():
        _fail("restore failed: " + persistence.last_error)
        return
    _stage("restored_scene")
    var restored_agents: Array = restored.get("agents", [])
    var restored_lod := restored.get("lod") as VaultPopulationLOD
    if restored_agents.size() != 3 or restored_lod == null:
        _fail("restored population shape is wrong")
        return
    if restored_lod.full_count() != 1 or restored_lod.reduced_count() != 1 or restored_lod.sleeping_count() != 1:
        _fail("restored LOD distribution changed: " + str(restored_lod.tier_snapshot()))
        return

    var full_agent := _find_agent(restored_agents, "world-full")
    var reduced_agent := _find_agent(restored_agents, "world-reduced")
    var restored_sleep := _find_agent(restored_agents, "world-sleep")
    if full_agent == null or reduced_agent == null or restored_sleep == null:
        _fail("restored character ids are incomplete")
        return
    if full_agent.skinned_visual == null or full_agent.collision_rig == null or restored_lod.resource_mode_for(full_agent) != VaultPopulationLOD.RESIDENT:
        _fail("full character did not restore full runtime resources")
        return
    if reduced_agent.skinned_visual != null or reduced_agent.collision_rig != null or reduced_agent.character_texture == null or restored_lod.resource_mode_for(reduced_agent) != VaultPopulationLOD.PROXY:
        _fail("reduced character did not restore proxy resources")
        return
    if restored_sleep.character_texture != null or restored_sleep.skinned_visual != null or restored_sleep.collision_rig != null or restored_lod.resource_mode_for(restored_sleep) != VaultPopulationLOD.RELEASED:
        _fail("sleeping character did not restore released residency")
        return

    if restored_sleep.phase < saved_sleep_phase + saved_sleep_pending - 0.01:
        _fail("saved pending sleep time was lost from phase")
        return
    if _memory_age(restored_sleep) < saved_sleep_memory + saved_sleep_pending - 0.02:
        _fail("saved pending sleep time was lost from short-term memory")
        return

    restored_lod.set_focus_position(restored_sleep.global_position, true)
    _stage("wake_requested")
    if restored_lod.tier_for(restored_sleep) != VaultPopulationLOD.TIER_FULL:
        _fail("restored sleeping character failed to wake into full tier")
        return
    if restored_sleep.skinned_visual == null or restored_sleep.collision_rig == null or restored_sleep.character_texture == null:
        _fail("wake after world reload did not reconstruct production resources")
        return

    var saved_count := int(doc.get("characters", []).size())
    print(
        "KROLIK_WORLD_STATE status=ok schema=", VaultWorldState.SCHEMA,
        " characters=", saved_count,
        " tiers=1/1/1",
        " sleep_pending=", snappedf(saved_sleep_pending, 0.001),
        " restored_phase=", snappedf(restored_sleep.phase, 0.001),
        " restored_memory_age=", snappedf(_memory_age(restored_sleep), 0.001),
        " hash_guard=true traversal_guard=true atomic_replace=true gpu_wake=true"
    )

    restored_lod.clear(false)
    restored_world.queue_free()
    if FileAccess.file_exists(saved_file):
        DirAccess.remove_absolute(saved_file)
    await process_frame
    quit(0)
