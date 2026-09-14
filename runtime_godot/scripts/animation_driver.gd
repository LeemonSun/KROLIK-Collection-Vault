class_name VaultAnimationDriver
extends RefCounted

## Data-driven animation sampler for KROLIK runtime characters.
##
## Clips contain normalized joint offsets relative to the rig rest pose. The
## driver samples them, performs cross-fades between clips and returns a pose
## that is applied *before* IK constraints. Runtime-only additive layers can be
## masked to selected joints so gestures/reactions can ride on top of locomotion
## without changing the versioned animation-v1 content contract. Invalid
## authoring data is rejected clip-by-clip so one malformed content pack cannot
## poison the runtime pose.

var current := "idle_breathe"
var phase := 0.0
var speed := 1.0
var clips: Dictionary = {}
var state_graph: Dictionary = {}
var layers: Dictionary = {}
var validation_errors: Array[String] = []
var validation_warnings: Array[String] = []
var _default_clip := "idle_breathe"
var _blend_duration := 0.0
var _blend_elapsed := 0.0
var _blend_from: Dictionary = {}
var _last_sample: Dictionary = {}

func configure(animation_doc: Dictionary) -> void:
    validation_errors.clear()
    validation_warnings.clear()
    clips.clear()
    state_graph.clear()
    layers.clear()

    var raw_clips = animation_doc.get("clips", {})
    if typeof(raw_clips) != TYPE_DICTIONARY:
        validation_errors.append("animation.clips must be a dictionary")
    else:
        for raw_name in raw_clips.keys():
            var clip_name := str(raw_name)
            if clip_name.is_empty():
                validation_errors.append("animation clip name must not be empty")
                continue
            var clip = raw_clips[raw_name]
            var clip_errors := _validate_clip(clip_name, clip)
            if clip_errors.is_empty():
                clips[clip_name] = clip.duplicate(true)
            else:
                validation_errors.append_array(clip_errors)

    var raw_graph = animation_doc.get("state_graph", {})
    if typeof(raw_graph) == TYPE_DICTIONARY:
        state_graph = raw_graph.duplicate(true)
    else:
        validation_errors.append("animation.state_graph must be a dictionary")

    var requested_default := str(animation_doc.get("default_clip", "idle_breathe"))
    _default_clip = _select_default_clip(requested_default)
    current = _default_clip
    _validate_state_graph()

    phase = 0.0
    _blend_duration = 0.0
    _blend_elapsed = 0.0
    _blend_from.clear()
    _last_sample = _empty_sample()

func validation_report() -> Dictionary:
    return {
        "valid_clip_count": clips.size(),
        "default_clip": _default_clip,
        "active_layer_count": layers.size(),
        "errors": validation_errors.duplicate(),
        "warnings": validation_warnings.duplicate(),
    }

func _select_default_clip(requested: String) -> String:
    if clips.has(requested):
        return requested
    if not requested.is_empty():
        validation_warnings.append("default clip '%s' is missing or invalid" % requested)
    if clips.has("idle_breathe"):
        return "idle_breathe"
    if not clips.is_empty():
        var names := clips.keys()
        names.sort()
        return str(names[0])
    # Old packages intentionally have no clip dictionary and use procedural
    # legacy sampling. Keep that compatibility path deterministic.
    validation_warnings.append("no valid data clips; using legacy idle_breathe sampler")
    return "idle_breathe"

func _finite_number(value) -> bool:
    var kind := typeof(value)
    if kind != TYPE_INT and kind != TYPE_FLOAT:
        return false
    return is_finite(float(value))

func _valid_vec2_value(value) -> bool:
    if typeof(value) == TYPE_VECTOR2:
        return is_finite(value.x) and is_finite(value.y)
    if typeof(value) == TYPE_ARRAY:
        return value.size() >= 2 and _finite_number(value[0]) and _finite_number(value[1])
    if typeof(value) == TYPE_DICTIONARY:
        return _finite_number(value.get("x", 0.0)) and _finite_number(value.get("y", 0.0))
    return false

func _validate_root(clip_name: String, index: int, root) -> Array[String]:
    var errors: Array[String] = []
    if root == null:
        return errors
    if typeof(root) != TYPE_DICTIONARY:
        errors.append("clip '%s' keyframe %d root must be a dictionary" % [clip_name, index])
        return errors
    for key in ["x", "y", "rotation", "scale_x", "scale_y"]:
        if root.has(key) and not _finite_number(root[key]):
            errors.append("clip '%s' keyframe %d root.%s must be finite numeric" % [clip_name, index, key])
    for key in ["scale_x", "scale_y"]:
        if root.has(key) and _finite_number(root[key]) and float(root[key]) <= 0.0:
            errors.append("clip '%s' keyframe %d root.%s must be > 0" % [clip_name, index, key])
    return errors

func _validate_joints(clip_name: String, index: int, joints) -> Array[String]:
    var errors: Array[String] = []
    if joints == null:
        return errors
    if typeof(joints) != TYPE_DICTIONARY:
        errors.append("clip '%s' keyframe %d joints must be a dictionary" % [clip_name, index])
        return errors
    for raw_name in joints.keys():
        var joint_name := str(raw_name)
        if joint_name.is_empty():
            errors.append("clip '%s' keyframe %d has an empty joint name" % [clip_name, index])
            continue
        if not _valid_vec2_value(joints[raw_name]):
            errors.append("clip '%s' keyframe %d joint '%s' must be a finite vec2" % [clip_name, index, joint_name])
    return errors

func _validate_clip(clip_name: String, clip) -> Array[String]:
    var errors: Array[String] = []
    if typeof(clip) != TYPE_DICTIONARY:
        errors.append("clip '%s' must be a dictionary" % clip_name)
        return errors

    var duration_value = clip.get("duration", 1.0)
    if not _finite_number(duration_value) or float(duration_value) <= 0.0:
        errors.append("clip '%s' duration must be finite and > 0" % clip_name)
        return errors
    var duration := float(duration_value)

    var frames = clip.get("keyframes", [])
    if typeof(frames) != TYPE_ARRAY or frames.is_empty():
        errors.append("clip '%s' must contain at least one keyframe" % clip_name)
        return errors

    var previous_t := -1.0
    for index in range(frames.size()):
        var frame = frames[index]
        if typeof(frame) != TYPE_DICTIONARY:
            errors.append("clip '%s' keyframe %d must be a dictionary" % [clip_name, index])
            continue
        var t_value = frame.get("t", null)
        if not _finite_number(t_value):
            errors.append("clip '%s' keyframe %d timestamp must be finite numeric" % [clip_name, index])
            continue
        var timestamp := float(t_value)
        if timestamp < 0.0 or timestamp > duration + 0.00001:
            errors.append("clip '%s' keyframe %d timestamp %.5f is outside [0, %.5f]" % [clip_name, index, timestamp, duration])
        if index > 0 and timestamp <= previous_t + 0.000001:
            errors.append("clip '%s' keyframe timestamps must be strictly increasing" % clip_name)
        previous_t = timestamp
        errors.append_array(_validate_root(clip_name, index, frame.get("root", {})))
        errors.append_array(_validate_joints(clip_name, index, frame.get("joints", {})))
    return errors

func _validate_state_graph() -> void:
    for raw_state in state_graph.keys():
        var state_name := str(raw_state)
        var entry = state_graph[raw_state]
        if typeof(entry) != TYPE_DICTIONARY:
            validation_warnings.append("state '%s' entry is not a dictionary; default clip will be used" % state_name)
            continue
        var candidate := str(entry.get("clip", _default_clip))
        if not clips.is_empty() and not clips.has(candidate):
            validation_warnings.append("state '%s' references missing/invalid clip '%s'; default clip will be used" % [state_name, candidate])
        if entry.has("blend"):
            var blend_value = entry["blend"]
            if not _finite_number(blend_value) or float(blend_value) < 0.0:
                validation_warnings.append("state '%s' has invalid blend; 0.16 will be used" % state_name)

func clip_for_state(state_name: String) -> String:
    var entry = state_graph.get(state_name, {})
    if typeof(entry) == TYPE_DICTIONARY:
        var candidate := str(entry.get("clip", _default_clip))
        if clips.is_empty() or clips.has(candidate):
            return candidate
    return _default_clip

func set_state(state_name: String) -> void:
    var entry = state_graph.get(state_name, {})
    var clip_name := clip_for_state(state_name)
    var blend := 0.16
    if typeof(entry) == TYPE_DICTIONARY and _finite_number(entry.get("blend", blend)):
        blend = maxf(0.0, float(entry.get("blend", blend)))
    set_animation(clip_name, blend)

func set_animation(name: String, blend: float = 0.16) -> void:
    var safe_name := name
    if not clips.is_empty() and not clips.has(safe_name):
        safe_name = _default_clip
    if safe_name == current:
        return
    _blend_from = _last_sample.duplicate(true)
    _blend_duration = maxf(0.0, blend) if is_finite(blend) else 0.0
    _blend_elapsed = 0.0
    current = safe_name
    phase = 0.0

func set_additive_layer(
    layer_name: String,
    clip_name: String,
    weight: float = 1.0,
    joint_mask: Array = [],
    root_weight: float = 0.0,
    playback_speed: float = 1.0,
    restart: bool = true
) -> bool:
    if layer_name.is_empty() or clip_name.is_empty():
        return false
    if not clips.is_empty() and not clips.has(clip_name):
        return false

    var mask: Dictionary = {}
    for raw_name in joint_mask:
        var joint_name := str(raw_name)
        if not joint_name.is_empty():
            mask[joint_name] = true

    var previous = layers.get(layer_name, {})
    var layer_phase := 0.0
    if not restart and typeof(previous) == TYPE_DICTIONARY and str(previous.get("clip", "")) == clip_name:
        var previous_phase = previous.get("phase", 0.0)
        if _finite_number(previous_phase):
            layer_phase = maxf(0.0, float(previous_phase))

    var safe_weight := clampf(weight if is_finite(weight) else 0.0, 0.0, 1.0)
    var safe_root_weight := clampf(root_weight if is_finite(root_weight) else 0.0, 0.0, 1.0)
    var safe_speed := maxf(0.0, playback_speed if is_finite(playback_speed) else 1.0)
    layers[layer_name] = {
        "clip": clip_name,
        "phase": layer_phase,
        "speed": safe_speed,
        "weight": safe_weight,
        "root_weight": safe_root_weight,
        "joint_mask": mask,
    }
    return true

func set_additive_layer_weight(layer_name: String, weight: float) -> bool:
    var value = layers.get(layer_name, null)
    if typeof(value) != TYPE_DICTIONARY:
        return false
    var layer: Dictionary = value
    layer["weight"] = clampf(weight if is_finite(weight) else 0.0, 0.0, 1.0)
    layers[layer_name] = layer
    return true

func clear_additive_layer(layer_name: String) -> bool:
    return layers.erase(layer_name)

func clear_additive_layers() -> void:
    layers.clear()

func active_layer_names() -> Array[String]:
    var out: Array[String] = []
    var names: Array = layers.keys()
    names.sort()
    for raw_name in names:
        out.append(str(raw_name))
    return out

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

func _apply_additive_layer(base: Dictionary, overlay: Dictionary, layer: Dictionary) -> Dictionary:
    var out: Dictionary = base.duplicate(true)
    var weight_value = layer.get("weight", 0.0)
    var weight := clampf(float(weight_value), 0.0, 1.0) if _finite_number(weight_value) else 0.0
    if weight <= 0.0:
        return out

    var root_weight_value = layer.get("root_weight", 0.0)
    var root_weight := clampf(float(root_weight_value), 0.0, 1.0) if _finite_number(root_weight_value) else 0.0
    var root_mix := weight * root_weight
    if root_mix > 0.0:
        out["offset"] = _as_vec2(base.get("offset", Vector2.ZERO)) + _as_vec2(overlay.get("offset", Vector2.ZERO)) * root_mix
        out["rotation"] = float(base.get("rotation", 0.0)) + float(overlay.get("rotation", 0.0)) * root_mix
        var base_scale := _as_vec2(base.get("scale", Vector2.ONE))
        var overlay_scale := _as_vec2(overlay.get("scale", Vector2.ONE))
        var scale_delta := Vector2(
            lerpf(1.0, overlay_scale.x, root_mix),
            lerpf(1.0, overlay_scale.y, root_mix)
        )
        out["scale"] = base_scale * scale_delta

    var base_joints = base.get("joint_offsets", {})
    var overlay_joints = overlay.get("joint_offsets", {})
    var joints: Dictionary = base_joints.duplicate(true) if typeof(base_joints) == TYPE_DICTIONARY else {}
    if typeof(overlay_joints) != TYPE_DICTIONARY:
        out["joint_offsets"] = joints
        return out
    var mask = layer.get("joint_mask", {})
    var mask_enabled := typeof(mask) == TYPE_DICTIONARY and not mask.is_empty()
    for raw_name in overlay_joints.keys():
        var joint_name := str(raw_name)
        if mask_enabled and not mask.has(joint_name):
            continue
        joints[joint_name] = _as_vec2(joints.get(joint_name, Vector2.ZERO)) + _as_vec2(overlay_joints[raw_name]) * weight
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
    # Compatibility for old packages without animation clips. New exports use
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
    var safe_delta := delta if is_finite(delta) and delta >= 0.0 else 0.0
    var safe_speed := speed if is_finite(speed) and speed >= 0.0 else 0.0
    phase += safe_delta * safe_speed
    var sampled := _sample_clip(current, phase)
    if _blend_duration > 0.0 and _blend_elapsed < _blend_duration and not _blend_from.is_empty():
        _blend_elapsed += safe_delta
        sampled = _lerp_samples(_blend_from, sampled, clampf(_blend_elapsed / _blend_duration, 0.0, 1.0))

    # Keep the pre-layer sample for base-clip cross-fades. Otherwise changing
    # locomotion while a gesture layer is active would bake the layer into the
    # blend source and apply it twice on the next frame.
    _last_sample = sampled.duplicate(true)

    var output: Dictionary = sampled
    var layer_names: Array = layers.keys()
    layer_names.sort()
    for raw_layer_name in layer_names:
        var value = layers.get(raw_layer_name, null)
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var layer: Dictionary = value
        var layer_speed_value = layer.get("speed", 1.0)
        var layer_speed := maxf(0.0, float(layer_speed_value)) if _finite_number(layer_speed_value) else 1.0
        var layer_phase_value = layer.get("phase", 0.0)
        var layer_phase := maxf(0.0, float(layer_phase_value)) if _finite_number(layer_phase_value) else 0.0
        layer_phase += safe_delta * layer_speed
        layer["phase"] = layer_phase
        layers[raw_layer_name] = layer
        var overlay := _sample_clip(str(layer.get("clip", "")), layer_phase)
        output = _apply_additive_layer(output, overlay, layer)
    return output
