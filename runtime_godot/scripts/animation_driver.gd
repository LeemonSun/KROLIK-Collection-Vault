class_name VaultAnimationDriver
extends RefCounted

## Data-driven animation sampler for KROLIK runtime characters.
##
## Clips contain normalized joint offsets relative to the rig rest pose.  The
## driver samples them, performs cross-fades between clips and returns a pose
## that is applied *before* IK constraints.  This is intentionally independent
## from Skeleton2D so the same animation data can later be reused by exporters,
## previews and LOD runtimes.

var current := "idle_breathe"
var phase := 0.0
var speed := 1.0
var clips: Dictionary = {}
var state_graph: Dictionary = {}
var _blend_duration := 0.0
var _blend_elapsed := 0.0
var _blend_from: Dictionary = {}
var _last_sample: Dictionary = {}

func configure(animation_doc: Dictionary) -> void:
    clips = animation_doc.get("clips", {}).duplicate(true)
    state_graph = animation_doc.get("state_graph", {}).duplicate(true)
    if animation_doc.has("default_clip"):
        current = str(animation_doc.get("default_clip", current))
    phase = 0.0
    _blend_duration = 0.0
    _blend_elapsed = 0.0
    _blend_from.clear()
    _last_sample = _empty_sample()

func clip_for_state(state_name: String) -> String:
    var entry = state_graph.get(state_name, {})
    if typeof(entry) == TYPE_DICTIONARY:
        return str(entry.get("clip", "idle_breathe"))
    return "idle_breathe"

func set_state(state_name: String) -> void:
    var entry = state_graph.get(state_name, {})
    var clip_name := clip_for_state(state_name)
    var blend := 0.16
    if typeof(entry) == TYPE_DICTIONARY:
        blend = maxf(0.0, float(entry.get("blend", blend)))
    set_animation(clip_name, blend)

func set_animation(name: String, blend: float = 0.16) -> void:
    if name == current:
        return
    _blend_from = _last_sample.duplicate(true)
    _blend_duration = maxf(0.0, blend)
    _blend_elapsed = 0.0
    current = name
    phase = 0.0

func _empty_sample() -> Dictionary:
    return {
        "offset": Vector2.ZERO,
        "rotation": 0.0,
        "scale": Vector2.ONE,
        "joint_offsets": {},
    }

func _as_vec2(value) -> Vector2:
    if typeof(value) == TYPE_VECTOR2:
        return value
    if typeof(value) == TYPE_ARRAY and value.size() >= 2:
        return Vector2(float(value[0]), float(value[1]))
    if typeof(value) == TYPE_DICTIONARY:
        return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
    return Vector2.ZERO

func _root_from_frame(frame: Dictionary) -> Dictionary:
    var root: Dictionary = frame.get("root", {})
    var sx := float(root.get("scale_x", 1.0))
    var sy := float(root.get("scale_y", sx))
    return {
        "offset": Vector2(float(root.get("x", 0.0)), float(root.get("y", 0.0))),
        "rotation": float(root.get("rotation", 0.0)),
        "scale": Vector2(sx, sy),
    }

func _joint_offsets(frame: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    var source = frame.get("joints", {})
    if typeof(source) != TYPE_DICTIONARY:
        return out
    for name in source.keys():
        out[str(name)] = _as_vec2(source[name])
    return out

func _lerp_samples(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
    t = clampf(t, 0.0, 1.0)
    var out := _empty_sample()
    out["offset"] = (_as_vec2(a.get("offset", Vector2.ZERO))).lerp(_as_vec2(b.get("offset", Vector2.ZERO)), t)
    out["rotation"] = lerpf(float(a.get("rotation", 0.0)), float(b.get("rotation", 0.0)), t)
    out["scale"] = (_as_vec2(a.get("scale", Vector2.ONE))).lerp(_as_vec2(b.get("scale", Vector2.ONE)), t)
    var aj: Dictionary = a.get("joint_offsets", {})
    var bj: Dictionary = b.get("joint_offsets", {})
    var names: Dictionary = {}
    for name in aj.keys(): names[str(name)] = true
    for name in bj.keys(): names[str(name)] = true
    var joints: Dictionary = {}
    for name in names.keys():
        joints[name] = _as_vec2(aj.get(name, Vector2.ZERO)).lerp(_as_vec2(bj.get(name, Vector2.ZERO)), t)
    out["joint_offsets"] = joints
    return out

func _sample_frame(frame: Dictionary) -> Dictionary:
    var out := _root_from_frame(frame)
    out["joint_offsets"] = _joint_offsets(frame)
    return out

func _sample_clip(clip_name: String, time_value: float) -> Dictionary:
    var clip = clips.get(clip_name, {})
    if typeof(clip) != TYPE_DICTIONARY:
        return _legacy_sample(clip_name, time_value)
    var frames = clip.get("keyframes", [])
    if typeof(frames) != TYPE_ARRAY or frames.is_empty():
        return _legacy_sample(clip_name, time_value)
    if frames.size() == 1:
        return _sample_frame(frames[0])
    var duration := maxf(0.001, float(clip.get("duration", 1.0)))
    var loop := bool(clip.get("loop", true))
    var local_time := time_value
    if loop:
        local_time = fmod(maxf(0.0, local_time), duration)
    else:
        local_time = clampf(local_time, 0.0, duration)
    var left: Dictionary = frames[0]
    var right: Dictionary = frames[frames.size() - 1]
    for i in range(frames.size() - 1):
        var f0: Dictionary = frames[i]
        var f1: Dictionary = frames[i + 1]
        var t0 := float(f0.get("t", 0.0))
        var t1 := float(f1.get("t", duration))
        if local_time >= t0 and local_time <= t1:
            left = f0
            right = f1
            break
    var lt := float(left.get("t", 0.0))
    var rt := float(right.get("t", duration))
    var alpha := 0.0 if absf(rt - lt) < 0.00001 else (local_time - lt) / (rt - lt)
    # Smoothstep avoids the mechanical linear look without inventing overshoot.
    alpha = alpha * alpha * (3.0 - 2.0 * alpha)
    return _lerp_samples(_sample_frame(left), _sample_frame(right), alpha)

func _legacy_sample(name: String, time_value: float) -> Dictionary:
    # Compatibility for old packages without animation clips.  New exports use
    # joint keyframes, so this path should gradually disappear.
    var out := _empty_sample()
    match name:
        "walk":
            out.offset.y = sin(time_value * 8.0) * 2.2
            out.rotation = sin(time_value * 4.0) * 0.012
        "inspect":
            out.rotation = sin(time_value * 0.8) * 0.008
        "social_idle":
            out.offset.y = sin(time_value * 1.6) * 1.2
        "contained_idle":
            out.rotation = sin(time_value * 0.7) * 0.006
        "rest":
            out.offset.y = abs(sin(time_value * 1.15)) * 0.8
        "idle_static":
            pass
        _:
            out.offset.y = sin(time_value * 1.4) * 1.0
            out.rotation = sin(time_value * 0.55) * 0.005
    return out

func step(delta: float) -> Dictionary:
    phase += maxf(0.0, delta) * speed
    var sampled := _sample_clip(current, phase)
    if _blend_duration > 0.0 and _blend_elapsed < _blend_duration and not _blend_from.is_empty():
        _blend_elapsed += maxf(0.0, delta)
        sampled = _lerp_samples(_blend_from, sampled, clampf(_blend_elapsed / _blend_duration, 0.0, 1.0))
    _last_sample = sampled.duplicate(true)
    return sampled
