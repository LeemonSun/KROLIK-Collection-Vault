extends SceneTree

## Rendered regression for the actual import -> runtime package ->
## VaultCharacterAgent -> VaultSkinnedCharacter path.
##
## The harness is intentionally parameterized through environment variables so
## deterministic heuristic packages, DWPose packages and future reviewed-art
## packages exercise the same production runtime/render path instead of growing
## separate test-only renderers.

const DEFAULT_MANIFEST_PATH := "res://.ci_vertical_slice/exports/runtime/ci_core_slice/manifest.json"
const VIEWPORT_SIZE := Vector2i(960, 720)
const CLEAR := Color(0.008, 0.008, 0.012, 1.0)

var _artifact_dir := ""

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String, code: int = 1) -> void:
    push_error("KROLIK_IMPORTED_RENDER_FAIL " + message)
    quit(code)

func _env_or(name: String, fallback: String) -> String:
    var value := OS.get_environment(name)
    return fallback if value.is_empty() else value

func _wait_render_frames(count: int = 4) -> void:
    for _i in range(count):
        await process_frame

func _capture() -> Image:
    return root.get_texture().get_image()

func _pixel_distance_from_clear(color: Color) -> float:
    return absf(color.r - CLEAR.r) + absf(color.g - CLEAR.g) + absf(color.b - CLEAR.b)

func _count_foreground(image: Image) -> int:
    var count := 0
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            if _pixel_distance_from_clear(image.get_pixel(x, y)) >= 0.09:
                count += 1
    return count

func _count_changed(a: Image, b: Image, threshold: float = 0.10) -> int:
    if a.get_size() != b.get_size():
        return -1
    var changed := 0
    for y in range(a.get_height()):
        for x in range(a.get_width()):
            var ca := a.get_pixel(x, y)
            var cb := b.get_pixel(x, y)
            var delta := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
            if delta >= threshold:
                changed += 1
    return changed

func _save(name: String, image: Image) -> bool:
    return image.save_png(_artifact_dir.path_join(name)) == OK

func _run() -> void:
    root.size = VIEWPORT_SIZE
    RenderingServer.set_default_clear_color(CLEAR)

    var manifest_path := _env_or("KROLIK_RENDER_MANIFEST_PATH", DEFAULT_MANIFEST_PATH)
    var expected_character_id := _env_or("KROLIK_RENDER_CHARACTER_ID", "ci_core_slice")
    var expected_rig_backend := OS.get_environment("KROLIK_RENDER_RIG_BACKEND")
    var artifact_res_dir := _env_or("KROLIK_RENDER_ARTIFACT_DIR", "res://imported_character_artifacts")
    var min_foreground := int(_env_or("KROLIK_RENDER_MIN_FOREGROUND", "8000"))
    var min_changed := int(_env_or("KROLIK_RENDER_MIN_CHANGED", "1800"))

    _artifact_dir = ProjectSettings.globalize_path(artifact_res_dir)
    DirAccess.make_dir_recursive_absolute(_artifact_dir)

    var manifest_abs := ProjectSettings.globalize_path(manifest_path)
    if not FileAccess.file_exists(manifest_abs):
        _fail("runtime package manifest is missing: " + manifest_abs, 11)
        return
    var manifest_file := FileAccess.open(manifest_abs, FileAccess.READ)
    if manifest_file == null:
        _fail("runtime package manifest cannot be opened: " + manifest_abs, 11)
        return
    var parsed = JSON.parse_string(manifest_file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("runtime package manifest is not a dictionary", 11)
        return
    var manifest: Dictionary = parsed
    var rig_doc: Dictionary = manifest.get("rig", {})
    if not expected_rig_backend.is_empty() and str(rig_doc.get("backend", "")) != expected_rig_backend:
        _fail("rig backend mismatch expected=%s actual=%s" % [expected_rig_backend, str(rig_doc.get("backend", ""))], 11)
        return

    var world := Node2D.new()
    world.name = "ImportedCharacterRenderWorld"
    root.add_child(world)

    var agent := VaultCharacterAgent.new()
    agent.name = "ImportedCharacterEvidence"
    world.add_child(agent)
    agent.setup("preload-id", Vector2(480.0, 650.0), {})
    agent.collision_layer = 0
    agent.collision_mask = 0
    agent.set_physics_process(false)

    if not agent.load_runtime_manifest(manifest_abs):
        _fail("VaultCharacterAgent rejected the generated package", 12)
        return
    if agent.character_id != expected_character_id:
        _fail("character id mismatch expected=%s actual=%s" % [expected_character_id, agent.character_id], 12)
        return
    if agent.skinned_visual == null or not is_instance_valid(agent.skinned_visual):
        _fail("package did not create production GPU skin", 13)
        return
    if not agent.skinned_visual.runtime_ready:
        _fail("production GPU skin reports runtime_ready=false", 14)
        return
    if agent.flat_sprite != null:
        _fail("package unexpectedly used flat fallback", 15)
        return
    if agent.rig_joints.size() != 15 or agent.rig_bones.size() != 14:
        _fail("rig contract mismatch", 16)
        return

    agent.skinned_visual.apply_joint_pose(agent.rig_joints)
    await _wait_render_frames(6)
    var baseline := _capture()
    var baseline_pixels := _count_foreground(baseline)
    if baseline_pixels < min_foreground:
        _fail("imported character render is blank/too small foreground=%d min=%d" % [baseline_pixels, min_foreground], 17)
        return

    var pose: Dictionary = agent.rig_joints.duplicate(true)
    var head: Vector2 = pose.get("head", Vector2(0.5, 0.1))
    var left_wrist: Vector2 = pose.get("left_wrist", Vector2(0.3, 0.5))
    var right_wrist: Vector2 = pose.get("right_wrist", Vector2(0.7, 0.5))
    pose["head"] = Vector2(clampf(head.x + 0.09, 0.15, 0.85), clampf(head.y + 0.025, 0.03, 0.30))
    pose["left_wrist"] = Vector2(clampf(left_wrist.x - 0.14, 0.02, 0.48), clampf(left_wrist.y - 0.08, 0.20, 0.78))
    pose["right_wrist"] = Vector2(clampf(right_wrist.x + 0.14, 0.52, 0.98), clampf(right_wrist.y - 0.08, 0.20, 0.78))
    agent.skinned_visual.apply_joint_pose(pose)

    await _wait_render_frames(6)
    var posed := _capture()
    var changed_pixels := _count_changed(baseline, posed)

    var baseline_saved := _save("imported_baseline.png", baseline)
    var posed_saved := _save("imported_posed.png", posed)
    if not baseline_saved or not posed_saved:
        _fail("unable to save imported-character PNG evidence", 18)
        return
    if changed_pixels < min_changed:
        _fail("insufficient imported-character rendered deformation %d < %d" % [changed_pixels, min_changed], 19)
        return

    var stats: Dictionary = agent.skinned_visual.stats()
    print("KROLIK_IMPORTED_RENDER character=%s rig_backend=%s texture=%dx%d vertices=%d skin_bones=%d rig_joints=%d rig_bones=%d foreground=%d changed_pixels=%d min_changed=%d gpu_skin=true evidence=true renderer=%s" % [
        agent.character_id, str(rig_doc.get("backend", "")),
        agent.character_texture.get_width(), agent.character_texture.get_height(),
        int(stats.get("vertices", 0)), int(stats.get("bones", 0)),
        agent.rig_joints.size(), agent.rig_bones.size(),
        baseline_pixels, changed_pixels, min_changed,
        RenderingServer.get_current_rendering_method(),
    ])

    agent.queue_free()
    await _wait_render_frames(2)
    quit(0)
