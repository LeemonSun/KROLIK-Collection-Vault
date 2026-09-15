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
var secondary_motion_enabled := false
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
var interaction_context: Dictionary = {}
var social_target_id := ""
var social_target_position := Vector2.ZERO
var social_target_valid := false
var social_candidate_count := 0
var social_affinity := 0.0
var social_familiarity := 0.0
var social_event_outcome := 0.0
var social_event_timer := 0.0
var nearby_witnesses := 0
var _last_face_mood := ""

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
    var package: Dictionary = RuntimePackageCacheScript.load_package(manifest_path, build_runtime_resources)
    if package.is_empty():
        return false
    var manifest_value: Variant = package.get("manifest", {})
    if typeof(manifest_value) != TYPE_DICTIONARY:
        return false
    var manifest: Dictionary = manifest_value
    var shared_texture: Texture2D = package.get("texture", null) as Texture2D
    if build_runtime_resources and shared_texture == null:
        return false
    character_texture = shared_texture if build_runtime_resources else null

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
        character_texture = null
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

func _normalized_constraint_kind(value: String) -> String:
    var raw := value.to_lower()
    if "ankle" in raw and "shackle" in raw: return "ankle_shackles"
    if "shackle" in raw: return "shackles"
    if "cuff" in raw: return "cuffs"
    if "stool" in raw: return "restraint_stool"
    if "chair" in raw: return "restraint_chair"
    if "stock" in raw: return "stocks"
    if "cage" in raw: return "cage"
    if "wall" in raw and "anchor" in raw: return "wall_anchor"
    if "harness" in raw: return "harness"
    if "rope" in raw: return "rope"
    if "tether" in raw or "chain" in raw: return "tether"
    if raw in ["bound", "anchored", "restrained", "contained"]: return "contained"
    return raw if not raw.is_empty() else "generic"

func _interaction_semantics(data: Dictionary) -> Dictionary:
    var count := runtime_constraints.size()
    var constrained := count > 0 or bool(data.get("contained", false))
    var raw_kind := str(data.get("constraint_kind", data.get("fixture_kind", data.get("kind", data.get("interaction_mode", "")))))
    var severity_default := clampf(0.18 + float(count) * 0.18 + (0.18 if bool(data.get("contained", false)) else 0.0), 0.0, 1.0) if constrained else 0.0
    return {
        "constraint_kind": _normalized_constraint_kind(raw_kind),
        "constraint_severity": clampf(float(data.get("constraint_severity", severity_default)), 0.0, 1.0),
        "constraint_novelty": clampf(float(data.get("constraint_novelty", 0.55 if constrained else 0.0)), 0.0, 1.0),
        "discomfort": clampf(float(data.get("discomfort", 0.0)), 0.0, 1.0),
        "threat": clampf(float(data.get("threat", 0.0)), 0.0, 1.0),
        "pain": clampf(float(data.get("pain", 0.0)), 0.0, 1.0),
        "witnesses": maxi(0, int(data.get("witnesses", 0))),
        "safe": bool(data.get("safe", false)),
        "released": bool(data.get("released", false)),
    }

func set_social_runtime_context(target_id: String, target_pos: Vector2, candidate_count: int, affinity: float, familiarity: float) -> void:
    social_target_id = target_id
    social_target_position = target_pos
    social_target_valid = not target_id.is_empty()
    social_candidate_count = maxi(0, candidate_count)
    social_affinity = clampf(affinity, -1.0, 1.0)
    social_familiarity = clampf(familiarity, 0.0, 1.0)

func set_nearby_witnesses(value: int) -> void:
    nearby_witnesses = maxi(0, value)

func relationship_to(subject: String) -> Dictionary:
    for raw in brain.long_term_snapshot().get("relationships", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = raw
        if str(entry.get("subject", "")) == subject:
            return entry.duplicate(true)
    return {}

func register_social_encounter(partner_id: String, outcome: float) -> void:
    var resolved := clampf(outcome, -1.0, 1.0)
    brain.remember_event("social", partner_id, resolved, 0.78, 240.0)
    brain.reinforce_relationship(partner_id, resolved, 0.72)
    social_event_outcome = resolved
    social_event_timer = 6.0
    var relation := relationship_to(partner_id)
    social_affinity = float(relation.get("affinity", social_affinity))
    social_familiarity = float(relation.get("familiarity", social_familiarity))

func apply_runtime_interaction(data: Dictionary) -> void:
    var was_contained := contained
    runtime_constraints.clear()
    for raw in data.get("constraints", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var item: Dictionary = raw.duplicate(true)
        var t: Dictionary = item.get("target", {})
        item["target_v"] = Vector2(float(t.get("x", 0.5)), float(t.get("y", 0.5)))
        runtime_constraints.append(item)
    contained = bool(data.get("contained", contained)) or not runtime_constraints.is_empty()
    interaction_context = _interaction_semantics(data)
    interaction_context["released"] = bool(data.get("released", false)) or (was_contained and not contained)
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
    social_event_timer = maxf(0.0, social_event_timer - delta)
    var mind_context := {
        "bound": contained,
        "interaction_mode": "contained" if contained else "",
        "away_from_home": global_position.distance_to(home_position) > 36.0,
        "interesting_targets": float(world_targets.size()),
        "social_targets": float(social_candidate_count),
        "social_subject": social_target_id,
        "social_affinity": social_affinity,
        "social_familiarity": social_familiarity,
        "social_success": social_event_outcome if social_event_timer > 0.0 else 0.0,
    }
    for key in interaction_context.keys():
        mind_context[key] = interaction_context[key]
    mind_context["witnesses"] = maxf(float(mind_context.get("witnesses", 0.0)), float(nearby_witnesses))
    brain.state = brain.step(delta, mind_context)
    walk_speed = 80.0 * brain.walk_speed
    match brain.state:
        "wander", "inspect", "social", "return_home":
            if brain.state == "social" and social_target_valid:
                target_position = social_target_position
                _navigation_target_valid = false
            elif global_position.distance_to(target_position) < 8.0:
                _choose_target()
            var waypoint := _movement_waypoint()
            var desired := global_position.direction_to(waypoint) * walk_speed
            if brain.state == "social" and social_target_valid and global_position.distance_to(social_target_position) < 34.0:
                desired = Vector2.ZERO
            velocity = velocity.move_toward(desired, acceleration * delta)
            move_and_slide()
            if absf(velocity.x) > 0.5:
                facing = signf(velocity.x)
        "rest", "contained", "idle", "disabled":
            velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
            if velocity.length_squared() > .01:
                move_and_slide()
    var affect := brain.affect_snapshot()
    var face_mood := str(affect.get("facial_mood", affect.get("mood", "calm")))
    if face_mood != _last_face_mood:
        if facial_state.set_mood(face_mood, maxf(0.18, float(affect.get("intensity", 0.0))), 0.28):
            _last_face_mood = face_mood
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
    if brain.state == "social" and social_target_valid:
        target_position = social_target_position
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