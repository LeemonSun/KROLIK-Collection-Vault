class_name VaultCharacterAgent
extends CharacterBody2D

const SkinnedCharacterScript = preload("res://scripts/skinned_character.gd")
const CollisionRigScript = preload("res://scripts/collision_rig.gd")
const RuntimePackageCacheScript = preload("res://scripts/runtime_package_cache.gd")

var character_id := ""
var brain := VaultAgentBrain.new()
var animation_driver := VaultAnimationDriver.new()
var facial_state := VaultFacialState.new()
var facial_channels: Dictionary = {}
var secondary_motion := VaultSecondaryMotion.new()
var secondary_motion_enabled = false
var contained := false
var home_position := Vector2.ZERO
var target_position := Vector2.ZERO
var world_targets: Array[Vector2] = []
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
var animated_joints: Dictionary = {}
var solved_joints: Dictionary = {}
var rig_bones: Array = []
var skin_recipe: Dictionary = {}
var runtime_constraints: Array = []
var physics_proxies: Array = []
var debug_rig := false
var visual_root: Node2D
var skinned_visual: VaultSkinnedCharacter
var flat_sprite: Sprite2D
var collision_rig: VaultCollisionRig
var navigation_agent: NavigationAgent2D
var _navigation_target_valid := false
var _navigation_target := Vector2.ZERO

func setup(id_value: String, spawn: Vector2, mind: Dictionary = {}) -> void:
    character_id = id_value
    position = spawn
    home_position = spawn
    target_position = spawn
    _navigation_target_valid = false
    brain.apply_snapshot(mind)
    facial_state.configure({}, int(hash(character_id)))
    facial_channels = facial_state.semantic_snapshot()
    configure_secondary_motion({})
    _ensure_visual_root()
    _ensure_navigation_agent()
    collision_layer = 1
    collision_mask = 1
    queue_redraw()

func load_runtime_manifest(manifest_path: String, build_runtime_resources: bool = true) -> bool:
    var package: Dictionary = RuntimePackageCacheScript.load_package(manifest_path)
    if package.is_empty():
        return false
    var manifest_value: Variant = package.get("manifest", {})
    if typeof(manifest_value) != TYPE_DICTIONARY:
        return false
    var manifest: Dictionary = manifest_value
    var shared_texture: Texture2D = package.get("texture", null) as Texture2D
    if shared_texture == null:
        return false
    character_texture = shared_texture

    var c: Dictionary = manifest.get("character", {})
    character_id = str(c.get("id", character_id))
    var mind: Dictionary = manifest.get("mind", {})
    brain.apply_snapshot(mind)
    var animation_doc: Dictionary = manifest.get("animation", {})
    animation_driver.configure(animation_doc)
    facial_state.configure(animation_doc, int(hash(character_id)))
    facial_channels = facial_state.semantic_snapshot()
    var visual: Dictionary = manifest.get("visual", {})
    texture_scale = float(visual.get("runtime_scale", texture_scale))
    contained = str(mind.get("state", "")) == "contained"
    var rig: Dictionary = manifest.get("rig", {})
    rig_joints.clear()
    var joint_doc: Dictionary = rig.get("joints", {})
    for joint_name in joint_doc.keys():
        var point: Dictionary = joint_doc[joint_name]
        rig_joints[str(joint_name)] = Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0)))
    rig_bones = rig.get("bones", []).duplicate(true)
    var mesh_doc: Dictionary = rig.get("mesh", {})
    skin_recipe = mesh_doc.get("skinning", rig.get("skinning", {})).duplicate(true)
    if skin_recipe.is_empty():
        skin_recipe = rig.get("skinning", {}).duplicate(true)
    var physics_doc: Dictionary = manifest.get("physics", {})
    physics_proxies = physics_doc.get("collision", []).duplicate(true)
    var secondary_doc = physics_doc.get("secondary", {})
    configure_secondary_motion(secondary_doc if typeof(secondary_doc) == TYPE_DICTIONARY else {})
    animated_joints = rig_joints.duplicate(true)
    solved_joints = animated_joints.duplicate(true)
    _solve_runtime_constraints(animated_joints)
    if build_runtime_resources:
        _rebuild_character_visual()
        _rebuild_collision_rig()
    else:
        _clear_character_visual()
        if collision_rig != null:
            collision_rig.clear()
            collision_rig = null
    queue_redraw()
    return true

func configure_secondary_motion(doc: Dictionary) -> void:
    secondary_motion.configure(doc)
    secondary_motion_enabled = not doc.is_empty()

func set_animation_layer(
    layer_name: String,
    clip_name: String,
    weight: float = 1.0,
    joint_mask: Array = [],
    root_weight: float = 0.0,
    playback_speed: float = 1.0,
    restart: bool = true
) -> bool:
    return animation_driver.set_additive_layer(
        layer_name, clip_name, weight, joint_mask, root_weight, playback_speed, restart
    )

func clear_animation_layer(layer_name: String) -> bool:
    return animation_driver.clear_additive_layer(layer_name)

func set_look_target(normalized_target: Vector2) -> void:
    facial_state.set_look_target(normalized_target)

func clear_look_target() -> void:
    facial_state.clear_look_target()

func set_mood(name: String, intensity: float = 1.0, transition: float = 0.20) -> bool:
    return facial_state.set_mood(name, intensity, transition)

func facial_snapshot() -> Dictionary:
    return facial_channels.duplicate(true)

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
    _solve_runtime_constraints(animated_joints if not animated_joints.is_empty() else rig_joints)
    _apply_visual_transform()
    queue_redraw()

func _solve_runtime_constraints(base_pose: Dictionary = {}) -> void:
    solved_joints = (base_pose if not base_pose.is_empty() else rig_joints).duplicate(true)
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
        var root_name := str(chain[0])
        var mid_name := str(chain[1])
        var end_name := str(chain[2])
        var target: Vector2 = raw.get("target_v", Vector2(0.5, 0.5))
        var default_limits := VaultIKSolver.default_limits(mid_name)
        solved_joints = VaultIKSolver.apply_chain(
            solved_joints,
            root_name,
            mid_name,
            end_name,
            target,
            float(raw.get("strength", 1.0)),
            float(raw.get("max_stretch", 1.0)),
            float(raw.get("min_joint_deg", default_limits.x)),
            float(raw.get("max_joint_deg", default_limits.y))
        )

func _apply_facial_pose(face_sample: Dictionary) -> void:
    var channels = face_sample.get("channels", {})
    facial_channels = channels.duplicate(true) if typeof(channels) == TYPE_DICTIONARY else {}
    var offsets = face_sample.get("joint_offsets", {})
    if typeof(offsets) != TYPE_DICTIONARY:
        return
    for raw_name in offsets.keys():
        var joint_name := str(raw_name)
        if not animated_joints.has(joint_name):
            continue
        var offset = offsets[raw_name]
        if typeof(offset) == TYPE_VECTOR2:
            animated_joints[joint_name] = animated_joints[joint_name] + offset

func _apply_secondary_motion(delta: float) -> void:
    if not secondary_motion_enabled or animated_joints.is_empty():
        return
    var channel_offsets := secondary_motion.step(delta, velocity)
    if channel_offsets.is_empty():
        return
    var offsets := secondary_motion.joint_offsets(channel_offsets)
    if offsets.is_empty():
        return

    # IK endpoints remain authoritative. A wrist/ankle explicitly constrained by
    # an interaction is not pre-shifted by an accessory spring before the IK
    # solve. Other secondary channels still contribute to the animated base pose.
    var constrained_ends: Dictionary = {}
    for raw in runtime_constraints:
        if typeof(raw) != TYPE_DICTIONARY or not bool(raw.get("enabled", true)):
            continue
        var constrained_name := str(raw.get("joint", ""))
        if not constrained_name.is_empty():
            constrained_ends[constrained_name] = true

    for raw_name in offsets.keys():
        var joint_name := str(raw_name)
        if constrained_ends.has(joint_name) or not animated_joints.has(joint_name):
            continue
        var offset = offsets[raw_name]
        if typeof(offset) != TYPE_VECTOR2:
            continue
        animated_joints[joint_name] = animated_joints[joint_name] + offset

func _apply_animation_pose(sample: Dictionary, delta: float = 0.0) -> void:
    animated_joints = rig_joints.duplicate(true)
    var offsets = sample.get("joint_offsets", {})
    if typeof(offsets) == TYPE_DICTIONARY:
        for joint_name in offsets.keys():
            var name := str(joint_name)
            if not animated_joints.has(name):
                continue
            var raw = offsets[joint_name]
            var joint_delta := Vector2.ZERO
            if typeof(raw) == TYPE_VECTOR2:
                joint_delta = raw
            elif typeof(raw) == TYPE_ARRAY and raw.size() >= 2:
                joint_delta = Vector2(float(raw[0]), float(raw[1]))
            elif typeof(raw) == TYPE_DICTIONARY:
                joint_delta = Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)))
            animated_joints[name] = animated_joints[name] + joint_delta
    if facial_state.enabled:
        _apply_facial_pose(facial_state.step(delta))
    _apply_secondary_motion(delta)
    _solve_runtime_constraints(animated_joints)

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
    _rebuild_character_visual()
    if not physics_proxies.is_empty():
        _rebuild_collision_rig()
    queue_redraw()
    return true

func _ensure_navigation_agent() -> void:
    if navigation_agent != null and is_instance_valid(navigation_agent):
        return
    navigation_agent = NavigationAgent2D.new()
    navigation_agent.name = "NavigationAgent2D"
    navigation_agent.path_desired_distance = 10.0
    navigation_agent.target_desired_distance = 12.0
    navigation_agent.radius = 12.0
    navigation_agent.neighbor_distance = 90.0
    navigation_agent.avoidance_enabled = false
    add_child(navigation_agent)
    _navigation_target_valid = false

func _sync_navigation_target() -> void:
    if navigation_agent == null:
        return
    if _navigation_target_valid and _navigation_target.distance_squared_to(target_position) <= 0.01:
        return
    _navigation_target = target_position
    _navigation_target_valid = true
    navigation_agent.target_position = target_position

func _movement_waypoint() -> Vector2:
    if navigation_agent == null:
        return target_position
    _sync_navigation_target()
    var map_rid := navigation_agent.get_navigation_map()
    if not map_rid.is_valid() or NavigationServer2D.map_get_iteration_id(map_rid) <= 0:
        return target_position
    # NavigationAgent2D can be attached to a valid World2D map before that map
    # contains a usable region/path. In that state get_next_path_position() may
    # resolve to the character's current position and silently stall locomotion.
    # Keep the direct-target path as a deterministic fallback until a genuine
    # navigation path exists; once it does, the agent follows navigation again.
    var path := navigation_agent.get_current_navigation_path()
    if path.is_empty() or not navigation_agent.is_target_reachable() or navigation_agent.is_navigation_finished():
        return target_position
    var next_waypoint := navigation_agent.get_next_path_position()
    if next_waypoint.distance_squared_to(global_position) <= 0.25:
        return target_position
    return next_waypoint

func _rebuild_collision_rig() -> void:
    if collision_rig != null:
        collision_rig.clear()
        collision_rig = null
    if character_texture == null or physics_proxies.is_empty():
        return
    collision_rig = CollisionRigScript.new()
    collision_rig.setup(self, character_texture.get_size(), physics_proxies, texture_scale)
    collision_rig.apply_joint_pose(solved_joints if not solved_joints.is_empty() else rig_joints, texture_scale, facing)

func _ensure_visual_root() -> void:
    if visual_root != null and is_instance_valid(visual_root):
        return
    visual_root = Node2D.new()
    visual_root.name = "CharacterVisual"
    add_child(visual_root)

func _clear_character_visual() -> void:
    _ensure_visual_root()
    for child in visual_root.get_children():
        visual_root.remove_child(child)
        child.queue_free()
    skinned_visual = null
    flat_sprite = null

func _rebuild_character_visual() -> void:
    if character_texture == null:
        return
    _clear_character_visual()
    if not rig_joints.is_empty() and not rig_bones.is_empty() and not skin_recipe.is_empty():
        skinned_visual = SkinnedCharacterScript.new()
        skinned_visual.name = "GPUDeformableCharacter"
        visual_root.add_child(skinned_visual)
        if skinned_visual.setup(character_texture, rig_joints, rig_bones, skin_recipe):
            skinned_visual.apply_joint_pose(solved_joints if not solved_joints.is_empty() else rig_joints)
            return
        skinned_visual.queue_free()
        skinned_visual = null
    flat_sprite = Sprite2D.new()
    flat_sprite.name = "FlatFallback"
    flat_sprite.texture = character_texture
    flat_sprite.centered = true
    flat_sprite.position = Vector2(0.0, -character_texture.get_height() * 0.5)
    visual_root.add_child(flat_sprite)

func _apply_visual_transform() -> void:
    if visual_root == null:
        return
    visual_root.position = _visual_offset
    visual_root.rotation = _visual_rotation
    visual_root.scale = Vector2(
        texture_scale * _visual_scale.x * facing,
        texture_scale * _visual_scale.y
    )
    if skinned_visual != null and is_instance_valid(skinned_visual):
        skinned_visual.apply_joint_pose(solved_joints)
    if collision_rig != null and is_instance_valid(collision_rig):
        collision_rig.apply_joint_pose(solved_joints, texture_scale, facing)

func _physics_process(delta: float) -> void:
    phase += delta
    var mind_context := {
        "bound": contained,
        "interaction_mode": "contained" if contained else "",
        "away_from_home": global_position.distance_to(home_position) > 36.0,
        "interesting_targets": float(world_targets.size()),
        "social_targets": 0.0,
    }
    brain.state = brain.step(delta, mind_context)
    walk_speed = 80.0 * brain.walk_speed
    match brain.state:
        "wander", "inspect", "social", "return_home":
            if global_position.distance_to(target_position) < 8.0:
                _choose_target()
            var waypoint := _movement_waypoint()
            var desired := global_position.direction_to(waypoint) * walk_speed
            velocity = velocity.move_toward(desired, acceleration * delta)
            move_and_slide()
            if absf(velocity.x) > 0.5:
                facing = signf(velocity.x)
        "rest", "contained", "idle", "disabled":
            velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
            if velocity.length_squared() > .01:
                move_and_slide()
    animation_driver.set_state(brain.state)
    var sample := animation_driver.step(delta)
    _visual_offset = sample.get("offset", Vector2.ZERO)
    _visual_rotation = float(sample.get("rotation", 0.0))
    _visual_scale = sample.get("scale", Vector2.ONE)
    _apply_animation_pose(sample, delta)
    _apply_visual_transform()
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
        _navigation_target_valid = false
        _sync_navigation_target()
        return
    if not world_targets.is_empty():
        var index := int(absf(sin(phase * 0.73)) * float(world_targets.size())) % world_targets.size()
        target_position = world_targets[index]
    else:
        var radius := 130.0 if brain.state == "wander" else 80.0
        target_position = home_position + Vector2(cos(phase * 1.7), sin(phase * 1.13)) * radius
    _navigation_target_valid = false
    _sync_navigation_target()

func _draw() -> void:
    if character_texture:
        if debug_rig and not solved_joints.is_empty():
            var bones := [
                ["head","neck"], ["neck","left_shoulder"], ["left_shoulder","left_elbow"], ["left_elbow","left_wrist"],
                ["neck","right_shoulder"], ["right_shoulder","right_elbow"], ["right_elbow","right_wrist"], ["neck","pelvis"],
                ["pelvis","left_hip"], ["left_hip","left_knee"], ["left_knee","left_ankle"],
                ["pelvis","right_hip"], ["right_hip","right_knee"], ["right_knee","right_ankle"]
            ]
            for bone in bones:
                if solved_joints.has(bone[0]) and solved_joints.has(bone[1]):
                    var p0 := _rig_to_local(solved_joints[bone[0]], character_texture.get_size()) * texture_scale
                    var p1 := _rig_to_local(solved_joints[bone[1]], character_texture.get_size()) * texture_scale
                    draw_line(p0, p1, Color(0.2,0.9,0.8,0.85), 1.5)
        return
    var tint := Color(0.8, 0.55, 0.65, 0.95)
    if brain.state == "contained": tint = Color(0.55, 0.55, 0.65, 0.95)
    draw_circle(_visual_offset, 18.0, tint)
    draw_line(_visual_offset + Vector2(0, -18), _visual_offset + Vector2(0, 24), tint, 8.0)