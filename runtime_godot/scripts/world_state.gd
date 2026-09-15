class_name VaultWorldState
extends RefCounted

## Versioned, source-independent persistence for the runtime world.
##
## The save never trusts arbitrary filesystem paths. Character packages are
## referenced by a relative manifest path beneath a caller-supplied package root,
## and the manifest SHA-256 is pinned in the save. Runtime resources themselves
## remain derived/sealed package data and are never copied into the world file.

const SCHEMA := "krolik.world-state/1"
const FORMAT_VERSION := 1
const MAX_CHARACTERS := 2000
const MAX_WORLD_ID := 128
const MAX_RELATIVE_PATH := 512

var last_error := ""

func _fail(message: String) -> bool:
    last_error = message
    return false

func _vec(value: Vector2) -> Dictionary:
    return {"x": value.x, "y": value.y}

func _read_vec(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
    if typeof(value) != TYPE_DICTIONARY:
        return fallback
    return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))

func _finite_vec(value: Variant) -> bool:
    if typeof(value) != TYPE_DICTIONARY:
        return false
    var x := float(value.get("x", NAN))
    var y := float(value.get("y", NAN))
    return is_finite(x) and is_finite(y)

func _normalized_root(path: String) -> String:
    var value := path.strip_edges().replace("\\", "/").simplify_path()
    while value.length() > 1 and value.ends_with("/"):
        value = value.left(value.length() - 1)
    return value

func _valid_relative_path(path: String) -> bool:
    if path.is_empty() or path.length() > MAX_RELATIVE_PATH:
        return false
    var value := path.replace("\\", "/")
    if value.begins_with("/") or value.contains(":") or value.contains("://"):
        return false
    for raw_segment in value.split("/", false):
        var segment := str(raw_segment)
        if segment.is_empty() or segment == "." or segment == "..":
            return false
    return value.get_file() == "manifest.json"

func _manifest_relative(manifest_path: String, package_root: String) -> String:
    var root := _normalized_root(package_root)
    var manifest := manifest_path.strip_edges().replace("\\", "/").simplify_path()
    if root.is_empty() or manifest.is_empty():
        return ""
    var prefix := root + "/"
    if not manifest.begins_with(prefix):
        return ""
    var relative := manifest.substr(prefix.length())
    return relative if _valid_relative_path(relative) else ""

func _resolve_manifest(relative_path: String, package_root: String) -> String:
    if not _valid_relative_path(relative_path):
        return ""
    var root := _normalized_root(package_root)
    if root.is_empty():
        return ""
    var candidate := root.path_join(relative_path.replace("\\", "/")).simplify_path()
    var prefix := root + "/"
    if not candidate.begins_with(prefix):
        return ""
    return candidate

func _manifest_hash(path: String) -> String:
    if path.is_empty() or not FileAccess.file_exists(path):
        return ""
    return FileAccess.get_sha256(path).to_lower()

func _semantic_context(agent: VaultCharacterAgent) -> Dictionary:
    return {
        "bound": agent.contained,
        "interaction_mode": "contained" if agent.contained else "",
        "away_from_home": agent.global_position.distance_to(agent.home_position) > 36.0,
        "interesting_targets": float(agent.world_targets.size()),
        "social_targets": 0.0,
    }

func capture(
    world_id: String,
    agents: Array,
    lod: VaultPopulationLOD,
    package_root: String
) -> Dictionary:
    last_error = ""
    var clean_world_id := world_id.strip_edges()
    if clean_world_id.is_empty() or clean_world_id.length() > MAX_WORLD_ID:
        _fail("invalid world_id")
        return {}
    if agents.size() > MAX_CHARACTERS:
        _fail("character count exceeds world-state limit")
        return {}
    if lod == null or not is_instance_valid(lod):
        _fail("population LOD manager is required")
        return {}

    var records: Array = []
    var seen_ids: Dictionary = {}
    for value in agents:
        var agent := value as VaultCharacterAgent
        if agent == null or not is_instance_valid(agent):
            continue
        var character_id := agent.character_id.strip_edges()
        if character_id.is_empty() or character_id.length() > 128:
            _fail("invalid character id")
            return {}
        if seen_ids.has(character_id):
            _fail("duplicate character id: " + character_id)
            return {}
        seen_ids[character_id] = true

        var lod_entry := lod.entry_snapshot(agent)
        if lod_entry.is_empty():
            _fail("character is not registered with population LOD: " + character_id)
            return {}
        var manifest_path := str(lod_entry.get("manifest_path", ""))
        var relative_manifest := _manifest_relative(manifest_path, package_root)
        if relative_manifest.is_empty():
            _fail("character manifest is outside package root: " + character_id)
            return {}
        var manifest_hash := _manifest_hash(manifest_path)
        if manifest_hash.length() != 64:
            _fail("unable to hash character manifest: " + character_id)
            return {}

        var target_values: Array = []
        for target in agent.world_targets:
            target_values.append(_vec(target))

        records.append({
            "character_id": character_id,
            "package_manifest": relative_manifest,
            "manifest_sha256": manifest_hash,
            "position": _vec(agent.position),
            "home_position": _vec(agent.home_position),
            "target_position": _vec(agent.target_position),
            "world_targets": target_values,
            "facing": agent.facing,
            "phase": agent.phase,
            "velocity": _vec(agent.velocity),
            "contained": agent.contained,
            "brain": agent.brain.snapshot(),
            "lod": {
                "tier": str(lod_entry.get("tier", VaultPopulationLOD.TIER_FULL)),
                "sleep_source_tier": str(lod_entry.get("sleep_source_tier", VaultPopulationLOD.TIER_FULL)),
                "sleep_elapsed": float(lod_entry.get("sleep_elapsed", 0.0)),
            },
        })

    records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a.get("character_id", "")) < str(b.get("character_id", ""))
    )

    var doc := {
        "schema": SCHEMA,
        "format_version": FORMAT_VERSION,
        "world_id": clean_world_id,
        "lod": {
            "enabled": lod.enabled,
            "resource_residency": lod.resource_residency_enabled,
            "focus_position": _vec(lod.focus_position),
            "full_radius": lod.full_radius,
            "sleep_radius": lod.sleep_radius,
            "wake_radius": lod.wake_radius,
            "reassess_interval": lod.reassess_interval,
            "proxy_max_height": lod.proxy_max_height,
        },
        "characters": records,
    }
    if not validate(doc):
        return {}
    return doc

func validate(doc: Variant) -> bool:
    last_error = ""
    if typeof(doc) != TYPE_DICTIONARY:
        return _fail("world state must be an object")
    if str(doc.get("schema", "")) != SCHEMA:
        return _fail("unsupported world-state schema")
    if int(doc.get("format_version", -1)) != FORMAT_VERSION:
        return _fail("unsupported world-state format version")
    var world_id := str(doc.get("world_id", "")).strip_edges()
    if world_id.is_empty() or world_id.length() > MAX_WORLD_ID:
        return _fail("invalid world_id")

    var lod_doc = doc.get("lod", null)
    if typeof(lod_doc) != TYPE_DICTIONARY:
        return _fail("lod settings must be an object")
    if not _finite_vec(lod_doc.get("focus_position", null)):
        return _fail("invalid LOD focus position")
    var full_radius := float(lod_doc.get("full_radius", NAN))
    var sleep_radius := float(lod_doc.get("sleep_radius", NAN))
    var wake_radius := float(lod_doc.get("wake_radius", NAN))
    var reassess := float(lod_doc.get("reassess_interval", NAN))
    var proxy_height := int(lod_doc.get("proxy_max_height", 0))
    if not is_finite(full_radius) or not is_finite(sleep_radius) or not is_finite(wake_radius) or not is_finite(reassess):
        return _fail("LOD settings contain non-finite values")
    if full_radius < 0.0 or sleep_radius < 1.0 or full_radius > sleep_radius:
        return _fail("invalid LOD radii")
    if wake_radius < full_radius or wake_radius > sleep_radius:
        return _fail("invalid LOD wake radius")
    if reassess < 0.05 or reassess > 5.0 or proxy_height < 48 or proxy_height > 512:
        return _fail("invalid LOD cadence/proxy size")

    var characters = doc.get("characters", null)
    if typeof(characters) != TYPE_ARRAY:
        return _fail("characters must be an array")
    if characters.size() > MAX_CHARACTERS:
        return _fail("character count exceeds world-state limit")

    var seen_ids: Dictionary = {}
    for index in range(characters.size()):
        var record = characters[index]
        if typeof(record) != TYPE_DICTIONARY:
            return _fail("character record %d must be an object" % index)
        var character_id := str(record.get("character_id", "")).strip_edges()
        if character_id.is_empty() or character_id.length() > 128:
            return _fail("invalid character id at index %d" % index)
        if seen_ids.has(character_id):
            return _fail("duplicate character id: " + character_id)
        seen_ids[character_id] = true
        if not _valid_relative_path(str(record.get("package_manifest", ""))):
            return _fail("unsafe package manifest path for " + character_id)
        var digest := str(record.get("manifest_sha256", "")).to_lower()
        if digest.length() != 64 or not digest.is_valid_hex_number():
            return _fail("invalid manifest SHA-256 for " + character_id)
        for key in ["position", "home_position", "target_position", "velocity"]:
            if not _finite_vec(record.get(key, null)):
                return _fail("invalid %s for %s" % [key, character_id])
        var targets = record.get("world_targets", null)
        if typeof(targets) != TYPE_ARRAY or targets.size() > 256:
            return _fail("invalid world_targets for " + character_id)
        for target in targets:
            if not _finite_vec(target):
                return _fail("invalid world target for " + character_id)
        var facing := float(record.get("facing", NAN))
        var phase := float(record.get("phase", NAN))
        if not is_finite(facing) or absf(facing) < 0.001 or not is_finite(phase) or phase < 0.0:
            return _fail("invalid facing/phase for " + character_id)
        if typeof(record.get("brain", null)) != TYPE_DICTIONARY:
            return _fail("brain snapshot missing for " + character_id)
        var lod_entry = record.get("lod", null)
        if typeof(lod_entry) != TYPE_DICTIONARY:
            return _fail("lod state missing for " + character_id)
        var tier := str(lod_entry.get("tier", ""))
        var source_tier := str(lod_entry.get("sleep_source_tier", ""))
        if tier not in [VaultPopulationLOD.TIER_FULL, VaultPopulationLOD.TIER_REDUCED, VaultPopulationLOD.TIER_SLEEP]:
            return _fail("invalid LOD tier for " + character_id)
        if source_tier not in [VaultPopulationLOD.TIER_FULL, VaultPopulationLOD.TIER_REDUCED]:
            return _fail("invalid sleep source tier for " + character_id)
        var sleep_elapsed := float(lod_entry.get("sleep_elapsed", NAN))
        if not is_finite(sleep_elapsed) or sleep_elapsed < 0.0 or sleep_elapsed > 300.0:
            return _fail("invalid pending sleep time for " + character_id)
    return true

func save_atomic(path: String, doc: Dictionary) -> bool:
    if not validate(doc):
        return false
    var global_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
    if global_path.is_empty():
        return _fail("save path is empty")
    var directory := global_path.get_base_dir()
    var mkdir_err := DirAccess.make_dir_recursive_absolute(directory)
    if mkdir_err != OK and mkdir_err != ERR_ALREADY_EXISTS:
        return _fail("unable to create world-state directory")

    var temp_path := global_path + ".tmp-%d" % Time.get_ticks_usec()
    var backup_path := global_path + ".bak"
    var file := FileAccess.open(temp_path, FileAccess.WRITE)
    if file == null:
        return _fail("unable to open temporary world-state file")
    file.store_string(JSON.stringify(doc, "  ", false))
    file.flush()
    file.close()

    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(temp_path))
    if not validate(parsed):
        DirAccess.remove_absolute(temp_path)
        return _fail("temporary world-state file failed read-back validation")

    if FileAccess.file_exists(backup_path):
        DirAccess.remove_absolute(backup_path)
    if FileAccess.file_exists(global_path):
        var backup_err := DirAccess.rename_absolute(global_path, backup_path)
        if backup_err != OK:
            DirAccess.remove_absolute(temp_path)
            return _fail("unable to preserve previous world-state file")
    var promote_err := DirAccess.rename_absolute(temp_path, global_path)
    if promote_err != OK:
        if FileAccess.file_exists(backup_path):
            DirAccess.rename_absolute(backup_path, global_path)
        DirAccess.remove_absolute(temp_path)
        return _fail("unable to promote validated world-state file")
    if FileAccess.file_exists(backup_path):
        DirAccess.remove_absolute(backup_path)
    last_error = ""
    return true

func load_file(path: String) -> Dictionary:
    last_error = ""
    var global_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
    if global_path.is_empty() or not FileAccess.file_exists(global_path):
        _fail("world-state file does not exist")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(global_path))
    if not validate(parsed):
        return {}
    return parsed

func _restore_failed(parent: Node, lod: VaultPopulationLOD, agents: Array, message: String) -> Dictionary:
    last_error = message
    if lod != null and is_instance_valid(lod):
        lod.clear(false)
        lod.queue_free()
    for value in agents:
        var agent := value as VaultCharacterAgent
        if agent != null and is_instance_valid(agent):
            agent.queue_free()
    return {}

func restore(doc: Dictionary, parent: Node, package_root: String) -> Dictionary:
    last_error = ""
    if parent == null or not is_instance_valid(parent):
        _fail("restore parent is invalid")
        return {}
    if not validate(doc):
        return {}

    # Resolve and hash every package before mutating the scene tree. A tampered
    # world file therefore cannot leave a partially restored population behind.
    var resolved: Array = []
    for record_value in doc.get("characters", []):
        var record: Dictionary = record_value
        var manifest := _resolve_manifest(str(record.get("package_manifest", "")), package_root)
        if manifest.is_empty() or not FileAccess.file_exists(manifest):
            _fail("saved package manifest is missing or outside package root")
            return {}
        var expected_hash := str(record.get("manifest_sha256", "")).to_lower()
        if _manifest_hash(manifest) != expected_hash:
            _fail("saved package manifest hash mismatch for " + str(record.get("character_id", "")))
            return {}
        resolved.append({"record": record, "manifest": manifest})

    var lod_doc: Dictionary = doc.get("lod", {})
    var lod := VaultPopulationLOD.new()
    parent.add_child(lod)
    lod.configure({
        "enabled": bool(lod_doc.get("enabled", true)),
        "resource_residency": bool(lod_doc.get("resource_residency", true)),
        "focus_position": _read_vec(lod_doc.get("focus_position", {})),
        "full_radius": float(lod_doc.get("full_radius", 320.0)),
        "sleep_radius": float(lod_doc.get("sleep_radius", 720.0)),
        "wake_radius": float(lod_doc.get("wake_radius", 640.0)),
        "reassess_interval": float(lod_doc.get("reassess_interval", 0.25)),
        "proxy_max_height": int(lod_doc.get("proxy_max_height", 160)),
        "runtime_manifest_path": "",
    })

    var agents: Array[VaultCharacterAgent] = []
    for item_value in resolved:
        var item: Dictionary = item_value
        var record: Dictionary = item.get("record", {})
        var manifest := str(item.get("manifest", ""))
        var position := _read_vec(record.get("position", {}))
        var saved_lod: Dictionary = record.get("lod", {})
        var expected_tier := str(saved_lod.get("tier", VaultPopulationLOD.TIER_FULL))
        var agent := VaultCharacterAgent.new()
        parent.add_child(agent)
        agent.setup(str(record.get("character_id", "")), position, {})
        if not agent.load_runtime_manifest(manifest, expected_tier == VaultPopulationLOD.TIER_FULL):
            return _restore_failed(parent, lod, agents, "runtime package rejected during world restore")

        agent.character_id = str(record.get("character_id", ""))
        agent.brain.apply_snapshot(record.get("brain", {}))
        agent.position = position
        agent.home_position = _read_vec(record.get("home_position", {}), position)
        agent.target_position = _read_vec(record.get("target_position", {}), position)
        var targets: Array[Vector2] = []
        for target_value in record.get("world_targets", []):
            targets.append(_read_vec(target_value))
        agent.world_targets = targets
        agent.facing = signf(float(record.get("facing", 1.0)))
        agent.phase = float(record.get("phase", 0.0))
        agent.velocity = _read_vec(record.get("velocity", {}))
        agent.contained = bool(record.get("contained", false))

        # Sleeping agents hold semantic time outside VaultAgentBrain. Materialize
        # that saved interval exactly once before they re-enter the new LOD manager.
        var pending_sleep := clampf(float(saved_lod.get("sleep_elapsed", 0.0)), 0.0, 300.0)
        if pending_sleep > 0.0:
            agent.brain.state = agent.brain.step(pending_sleep, _semantic_context(agent))
            agent.phase += pending_sleep

        if not lod.register_agent(agent, manifest):
            agents.append(agent)
            return _restore_failed(parent, lod, agents, "failed to register restored agent with population LOD")
        agents.append(agent)

        var restored_tier := lod.tier_for(agent)
        if restored_tier != expected_tier:
            return _restore_failed(
                parent, lod, agents,
                "saved LOD tier no longer matches restored distance policy for %s: expected=%s actual=%s" % [agent.character_id, expected_tier, restored_tier]
            )

    last_error = ""
    return {"world_id": str(doc.get("world_id", "")), "lod": lod, "agents": agents}