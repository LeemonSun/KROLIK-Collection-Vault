extends SceneTree

## Mixed-package persistence regression. Saves and restores one world populated
## from four distinct sealed runtime packages and proves package references stay
## distinct across capture -> disk -> destroy -> reload -> restore.

const PACKAGE_ROOT := "res://.ci_multi_art/exports/runtime"
const SAVE_PATH := "user://krolik-multi-art-world-state-ci.json"
const AGENT_COUNT := 200
const EXPECTED_FULL := 40
const EXPECTED_REDUCED := 60
const EXPECTED_SLEEP := 100
const FOCUS := Vector2(100.0, 100.0)

var _manifest_paths: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("KROLIK_MULTI_ART_WORLD_FAIL " + message)
    quit(1)

func _load_manifests() -> bool:
    _manifest_paths.clear()
    var raw: String = OS.get_environment("KROLIK_MULTI_ART_MANIFEST_PATHS").strip_edges()
    for value in raw.split(";", false):
        var path := str(value).strip_edges()
        if not path.is_empty():
            _manifest_paths.append(path)
    if _manifest_paths.size() != 4:
        return false
    for path in _manifest_paths:
        var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
        if not FileAccess.file_exists(absolute):
            return false
    return true

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

func _mind(index: int) -> Dictionary:
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
        "needs": {"energy": 0.9, "comfort": 0.8, "curiosity": 0.1, "social": 0.1},
        "memory": [{
            "kind": "mixed-package",
            "subject": "mixed-%03d" % index,
            "valence": 0.1,
            "importance": 0.4,
            "age": float(index % 11) * 0.1,
            "ttl": 300.0,
        }],
    }

func _manifest_absolute(index: int) -> String:
    var path: String = _manifest_paths[index % _manifest_paths.size()]
    return ProjectSettings.globalize_path(path) if path.begins_with("res://") else path

func _spawn(parent: Node, lod: VaultPopulationLOD, index: int) -> VaultCharacterAgent:
    var position := _position_for(index)
    var manifest_abs := _manifest_absolute(index)
    var agent := VaultCharacterAgent.new()
    parent.add_child(agent)
    agent.setup("mixed-%03d" % index, position, {})
    var build_full := index < EXPECTED_FULL
    if not agent.load_runtime_manifest(manifest_abs, build_full):
        agent.free()
        return null
    agent.character_id = "mixed-%03d" % index
    agent.brain.apply_snapshot(_mind(index))
    agent.position = position
    agent.home_position = position
    agent.target_position = position
    agent.velocity = Vector2.ZERO
    var no_targets: Array[Vector2] = []
    agent.world_targets = no_targets
    if not lod.register_agent(agent, manifest_abs):
        agent.free()
        return null
    return agent

func _manifest_distribution(doc: Dictionary) -> Dictionary:
    var counts: Dictionary = {}
    var records: Array = doc.get("characters", [])
    for value in records:
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var record: Dictionary = value
        var path := str(record.get("package_manifest", ""))
        counts[path] = int(counts.get(path, 0)) + 1
    return counts

func _run() -> void:
    if not _load_manifests():
        _fail("expected four valid runtime manifests")
        return
    VaultRuntimePackageCache.reset_cache()
    var package_root_abs := ProjectSettings.globalize_path(PACKAGE_ROOT)

    var world := Node2D.new()
    world.name = "MultiArtWorldBeforeSave"
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
        "reassess_interval": 0.10,
        "proxy_max_height": 128,
    })

    var agents: Array[VaultCharacterAgent] = []
    var spawn_start := Time.get_ticks_usec()
    for index in range(AGENT_COUNT):
        var agent := _spawn(world, lod, index)
        if agent == null:
            _fail("spawn failed at index %d" % index)
            return
        agents.append(agent)
    lod.force_reassess()
    var spawn_ms := float(Time.get_ticks_usec() - spawn_start) / 1000.0
    if lod.full_count() != EXPECTED_FULL or lod.reduced_count() != EXPECTED_REDUCED or lod.sleeping_count() != EXPECTED_SLEEP:
        _fail("initial LOD distribution mismatch: " + str(lod.tier_snapshot()))
        return

    var persistence := VaultWorldState.new()
    var capture_start := Time.get_ticks_usec()
    var doc := persistence.capture("ci-multi-art-world", agents, lod, package_root_abs)
    var capture_ms := float(Time.get_ticks_usec() - capture_start) / 1000.0
    if doc.is_empty() or int(doc.get("characters", []).size()) != AGENT_COUNT:
        _fail("capture failed: " + persistence.last_error)
        return
    var before_distribution := _manifest_distribution(doc)
    if before_distribution.size() != 4:
        _fail("capture collapsed package diversity: " + str(before_distribution))
        return
    for count_value in before_distribution.values():
        if int(count_value) != AGENT_COUNT / 4:
            _fail("capture package distribution is uneven: " + str(before_distribution))
            return

    var save_start := Time.get_ticks_usec()
    if not persistence.save_atomic(SAVE_PATH, doc):
        _fail("save failed: " + persistence.last_error)
        return
    var save_ms := float(Time.get_ticks_usec() - save_start) / 1000.0
    var save_abs := ProjectSettings.globalize_path(SAVE_PATH)
    var save_bytes := FileAccess.get_file_as_string(save_abs).to_utf8_buffer().size()

    lod.clear(false)
    world.free()
    agents.clear()

    var load_start := Time.get_ticks_usec()
    var loaded := persistence.load_file(SAVE_PATH)
    var load_ms := float(Time.get_ticks_usec() - load_start) / 1000.0
    if loaded.is_empty():
        _fail("load failed: " + persistence.last_error)
        return
    var after_distribution := _manifest_distribution(loaded)
    if after_distribution != before_distribution:
        _fail("package references changed on disk round-trip: before=%s after=%s" % [str(before_distribution), str(after_distribution)])
        return

    var restored_world := Node2D.new()
    restored_world.name = "MultiArtWorldAfterReload"
    root.add_child(restored_world)
    var restore_start := Time.get_ticks_usec()
    var restored := persistence.restore(loaded, restored_world, package_root_abs)
    var restore_ms := float(Time.get_ticks_usec() - restore_start) / 1000.0
    if restored.is_empty():
        _fail("restore failed: " + persistence.last_error)
        return
    var restored_agents: Array = restored.get("agents", [])
    var restored_lod := restored.get("lod") as VaultPopulationLOD
    if restored_agents.size() != AGENT_COUNT or restored_lod == null:
        _fail("restored population shape mismatch")
        return
    if restored_lod.full_count() != EXPECTED_FULL or restored_lod.reduced_count() != EXPECTED_REDUCED or restored_lod.sleeping_count() != EXPECTED_SLEEP:
        _fail("restored LOD distribution mismatch: " + str(restored_lod.tier_snapshot()))
        return

    var first := restored_agents[0] as VaultCharacterAgent
    var last := restored_agents[restored_agents.size() - 1] as VaultCharacterAgent
    if first == null or last == null or first.character_id != "mixed-000" or last.character_id != "mixed-199":
        _fail("character identity/order changed during mixed restore")
        return
    if first.skinned_visual == null or first.collision_rig == null:
        _fail("full-tier mixed character did not restore GPU/collision resources")
        return
    if last.character_texture != null or last.skinned_visual != null or last.collision_rig != null:
        _fail("sleep-tier mixed character retained runtime resources")
        return

    var cache := VaultRuntimePackageCache.stats_snapshot()
    if int(cache.get("entries", 0)) != 4 or int(cache.get("manifest_parses", 0)) != 4 or int(cache.get("texture_decodes", 0)) != 4:
        _fail("mixed package cache shape mismatch: " + str(cache))
        return

    print("KROLIK_MULTI_ART_WORLD status=ok agents=%d packages=4 full=%d reduced=%d sleeping=%d spawn_ms=%.2f capture_ms=%.2f save_ms=%.2f load_ms=%.2f restore_ms=%.2f save_bytes=%d cache_parses=%d cache_decodes=%d cache_hits=%d" % [
        AGENT_COUNT, EXPECTED_FULL, EXPECTED_REDUCED, EXPECTED_SLEEP, spawn_ms, capture_ms, save_ms, load_ms, restore_ms, save_bytes, int(cache.get("manifest_parses", 0)), int(cache.get("texture_decodes", 0)), int(cache.get("hits", 0))
    ])

    restored_lod.clear(false)
    restored_world.free()
    if FileAccess.file_exists(save_abs):
        DirAccess.remove_absolute(save_abs)
    quit(0)
