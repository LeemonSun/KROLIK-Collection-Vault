class_name VaultSecondaryMotion
extends RefCounted

## Lightweight secondary-motion solver for runtime characters.
##
## This is deliberately a small spring system, not a cloth simulator.  It adds
## inertial lag to existing rig joints before IK constraints are solved.  When
## semantic hair/accessory bones are exported later, the same channel data can
## drive those bones without changing the manifest format.

var config: Dictionary = {}
var _state: Dictionary = {}
var _previous_velocity := Vector2.ZERO
var _initialized := false

func configure(doc: Dictionary) -> void:
    config = doc.duplicate(true)
    _state.clear()
    _previous_velocity = Vector2.ZERO
    _initialized = false

func reset() -> void:
    _state.clear()
    _previous_velocity = Vector2.ZERO
    _initialized = false

func _max_offset(channel: String, params: Dictionary) -> float:
    if params.has("max_offset"):
        return clampf(float(params.get("max_offset", 0.01)), 0.0, 0.05)
    # Angle-based channels (hair/accessories) are converted to a conservative
    # normalized positional lag until dedicated semantic chains are available.
    var angle := clampf(float(params.get("max_angle", 12.0)), 0.0, 45.0)
    return lerpf(0.004, 0.022, angle / 45.0)

func _step_spring(channel: String, target: Vector2, params: Dictionary, delta: float) -> Vector2:
    var state: Dictionary = _state.get(channel, {"offset": Vector2.ZERO, "velocity": Vector2.ZERO})
    var offset: Vector2 = state.get("offset", Vector2.ZERO)
    var velocity: Vector2 = state.get("velocity", Vector2.ZERO)
    var stiffness := clampf(float(params.get("stiffness", 0.4)), 0.0, 1.0)
    var damping := clampf(float(params.get("damping", 0.75)), 0.0, 1.0)
    # Convert user-friendly 0..1 values to stable spring coefficients.
    var omega := lerpf(7.0, 17.0, stiffness)
    var damp := lerpf(5.0, 15.0, damping)
    var dt := minf(maxf(delta, 0.0), 1.0 / 20.0)
    var accel := (target - offset) * (omega * omega) - velocity * damp
    velocity += accel * dt
    offset += velocity * dt
    var limit := _max_offset(channel, params)
    offset.x = clampf(offset.x, -limit, limit)
    offset.y = clampf(offset.y, -limit, limit)
    state["offset"] = offset
    state["velocity"] = velocity
    _state[channel] = state
    return offset

func step(delta: float, world_velocity: Vector2) -> Dictionary:
    var dt := maxf(delta, 0.0001)
    if not _initialized:
        _previous_velocity = world_velocity
        _initialized = true
    var world_accel := (world_velocity - _previous_velocity) / dt
    _previous_velocity = world_velocity

    # Normalize against runtime movement scales.  Values are clamped so a
    # collision impulse cannot explode the puppet pose.
    var inertia := Vector2(
        clampf(world_accel.x / 900.0, -1.0, 1.0),
        clampf(world_accel.y / 900.0, -1.0, 1.0)
    )
    var drift := Vector2(
        clampf(world_velocity.x / 140.0, -1.0, 1.0),
        clampf(world_velocity.y / 140.0, -1.0, 1.0)
    )

    var out: Dictionary = {}
    for channel_name in config.keys():
        var channel := str(channel_name)
        var params = config[channel_name]
        if typeof(params) != TYPE_DICTIONARY:
            continue
        var p: Dictionary = params
        var limit := _max_offset(channel, p)
        var target := Vector2.ZERO
        match channel:
            "hair":
                target = Vector2(-inertia.x - drift.x * 0.18, -inertia.y * 0.25) * limit
            "chest":
                target = Vector2(-inertia.x * 0.28, -inertia.y * 0.45) * limit
            "hips":
                target = Vector2(-inertia.x * 0.42, -inertia.y * 0.20) * limit
            "accessories":
                target = Vector2(-inertia.x - drift.x * 0.25, -inertia.y * 0.35) * limit
            _:
                target = Vector2(-inertia.x * 0.35, -inertia.y * 0.20) * limit
        out[channel] = _step_spring(channel, target, p, delta)
    return out

func joint_offsets(channel_offsets: Dictionary) -> Dictionary:
    ## Map generic secondary channels onto the current base rig.  Dedicated
    ## semantic chains can replace these mappings later without touching agents.
    var out: Dictionary = {}
    var add := func(name: String, value: Vector2) -> void:
        out[name] = out.get(name, Vector2.ZERO) + value

    if channel_offsets.has("hair"):
        var h: Vector2 = channel_offsets["hair"]
        add.call("head", h)
        add.call("neck", h * 0.35)
    if channel_offsets.has("chest"):
        var c: Vector2 = channel_offsets["chest"]
        add.call("left_shoulder", c)
        add.call("right_shoulder", c)
        add.call("neck", c * 0.25)
    if channel_offsets.has("hips"):
        var hip: Vector2 = channel_offsets["hips"]
        add.call("pelvis", hip)
        add.call("left_hip", hip * 0.75)
        add.call("right_hip", hip * 0.75)
    if channel_offsets.has("accessories"):
        var a: Vector2 = channel_offsets["accessories"]
        add.call("left_wrist", a)
        add.call("right_wrist", a)
    return out
