extends SceneTree

const MATRIX_PATH := "res://.ci_import_matrix/matrix.json"

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("KROLIK_IMPORT_MATRIX_FAIL " + message)
    quit(1)

func _run() -> void:
    var matrix_abs := ProjectSettings.globalize_path(MATRIX_PATH)
    var matrix_file := FileAccess.open(matrix_abs, FileAccess.READ)
    if matrix_file == null:
        _fail("matrix document missing: " + matrix_abs)
        return
    var parsed = JSON.parse_string(matrix_file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("matrix is not a dictionary")
        return
    var matrix: Dictionary = parsed
    if str(matrix.get("schema", "")) != "krolik.import-qa-matrix/1":
        _fail("matrix schema mismatch")
        return
    var entries = matrix.get("entries", [])
    if typeof(entries) != TYPE_ARRAY or entries.size() < 4:
        _fail("matrix does not contain enough diverse fixtures")
        return

    var passed := 0
    var corrected := 0
    var total_travel := 0.0
    var methods: Dictionary = {}
    for raw_entry in entries:
        if typeof(raw_entry) != TYPE_DICTIONARY:
            _fail("matrix entry is not a dictionary")
            return
        var entry: Dictionary = raw_entry
        var character_id := str(entry.get("character_id", ""))
        var manifest_rel := str(entry.get("manifest", ""))
        var manifest_abs := matrix_abs.get_base_dir().path_join(manifest_rel)
        if not FileAccess.file_exists(manifest_abs):
            _fail(character_id + ": manifest missing: " + manifest_abs)
            return

        var agent := VaultCharacterAgent.new()
        root.add_child(agent)
        agent.setup("matrix-preload", Vector2(96.0, 180.0), {})
        agent.collision_layer = 0
        agent.collision_mask = 0
        agent.set_physics_process(true)
        if not agent.load_runtime_manifest(manifest_abs):
            _fail(character_id + ": production agent rejected package")
            agent.queue_free()
            return
        if agent.character_id != character_id:
            _fail(character_id + ": manifest character id mismatch")
            agent.queue_free()
            return
        if agent.character_texture == null:
            _fail(character_id + ": texture missing")
            agent.queue_free()
            return
        if agent.character_texture.get_width() != int(entry.get("width", 0)) or agent.character_texture.get_height() != int(entry.get("height", 0)):
            _fail(character_id + ": texture dimensions mismatch")
            agent.queue_free()
            return
        if agent.rig_joints.size() != 15 or agent.rig_bones.size() != 14:
            _fail(character_id + ": rig contract mismatch")
            agent.queue_free()
            return
        if agent.skin_recipe.is_empty() or str(agent.skin_recipe.get("backend", "")) != "godot_polygon2d_grid_v1":
            _fail(character_id + ": GPU skin recipe missing")
            agent.queue_free()
            return
        var weights = agent.skin_recipe.get("bone_weights", [])
        if typeof(weights) != TYPE_ARRAY or weights.size() != 14:
            _fail(character_id + ": bone weights mismatch")
            agent.queue_free()
            return
        if agent.physics_proxies.size() != 14 or agent.collision_rig == null:
            _fail(character_id + ": collision runtime mismatch")
            agent.queue_free()
            return
        if agent.skinned_visual == null or not is_instance_valid(agent.skinned_visual) or agent.flat_sprite != null:
            _fail(character_id + ": package did not use GPU deformable visual")
            agent.queue_free()
            return
        if not agent.brain.policy_loaded:
            _fail(character_id + ": AI policy missing")
            agent.queue_free()
            return

        var expected_joint = entry.get("expected_joint", null)
        if typeof(expected_joint) == TYPE_DICTIONARY:
            var expected: Dictionary = expected_joint
            var joint_name := str(expected.get("name", ""))
            if not agent.rig_joints.has(joint_name):
                _fail(character_id + ": corrected joint missing in runtime")
                agent.queue_free()
                return
            var expected_point := Vector2(float(expected.get("x", 0.0)), float(expected.get("y", 0.0)))
            var actual_point: Vector2 = agent.rig_joints[joint_name]
            if actual_point.distance_to(expected_point) > 0.00001:
                _fail(character_id + ": corrected joint changed during runtime load")
                agent.queue_free()
                return
            corrected += 1

        var start := agent.global_position
        agent.home_position = start
        agent.target_position = start
        agent.world_targets.clear()
        agent.world_targets.append(start + Vector2(150.0, 0.0))
        for _frame in range(18):
            await physics_frame
        var travel := agent.global_position.distance_to(start)
        if agent.phase < 0.10:
            _fail(character_id + ": physics callback did not run")
            agent.queue_free()
            return
        if travel < 1.0:
            _fail(character_id + ": loaded package did not move: " + str(travel))
            agent.queue_free()
            return
        if agent.animated_joints.size() != 15 or agent.solved_joints.size() != 15:
            _fail(character_id + ": animated/solved joint contract mismatch")
            agent.queue_free()
            return

        methods[str(entry.get("cutout_method", "unknown"))] = true
        total_travel += travel
        passed += 1
        agent.queue_free()
        await process_frame

    if not methods.has("embedded-alpha") or not methods.has("uniform-border-v1"):
        _fail("matrix did not exercise both embedded-alpha and automatic cutout paths")
        return
    if corrected < 1:
        _fail("matrix did not exercise a manually corrected rig")
        return

    print(
        "KROLIK_IMPORT_MATRIX_GODOT cases=", entries.size(),
        " passed=", passed,
        " corrected=", corrected,
        " methods=", methods.keys(),
        " total_travel=", snappedf(total_travel, 0.01),
        " gpu_skin_all=true collisions_all=true policy_all=true"
    )
    quit(0)
