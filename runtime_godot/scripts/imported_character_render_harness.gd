extends SceneTree

## Rendered regression for the actual ordinary-image import -> runtime package ->
## VaultCharacterAgent -> VaultSkinnedCharacter path.
##
## Unlike deformation_harness.gd this does not construct a procedural texture or
## a tiny synthetic skin recipe. The Python CI builder first imports an ordinary
## image through character_import.py, creates the full runtime package, and this
## harness loads that exact package through the production character agent. It
## captures the imported character at rest, applies a deliberately visible pose
## through the production GPU skin, captures again, and requires a material
## rendered pixel difference. PNGs are retained as CI evidence.

const MANIFEST_PATH := "res://.ci_vertical_slice/exports/runtime/ci_core_slice/manifest.json"
const VIEWPORT_SIZE := Vector2i(960, 720)
const CLEAR := Color(0.008, 0.008, 0.012, 1.0)

var _artifact_dir := ""

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String, code: int = 1) -> void:
    push_error("KROLIK_IMPORTED_RENDER_FAIL " + message)
    quit(code)

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
    _artifact_dir = ProjectSettings.globalize_path("res://imported_character_artifacts")
    DirAccess.make_dir_recursive_absolute(_artifact_dir)

    var manifest_abs := ProjectSettings.globalize_path(MANIFEST_PATH)
    if not FileAccess.file_exists(manifest_abs):
        _fail("ordinary-image runtime package manifest is missing: " + manifest_abs, 11)
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
        _fail("VaultCharacterAgent rejected the generated ordinary-image package", 12)
        return
    if agent.skinned_visual == null or not is_instance_valid(agent.skinned_visual):
        _fail("ordinary-image package did not create production GPU skin", 13)
        return
    if not agent.skinned_visual.runtime_ready:
        _fail("production GPU skin reports runtime_ready=false", 14)
        return
    if agent.flat_sprite != null:
        _fail("ordinary-image package unexpectedly used flat fallback", 15)
        return
    if agent.rig_joints.size() != 15 or agent.rig_bones.size() != 14:
        _fail("ordinary-image rig contract mismatch", 16)
        return

    agent.skinned_visual.apply_joint_pose(agent.rig_joints)
    await _wait_render_frames(6)
    var baseline := _capture()
    var baseline_pixels := _count_foreground(baseline)
    if baseline_pixels < 8000:
        _fail("imported character render is blank/too small foreground=%d" % baseline_pixels, 17)
        return

    var pose: Dictionary = agent.rig_joints.duplicate(true)
    var head: Vector2 = pose.get("head", Vector2(0.5, 0.1))
    var left_wrist: Vector2 = pose.get("left_wrist", Vector2(0.3, 0.5))
    var right_wrist: Vector2 = pose.get("right_wrist", Vector2(0.7, 0.5))
    # Strong but bounded pose so the pixel regression is stable across the
    # current heuristic rig and future validated auto-rig backends.
    pose["head"] = Vector2(clampf(head.x + 0.09, 0.15, 0.85), clampf(head.y + 0.025, 0.03, 0.30))
    pose["left_wrist"] = Vector2(clampf(left_wrist.x - 0.14, 0.02, 0.48), clampf(left_wrist.y - 0.08, 0.20, 0.78))
    pose["right_wrist"] = Vector2(clampf(right_wrist.x + 0.14, 0.52, 0.98), clampf(right_wrist.y - 0.08, 0.20, 0.78))
    agent.skinned_visual.apply_joint_pose(pose)

    await _wait_render_frames(6)
    var posed := _capture()
    var changed_pixels := _count_changed(baseline, posed)
    var min_changed := 1800

    var baseline_saved := _save("imported_baseline.png", baseline)
    var posed_saved := _save("imported_posed.png", posed)
    if not baseline_saved or not posed_saved:
        _fail("unable to save imported-character PNG evidence", 18)
        return
    if changed_pixels < min_changed:
        _fail("insufficient imported-character rendered deformation %d < %d" % [changed_pixels, min_changed], 19)
        return

    var stats: Dictionary = agent.skinned_visual.stats()
    print("KROLIK_IMPORTED_RENDER character=%s texture=%dx%d vertices=%d skin_bones=%d rig_joints=%d rig_bones=%d foreground=%d changed_pixels=%d min_changed=%d gpu_skin=true evidence=true renderer=%s" % [
        agent.character_id,
        agent.character_texture.get_width(), agent.character_texture.get_height(),
        int(stats.get("vertices", 0)), int(stats.get("bones", 0)),
        agent.rig_joints.size(), agent.rig_bones.size(),
        baseline_pixels, changed_pixels, min_changed,
        RenderingServer.get_current_rendering_method(),
    ])

    agent.queue_free()
    await _wait_render_frames(2)
    quit(0)
