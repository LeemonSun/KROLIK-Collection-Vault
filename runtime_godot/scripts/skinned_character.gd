class_name VaultSkinnedCharacter
extends Node2D

## Realtime 2D GPU skin bridge for KROLIK runtime characters.
##
## A character is exported as a normalized grid + per-bone vertex weights.
## Godot keeps the pixels on a Polygon2D and performs skeletal deformation on
## the renderer side.  The Python CPU warp remains an offline/reference tool.

var character_texture: Texture2D
var texture_size := Vector2.ONE
var rest_joints: Dictionary = {}
var bone_pairs: Array = []
var skin_recipe: Dictionary = {}

var skeleton: Skeleton2D
var polygon: Polygon2D
var segment_nodes: Array = []
var runtime_ready := false
var vertex_count := 0

func setup(texture: Texture2D, joints: Dictionary, bones: Array, recipe: Dictionary = {}) -> bool:
    character_texture = texture
    texture_size = texture.get_size() if texture != null else Vector2.ONE
    rest_joints = joints.duplicate(true)
    bone_pairs = bones.duplicate(true)
    skin_recipe = recipe.duplicate(true)
    _clear_runtime_nodes()
    if character_texture == null or rest_joints.is_empty() or bone_pairs.is_empty():
        runtime_ready = false
        return false
    _build_skeleton()
    _build_polygon()
    runtime_ready = polygon != null and polygon.get_bone_count() > 0 and vertex_count >= 4
    return runtime_ready

func _clear_runtime_nodes() -> void:
    for child in get_children():
        remove_child(child)
        child.queue_free()
    skeleton = null
    polygon = null
    segment_nodes.clear()
    vertex_count = 0
    runtime_ready = false

func _point(doc: Dictionary, name: String) -> Vector2:
    if not doc.has(name) or typeof(doc[name]) != TYPE_VECTOR2:
        return Vector2.ZERO
    return doc[name]

func _rig_to_local(p: Vector2) -> Vector2:
    return Vector2((p.x - 0.5) * texture_size.x, (p.y - 1.0) * texture_size.y)

func _build_skeleton() -> void:
    skeleton = Skeleton2D.new()
    skeleton.name = "Skeleton2D"
    add_child(skeleton)
    for index in range(bone_pairs.size()):
        var pair = bone_pairs[index]
        if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
            continue
        var a := str(pair[0])
        var b := str(pair[1])
        if not rest_joints.has(a) or not rest_joints.has(b):
            continue
        var p0 := _rig_to_local(rest_joints[a])
        var p1 := _rig_to_local(rest_joints[b])
        var delta := p1 - p0
        if delta.length_squared() < 0.0001:
            continue
        var bone := Bone2D.new()
        bone.name = "Seg_%02d_%s_%s" % [index, a, b]
        bone.set_autocalculate_length_and_angle(false)
        bone.position = p0
        bone.rotation = delta.angle()
        bone.length = maxf(1.0, delta.length())
        skeleton.add_child(bone)
        # Direct-child segment bones are deliberate: each exported segment has
        # an independent rest->pose transform and blends through vertex weights.
        bone.rest = bone.transform
        segment_nodes.append({
            "a": a,
            "b": b,
            "node": bone,
            "rest_length": maxf(1.0, delta.length()),
        })

func _build_polygon() -> void:
    polygon = Polygon2D.new()
    polygon.name = "SkinnedPolygon"
    polygon.texture = character_texture
    polygon.antialiased = true
    add_child(polygon)
    polygon.skeleton = polygon.get_path_to(skeleton)

    var vertices_doc = skin_recipe.get("vertices", [])
    var triangles_doc = skin_recipe.get("triangles", [])
    if typeof(vertices_doc) != TYPE_ARRAY or vertices_doc.size() < 4:
        _build_flat_fallback()
        return

    var vertices := PackedVector2Array()
    var uvs := PackedVector2Array()
    for raw in vertices_doc:
        if typeof(raw) != TYPE_ARRAY or raw.size() < 2:
            continue
        var nx := float(raw[0])
        var ny := float(raw[1])
        vertices.append(Vector2((nx - 0.5) * texture_size.x, (ny - 1.0) * texture_size.y))
        uvs.append(Vector2(nx * texture_size.x, ny * texture_size.y))
    polygon.polygon = vertices
    polygon.uv = uvs
    vertex_count = vertices.size()

    if typeof(triangles_doc) == TYPE_ARRAY and triangles_doc.size() >= 3:
        var triangles: Array = []
        var i := 0
        while i + 2 < triangles_doc.size():
            triangles.append(PackedInt32Array([
                int(triangles_doc[i]),
                int(triangles_doc[i + 1]),
                int(triangles_doc[i + 2]),
            ]))
            i += 3
        polygon.polygons = triangles

    _bind_weights()

func _build_flat_fallback() -> void:
    var w := texture_size.x
    var h := texture_size.y
    polygon.polygon = PackedVector2Array([
        Vector2(-w * 0.5, -h), Vector2(w * 0.5, -h),
        Vector2(w * 0.5, 0.0), Vector2(-w * 0.5, 0.0),
    ])
    polygon.uv = PackedVector2Array([
        Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h),
    ])
    polygon.polygons = [PackedInt32Array([0, 3, 1]), PackedInt32Array([1, 3, 2])]
    vertex_count = 4

func _segment_for(a: String, b: String) -> Dictionary:
    for segment in segment_nodes:
        if str(segment.get("a", "")) == a and str(segment.get("b", "")) == b:
            return segment
    return {}

func _bind_weights() -> void:
    polygon.clear_bones()
    var weight_docs = skin_recipe.get("bone_weights", [])
    if typeof(weight_docs) != TYPE_ARRAY:
        return
    for raw in weight_docs:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var a := str(raw.get("a", ""))
        var b := str(raw.get("b", ""))
        var segment := _segment_for(a, b)
        if segment.is_empty():
            continue
        var source_weights = raw.get("weights", [])
        if typeof(source_weights) != TYPE_ARRAY or source_weights.size() != vertex_count:
            continue
        var weights := PackedFloat32Array()
        weights.resize(vertex_count)
        for i in range(vertex_count):
            weights[i] = clampf(float(source_weights[i]), 0.0, 1.0)
        var bone: Bone2D = segment["node"]
        # Polygon2D bone paths are relative to the assigned Skeleton2D.
        polygon.add_bone(skeleton.get_path_to(bone), weights)

func apply_joint_pose(joints: Dictionary) -> void:
    if not runtime_ready:
        return
    for segment in segment_nodes:
        var a := str(segment.get("a", ""))
        var b := str(segment.get("b", ""))
        if not joints.has(a) or not joints.has(b):
            continue
        var p0 := _rig_to_local(joints[a])
        var p1 := _rig_to_local(joints[b])
        var delta := p1 - p0
        if delta.length_squared() < 0.0001:
            continue
        var bone: Bone2D = segment["node"]
        bone.position = p0
        bone.rotation = delta.angle()
        var rest_length := maxf(1.0, float(segment.get("rest_length", delta.length())))
        # Two-bone IK normally preserves segment length.  The clamped ratio also
        # makes edited rigs and future pose clips tolerant of small discrepancies.
        bone.scale = Vector2(clampf(delta.length() / rest_length, 0.72, 1.38), 1.0)

func stats() -> Dictionary:
    return {
        "runtime_ready": runtime_ready,
        "vertices": vertex_count,
        "bones": polygon.get_bone_count() if polygon != null else 0,
        "segments": segment_nodes.size(),
        "backend": str(skin_recipe.get("backend", "flat_fallback")),
    }
