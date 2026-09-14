extends SceneTree

const MANIFEST_PATH := "res://.ci_vertical_slice/exports/runtime/ci_core_slice/manifest.json"

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("KROLIK_CORE_VERTICAL_SLICE_FAIL " + message)
    quit(1)

func _run() -> void:
    var manifest_abs := ProjectSettings.globalize_path(MANIFEST_PATH)
    var manifest_file := FileAccess.open(manifest_abs, FileAccess.READ)
    if manifest_file == null:
        _fail("generated manifest is missing: " + manifest_abs)
        return
    var parsed = JSON.parse_string(manifest_file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("generated manifest is not a dictionary")
        return
    var manifest: Dictionary = parsed
    if str(manifest.get("schema", "")) != "krolik.runtime-character/1":
        _fail("runtime manifest schema mismatch")
        return
    var quality: Dictionary = manifest.get("quality", {})
    if not bool(quality.get("runtime_ready", false)) or float(quality.get("rig_score", 0.0)) < 99.0:
        _fail("generated package is not runtime-ready")
        return

    var agent := VaultCharacterAgent.new()
    root.add_child(agent)
    agent.setup("preload-id", Vector2(80.0, 160.0), {})
    agent.collision_layer = 0
    agent.collision_mask = 0
    agent.set_physics_process(true)

    if not agent.load_runtime_manifest(manifest_abs):
        _fail("production VaultCharacterAgent rejected generated manifest/image")
        agent.queue_free()
        return
    if agent.character_id != "ci_core_slice":
        _fail("character id did not load from manifest: " + agent.character_id)
        agent.queue_free()
        return
    if agent.character_texture == null or agent.character_texture.get_width() != 256 or agent.character_texture.get_height() != 512:
        _fail("packaged character image did not load with expected dimensions")
        agent.queue_free()
        return
    if agent.rig_joints.size() != 15 or agent.rig_bones.size() != 14:
        _fail("rig contract did not survive package load joints=%d bones=%d" % [agent.rig_joints.size(), agent.rig_bones.size()])
        agent.queue_free()
        return
    if agent.skin_recipe.is_empty() or str(agent.skin_recipe.get("backend", "")) != "godot_polygon2d_grid_v1":
        _fail("GPU skin recipe missing after manifest load")
        agent.queue_free()
        return
    var weights = agent.skin_recipe.get("bone_weights", [])
    if typeof(weights) != TYPE_ARRAY or weights.size() != 14:
        _fail("skin weights missing after manifest load")
        agent.queue_free()
        return
    if agent.physics_proxies.size() != 14:
        _fail("collision proxies missing after manifest load: " + str(agent.physics_proxies.size()))
        agent.queue_free()
        return
    if agent.skinned_visual == null or not is_instance_valid(agent.skinned_visual):
        _fail("production character fell back instead of creating GPU skinned visual")
        agent.queue_free()
        return
    if agent.flat_sprite != null:
        _fail("flat fallback was created despite valid rig/skin package")
        agent.queue_free()
        return
    if agent.collision_rig == null:
        _fail("collision rig was not rebuilt from packaged proxies")
        agent.queue_free()
        return
    if not agent.brain.policy_loaded:
        _fail("production brain did not retain generated AI policy")
        agent.queue_free()
        return

    var start := agent.global_position
    agent.home_position = start
    agent.target_position = start
    agent.world_targets.clear()
    agent.world_targets.append(start + Vector2(180.0, 0.0))

    for _frame in range(36):
        await physics_frame

    var travel := agent.global_position.distance_to(start)
    if agent.phase < 0.20:
        _fail("production physics callback did not execute")
        agent.queue_free()
        return
    if agent.brain.state not in ["wander", "inspect", "social", "return_home"]:
        _fail("package mind did not enter a mobile state: " + agent.brain.state)
        agent.queue_free()
        return
    if travel < 4.0:
        _fail("production package loaded but did not move: travel=" + str(travel))
        agent.queue_free()
        return
    if agent.animated_joints.size() != 15 or agent.solved_joints.size() != 15:
        _fail("animation/IK pose pipeline did not preserve complete joint set")
        agent.queue_free()
        return

    print(
        "KROLIK_CORE_VERTICAL_SLICE_GODOT character=", agent.character_id,
        " joints=", agent.rig_joints.size(),
        " bones=", agent.rig_bones.size(),
        " weights=", weights.size(),
        " collisions=", agent.physics_proxies.size(),
        " gpu_skin=true policy=", agent.brain.policy_loaded,
        " state=", agent.brain.state,
        " phase=", snappedf(agent.phase, 0.001),
        " travel=", snappedf(travel, 0.01)
    )
    agent.queue_free()
    await process_frame
    quit(0)
