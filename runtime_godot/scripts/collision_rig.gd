class_name VaultCollisionRig
extends Node2D

## Runtime collision proxy builder.  Proxies are exported from the same rig that
## drives GPU skinning, so physics and visual joints share one coordinate space.

var texture_size := Vector2.ONE
var proxies: Array = []
var shapes: Array = []
var runtime_scale := 1.0
var facing := 1.0

func setup(size: Vector2, proxy_docs: Array, display_scale: float = 1.0) -> void:
    texture_size = size
    runtime_scale = maxf(.001, display_scale)
    proxies = proxy_docs.duplicate(true)
    _clear_shapes()
    for raw in proxies:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        if str(raw.get("type", "")) != "capsule_segment":
            continue
        var p0_doc: Dictionary = raw.get("p0", {})
        var p1_doc: Dictionary = raw.get("p1", {})
        var p0 := _rig_to_local(Vector2(float(p0_doc.get("x", .5)), float(p0_doc.get("y", .5))))
        var p1 := _rig_to_local(Vector2(float(p1_doc.get("x", .5)), float(p1_doc.get("y", .5))))
        var radius_norm := maxf(.008, float(raw.get("radius", .04)))
        var radius_px := radius_norm * minf(texture_size.x, texture_size.y) * runtime_scale
        var delta := p1 - p0
        if delta.length_squared() < 1.0:
            continue
        var capsule := CapsuleShape2D.new()
        capsule.radius = maxf(1.5, radius_px)
        capsule.height = maxf(capsule.radius * 2.0, delta.length() + capsule.radius * 2.0)
        var shape_node := CollisionShape2D.new()
        shape_node.name = "Collision_%s_%s" % [str(raw.get("a", "a")), str(raw.get("b", "b"))]
        shape_node.shape = capsule
        shape_node.position = (p0 + p1) * .5
        # CapsuleShape2D's long axis is local Y.
        shape_node.rotation = delta.angle() - PI * .5
        shape_node.disabled = bool(raw.get("sensor", false))
        add_child(shape_node)
        shapes.append({
            "a": str(raw.get("a", "")),
            "b": str(raw.get("b", "")),
            "node": shape_node,
            "radius_norm": radius_norm,
        })

func _clear_shapes() -> void:
    for child in get_children():
        remove_child(child)
        child.queue_free()
    shapes.clear()

func _rig_to_local(p: Vector2) -> Vector2:
    return Vector2((p.x - .5) * texture_size.x * runtime_scale * facing, (p.y - 1.0) * texture_size.y * runtime_scale)

func apply_joint_pose(joints: Dictionary, display_scale: float = -1.0, facing_value: float = 0.0) -> void:
    if display_scale > 0.0:
        runtime_scale = display_scale
    if absf(facing_value) > .001:
        facing = signf(facing_value)
    for entry in shapes:
        var a := str(entry.get("a", ""))
        var b := str(entry.get("b", ""))
        if not joints.has(a) or not joints.has(b):
            continue
        var p0 := _rig_to_local(joints[a])
        var p1 := _rig_to_local(joints[b])
        var delta := p1 - p0
        if delta.length_squared() < 1.0:
            continue
        var node: CollisionShape2D = entry["node"]
        var capsule := node.shape as CapsuleShape2D
        if capsule == null:
            continue
        var radius_px := maxf(1.5, float(entry.get("radius_norm", .04)) * minf(texture_size.x, texture_size.y) * runtime_scale)
        capsule.radius = radius_px
        capsule.height = maxf(radius_px * 2.0, delta.length() + radius_px * 2.0)
        node.position = (p0 + p1) * .5
        node.rotation = delta.angle() - PI * .5

func stats() -> Dictionary:
    return {"capsules": shapes.size(), "backend": "godot_physics2d_capsules_v1"}
