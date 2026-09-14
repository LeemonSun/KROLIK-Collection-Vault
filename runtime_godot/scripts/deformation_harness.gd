extends SceneTree

## Rendered A1 regression for the actual VaultSkinnedCharacter GPU path.
##
## This is intentionally not a string/node-existence test.  Each case creates a
## procedural character texture, real Skeleton2D/Bone2D/Polygon2D skinning and
## per-vertex bone weights, captures a rendered baseline frame, changes a joint
## pose, captures the posed frame, and requires a material pixel difference.
## PNG evidence is written for CI artifact upload.

const SkinnedCharacterScript = preload("res://scripts/skinned_character.gd")
const VIEWPORT_SIZE := Vector2i(640, 480)
const CASES := [
    {"name": "tall", "size": Vector2i(128, 256), "head_x": 0.76},
    {"name": "compact", "size": Vector2i(192, 192), "head_x": 0.24},
]

var _world: Node2D
var _artifact_dir := ""

func _initialize() -> void:
    call_deferred("_run")

func _make_texture(size: Vector2i, seed: int) -> Texture2D:
    var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
    for y in range(size.y):
        for x in range(size.x):
            var checker := ((x / 16) + (y / 20) + seed) % 2
            var nx := float(x) / float(maxi(size.x - 1, 1))
            var ny := float(y) / float(maxi(size.y - 1, 1))
            var color := Color(
                0.25 + nx * 0.65,
                0.30 + ny * 0.60,
                0.82 if checker == 0 else 0.28,
                1.0
            )
            image.set_pixel(x, y, color)
    return ImageTexture.create_from_image(image)

func _rest_joints() -> Dictionary:
    return {
        "pelvis": Vector2(0.50, 0.92),
        "neck": Vector2(0.50, 0.55),
        "head": Vector2(0.50, 0.12),
    }

func _skin_recipe() -> Dictionary:
    return {
        "backend": "a1_render_regression",
        "vertices": [
            [0.18, 0.12], [0.82, 0.12],
            [0.18, 0.55], [0.82, 0.55],
            [0.18, 0.92], [0.82, 0.92],
        ],
        "triangles": [0, 2, 1, 1, 2, 3, 2, 4, 3, 3, 4, 5],
        "bone_weights": [
            {
                "a": "pelvis", "b": "neck",
                "weights": [0.0, 0.0, 0.5, 0.5, 1.0, 1.0],
            },
            {
                "a": "neck", "b": "head",
                "weights": [1.0, 1.0, 0.5, 0.5, 0.0, 0.0],
            },
        ],
    }

func _wait_render_frames(count: int = 3) -> void:
    for _i in range(count):
        await process_frame

func _capture() -> Image:
    return root.get_texture().get_image()

func _is_foreground(color: Color) -> bool:
    return color.r > 0.08 or color.g > 0.08 or color.b > 0.08

func _count_foreground(image: Image) -> int:
    var count := 0
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            if _is_foreground(image.get_pixel(x, y)):
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

func _save_evidence(case_name: String, baseline: Image, posed: Image) -> bool:
    var baseline_path := _artifact_dir.path_join("%s_baseline.png" % case_name)
    var posed_path := _artifact_dir.path_join("%s_posed.png" % case_name)
    return baseline.save_png(baseline_path) == OK and posed.save_png(posed_path) == OK

func _run_case(case_index: int, case_doc: Dictionary) -> Dictionary:
    var case_name := str(case_doc.get("name", "case_%d" % case_index))
    var texture_size: Vector2i = case_doc.get("size", Vector2i(128, 256))
    var head_x := float(case_doc.get("head_x", 0.75))

    var skinned := SkinnedCharacterScript.new() as VaultSkinnedCharacter
    skinned.name = "A1_%s" % case_name
    skinned.position = Vector2(320.0, 355.0)
    _world.add_child(skinned)

    var rest := _rest_joints()
    var bones := [["pelvis", "neck"], ["neck", "head"]]
    var texture := _make_texture(texture_size, case_index)
    if not skinned.setup(texture, rest, bones, _skin_recipe()):
        return {"ok": false, "reason": "setup_failed", "name": case_name}

    var stats := skinned.stats()
    if int(stats.get("vertices", 0)) != 6 or int(stats.get("bones", 0)) != 2:
        return {"ok": false, "reason": "unexpected_skin_stats_%s" % str(stats), "name": case_name}

    skinned.apply_joint_pose(rest)
    await _wait_render_frames(4)
    var baseline := _capture()
    var baseline_pixels := _count_foreground(baseline)

    var pose := rest.duplicate(true)
    pose["head"] = Vector2(head_x, 0.18)
    skinned.apply_joint_pose(pose)
    await _wait_render_frames(4)
    var posed := _capture()
    var changed_pixels := _count_changed(baseline, posed)
    var min_foreground := maxi(500, int(float(texture_size.x * texture_size.y) * 0.10))
    var min_changed := maxi(300, int(float(texture_size.x * texture_size.y) * 0.015))
    var evidence_saved := _save_evidence(case_name, baseline, posed)

    print("KROLIK_DEFORM case=%s texture=%dx%d vertices=%d bones=%d baseline_pixels=%d changed_pixels=%d min_changed=%d evidence=%s" % [
        case_name, texture_size.x, texture_size.y,
        int(stats.get("vertices", 0)), int(stats.get("bones", 0)),
        baseline_pixels, changed_pixels, min_changed, str(evidence_saved)
    ])

    _world.remove_child(skinned)
    skinned.queue_free()
    await _wait_render_frames(2)

    if baseline_pixels < min_foreground:
        return {"ok": false, "reason": "render_blank_or_too_small_%d_lt_%d" % [baseline_pixels, min_foreground], "name": case_name}
    if changed_pixels < min_changed:
        return {"ok": false, "reason": "insufficient_pixel_deformation_%d_lt_%d" % [changed_pixels, min_changed], "name": case_name}
    if not evidence_saved:
        return {"ok": false, "reason": "png_evidence_save_failed", "name": case_name}
    return {"ok": true, "name": case_name, "changed": changed_pixels, "foreground": baseline_pixels}

func _run() -> void:
    root.size = VIEWPORT_SIZE
    RenderingServer.set_default_clear_color(Color(0.005, 0.005, 0.008, 1.0))
    _world = Node2D.new()
    _world.name = "A1DeformationWorld"
    root.add_child(_world)

    _artifact_dir = ProjectSettings.globalize_path("res://deformation_artifacts")
    DirAccess.make_dir_recursive_absolute(_artifact_dir)
    await _wait_render_frames(3)

    var passed := 0
    var total_changed := 0
    for i in range(CASES.size()):
        var result: Dictionary = await _run_case(i, CASES[i])
        if not bool(result.get("ok", false)):
            push_error("KROLIK A1 deformation regression failed for %s: %s" % [str(result.get("name", "unknown")), str(result.get("reason", "unknown"))])
            quit(20 + i)
            return
        passed += 1
        total_changed += int(result.get("changed", 0))

    print("KROLIK_DEFORM_METRIC cases=%d passed=%d changed_pixels_total=%d renderer=%s" % [
        CASES.size(), passed, total_changed, RenderingServer.get_current_rendering_method()
    ])
    if passed != CASES.size():
        quit(29)
        return
    quit(0)
