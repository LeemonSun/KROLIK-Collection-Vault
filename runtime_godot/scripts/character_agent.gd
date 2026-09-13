class_name VaultCharacterAgent
extends Node2D

var character_id := ""
var brain := VaultAgentBrain.new()
var animation_driver := VaultAnimationDriver.new()
var contained := false
var home_position := Vector2.ZERO
var target_position := Vector2.ZERO
var world_targets: Array[Vector2] = []
var velocity := Vector2.ZERO
var acceleration := 540.0
var facing := 1.0
var walk_speed := 80.0
var phase := 0.0
var character_texture: Texture2D
var texture_scale := 0.35
var _visual_offset := Vector2.ZERO
var _visual_rotation := 0.0
var _visual_scale := Vector2.ONE
var rig_joints: Dictionary = {}
var solved_joints: Dictionary = {}
var runtime_constraints: Array = []
var debug_rig := false

func setup(id_value: String, spawn: Vector2, mind: Dictionary = {}) -> void:
    character_id = id_value
    position = spawn
    home_position = spawn
    target_position = spawn
    brain.apply_snapshot(mind)
    queue_redraw()

func load_runtime_manifest(manifest_path: String) -> bool:
    var file := FileAccess.open(manifest_path, FileAccess.READ)
    if file == null:
        return false
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    var manifest: Dictionary = parsed
    var c: Dictionary = manifest.get("character", {})
    character_id = str(c.get("id", character_id))
    var mind: Dictionary = manifest.get("mind", {})
    brain.apply_snapshot(mind)
    var visual: Dictionary = manifest.get("visual", {})
    var image_name := str(visual.get("file", "character.png"))
    var image_path := manifest_path.get_base_dir().path_join(image_name)
    if not set_character_image(image_path):
        return false
    texture_scale = float(visual.get("runtime_scale", texture_scale))
    contained = str(mind.get("state", "")) == "contained"
    var rig: Dictionary = manifest.get("rig", {})
    rig_joints.clear()
    var joint_doc: Dictionary = rig.get("joints", {})
    for joint_name in joint_doc.keys():
        var point: Dictionary = joint_doc[joint_name]
        rig_joints[str(joint_name)] = Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0)))
    solved_joints = rig_joints.duplicate(true)
    _solve_runtime_constraints()
    queue_redraw()
    return true

func apply_runtime_interaction(data: Dictionary) -> void:
    runtime_constraints.clear()
    for raw in data.get("constraints", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var item: Dictionary = raw.duplicate(true)
        var t: Dictionary = item.get("target", {})
        item["target_v"] = Vector2(float(t.get("x", 0.5)), float(t.get("y", 0.5)))
        runtime_constraints.append(item)
    contained = bool(data.get("contained", contained)) or not runtime_constraints.is_empty()
    _solve_runtime_constraints()
    queue_redraw()

func _solve_runtime_constraints() -> void:
    solved_joints = rig_joints.duplicate(true)
    if solved_joints.is_empty():
        return
    var chains := {
        "left_wrist": ["left_shoulder", "left_elbow", "left_wrist"],
        "right_wrist": ["right_shoulder", "right_elbow", "right_wrist"],
        "left_ankle": ["left_hip", "left_knee", "left_ankle"],
        "right_ankle": ["right_hip", "right_knee", "right_ankle"],
    }
    for raw in runtime_constraints:
        if not bool(raw.get("enabled", true)):
            continue
        var joint := str(raw.get("joint", ""))
        if not chains.has(joint):
            continue
        var chain: Array = chains[joint]
        var target: Vector2 = raw.get("target_v", Vector2(0.5, 0.5))
        solved_joints = VaultIKSolver.apply_chain(solved_joints, str(chain[0]), str(chain[1]), str(chain[2]), target, float(raw.get("strength", 1.0)))

func _rig_to_local(p: Vector2, size: Vector2) -> Vector2:
    return Vector2((p.x - 0.5) * size.x, (p.y - 1.0) * size.y)

func set_character_image(path: String) -> bool:
    if path.is_empty():
        return false
    var image := Image.new()
    var err := image.load(path)
    if err != OK:
        return false
    character_texture = ImageTexture.create_from_image(image)
    queue_redraw()
    return true

func _process(delta: float) -> void:
    phase += delta
    brain.state = brain.step(delta, contained)
    match brain.state:
        "wander", "inspect", "social", "return_home":
            if position.distance_to(target_position) < 8.0:
                _choose_target()
            var desired := (target_position - position).normalized() * walk_speed
            velocity = velocity.move_toward(desired, acceleration * delta)
            position += velocity * delta
            if absf(velocity.x) > 0.5:
                facing = signf(velocity.x)
        "rest", "contained", "idle", "disabled":
            velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
    animation_driver.set_animation(_animation_for_state(brain.state))
    var sample := animation_driver.step(delta)
    _visual_offset = sample.offset
    _visual_rotation = sample.rotation
    _visual_scale = sample.scale
    queue_redraw()

func _animation_for_state(state_name: String) -> String:
    match state_name:
        "wander", "return_home": return "walk"
        "inspect": return "inspect"
        "social": return "social_idle"
        "contained": return "contained_idle"
        "rest": return "rest"
        "disabled": return "idle_static"
        _: return "idle_breathe"

func _choose_target() -> void:
    if brain.state == "return_home":
        target_position = home_position
        return
    if not world_targets.is_empty():
        var index := int(absf(sin(phase * 0.73)) * float(world_targets.size())) % world_targets.size()
        target_position = world_targets[index]
        return
    var radius := 130.0 if brain.state == "wander" else 80.0
    target_position = home_position + Vector2(cos(phase * 1.7), sin(phase * 1.13)) * radius

func _draw() -> void:
    if character_texture:
        var size := character_texture.get_size() * texture_scale
        var sx := _visual_scale.x * facing
        var draw_w := size.x * sx
        var rect := Rect2(-draw_w * 0.5 + _visual_offset.x, -size.y + _visual_offset.y, draw_w, size.y * _visual_scale.y)
        draw_set_transform(Vector2.ZERO, _visual_rotation, Vector2.ONE)
        draw_texture_rect(character_texture, rect, false)
        if debug_rig and not solved_joints.is_empty():
            var bones := [["head","neck"],["neck","left_shoulder"],["left_shoulder","left_elbow"],["left_elbow","left_wrist"],["neck","right_shoulder"],["right_shoulder","right_elbow"],["right_elbow","right_wrist"],["neck","pelvis"],["pelvis","left_hip"],["left_hip","left_knee"],["left_knee","left_ankle"],["pelvis","right_hip"],["right_hip","right_knee"],["right_knee","right_ankle"]]
            for bone in bones:
                if solved_joints.has(bone[0]) and solved_joints.has(bone[1]):
                    draw_line(_rig_to_local(solved_joints[bone[0]], size), _rig_to_local(solved_joints[bone[1]], size), Color(0.2,0.9,0.8,0.85), 1.5)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        return
    var tint := Color(0.8, 0.55, 0.65, 0.95)
    if brain.state == "contained": tint = Color(0.55, 0.55, 0.65, 0.95)
    draw_circle(_visual_offset, 18.0, tint)
    draw_line(_visual_offset + Vector2(0, -18), _visual_offset + Vector2(0, 24), tint, 8.0)
