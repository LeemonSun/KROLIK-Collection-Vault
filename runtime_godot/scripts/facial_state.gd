class_name VaultFacialState
extends RefCounted

## Semantic face/mood controller for the current cutout-based runtime.
##
## The existing rig can honestly render head/neck posture, but it does not yet
## have separate eyelid/mouth geometry. Blink, gaze and expression values are
## therefore exposed as semantic channels for a future face mesh/sprite layer,
## while bounded head/neck offsets are applied to the real skeletal pose now.

var enabled := false
var blink_enabled := false
var look_enabled := false
var blink_min_interval := 2.1
var blink_max_interval := 6.4
var blink_duration := 0.12
var max_head_deg := 16.0
var max_eye := 0.06

var look_target := Vector2.ZERO
var look_current := Vector2.ZERO
var look_response := 8.0

var mood_name := "neutral"
var mood_intensity := 0.0
var _mood_current: Dictionary = {}
var _mood_target: Dictionary = {}
var _mood_transition := 0.20

var _clock := 0.0
var _next_blink := INF
var _blink_start := -1.0
var _blink_index := 0
var _seed_phase := 0.0

const MOOD_KEYS := ["eye_open", "brow", "mouth_curve", "mouth_open", "head_x", "head_y"]

func _neutral_preset() -> Dictionary:
    return {
        "eye_open": 1.0,
        "brow": 0.0,
        "mouth_curve": 0.0,
        "mouth_open": 0.0,
        "head_x": 0.0,
        "head_y": 0.0,
    }

func _preset(name: String):
    match name:
        "neutral":
            return _neutral_preset()
        "calm":
            return {"eye_open": 0.92, "brow": 0.02, "mouth_curve": 0.08, "mouth_open": 0.0, "head_x": 0.0, "head_y": 0.002}
        "alert":
            return {"eye_open": 1.0, "brow": 0.20, "mouth_curve": 0.0, "mouth_open": 0.04, "head_x": 0.0, "head_y": -0.006}
        "happy":
            return {"eye_open": 0.90, "brow": 0.10, "mouth_curve": 0.55, "mouth_open": 0.03, "head_x": 0.0, "head_y": -0.002}
        "sad":
            return {"eye_open": 0.78, "brow": -0.22, "mouth_curve": -0.45, "mouth_open": 0.01, "head_x": -0.002, "head_y": 0.008}
        "angry":
            return {"eye_open": 0.74, "brow": -0.48, "mouth_curve": -0.28, "mouth_open": 0.02, "head_x": 0.0, "head_y": -0.004}
        "afraid":
            return {"eye_open": 1.0, "brow": 0.50, "mouth_curve": -0.25, "mouth_open": 0.18, "head_x": 0.0, "head_y": -0.008}
        "uneasy":
            return {"eye_open": 0.88, "brow": 0.20, "mouth_curve": -0.18, "mouth_open": 0.03, "head_x": 0.002, "head_y": 0.006}
        "seeking_company":
            return {"eye_open": 0.94, "brow": 0.12, "mouth_curve": 0.10, "mouth_open": 0.02, "head_x": 0.0, "head_y": -0.002}
        "terrified":
            return {"eye_open": 1.0, "brow": 0.72, "mouth_curve": -0.40, "mouth_open": 0.34, "head_x": 0.0, "head_y": -0.014}
        "furious":
            return {"eye_open": 0.70, "brow": -0.72, "mouth_curve": -0.48, "mouth_open": 0.12, "head_x": 0.0, "head_y": -0.008}
        "ashamed":
            return {"eye_open": 0.68, "brow": -0.08, "mouth_curve": -0.22, "mouth_open": 0.01, "head_x": -0.008, "head_y": 0.016}
        "frustrated":
            return {"eye_open": 0.80, "brow": -0.40, "mouth_curve": -0.24, "mouth_open": 0.05, "head_x": 0.005, "head_y": -0.002}
        "hopeful":
            return {"eye_open": 0.96, "brow": 0.20, "mouth_curve": 0.22, "mouth_open": 0.02, "head_x": 0.0, "head_y": -0.006}
        "relieved":
            return {"eye_open": 0.72, "brow": 0.05, "mouth_curve": 0.24, "mouth_open": 0.03, "head_x": 0.0, "head_y": 0.008}
        "content":
            return {"eye_open": 0.82, "brow": 0.04, "mouth_curve": 0.30, "mouth_open": 0.0, "head_x": 0.0, "head_y": 0.004}
        "curious":
            return {"eye_open": 0.98, "brow": 0.28, "mouth_curve": 0.04, "mouth_open": 0.02, "head_x": 0.008, "head_y": -0.006}
        "lonely":
            return {"eye_open": 0.76, "brow": -0.16, "mouth_curve": -0.32, "mouth_open": 0.01, "head_x": -0.004, "head_y": 0.012}
        "anxious":
            return {"eye_open": 0.98, "brow": 0.38, "mouth_curve": -0.20, "mouth_open": 0.08, "head_x": 0.004, "head_y": -0.006}
        "determined":
            return {"eye_open": 0.84, "brow": -0.28, "mouth_curve": -0.04, "mouth_open": 0.0, "head_x": 0.0, "head_y": -0.006}
        "defiant":
            return {"eye_open": 0.88, "brow": -0.34, "mouth_curve": 0.10, "mouth_open": 0.0, "head_x": 0.006, "head_y": -0.008}
        "resigned":
            return {"eye_open": 0.64, "brow": -0.10, "mouth_curve": -0.18, "mouth_open": 0.01, "head_x": -0.004, "head_y": 0.018}
        "tired":
            return {"eye_open": 0.62, "brow": -0.12, "mouth_curve": -0.08, "mouth_open": 0.02, "head_x": 0.003, "head_y": 0.012}
        _:
            return null

func configure(animation_doc: Dictionary, seed: int = 1) -> void:
    var blink_doc = animation_doc.get("procedural_blink", {})
    var look_doc = animation_doc.get("look_at", {})

    blink_enabled = typeof(blink_doc) == TYPE_DICTIONARY and bool(blink_doc.get("enabled", false))
    look_enabled = typeof(look_doc) == TYPE_DICTIONARY and bool(look_doc.get("enabled", false))

    if typeof(blink_doc) == TYPE_DICTIONARY:
        blink_min_interval = clampf(float(blink_doc.get("min_interval", 2.1)), 0.2, 60.0)
        blink_max_interval = clampf(float(blink_doc.get("max_interval", 6.4)), blink_min_interval, 120.0)
        blink_duration = clampf(float(blink_doc.get("duration", 0.12)), 0.04, 1.0)
    else:
        blink_min_interval = 2.1
        blink_max_interval = 6.4
        blink_duration = 0.12

    if typeof(look_doc) == TYPE_DICTIONARY:
        max_head_deg = clampf(float(look_doc.get("max_head_deg", 16.0)), 0.0, 45.0)
        max_eye = clampf(float(look_doc.get("max_eye", 0.06)), 0.0, 0.20)
    else:
        max_head_deg = 16.0
        max_eye = 0.06

    _seed_phase = float(absi(seed % 10007)) / 10007.0
    _clock = 0.0
    _blink_index = 0
    _blink_start = -1.0
    _next_blink = _interval_for_index(_blink_index) if blink_enabled else INF
    look_target = Vector2.ZERO
    look_current = Vector2.ZERO
    mood_name = "neutral"
    mood_intensity = 0.0
    _mood_current = _neutral_preset()
    _mood_target = _neutral_preset()
    _mood_transition = 0.20
    enabled = blink_enabled or look_enabled

func set_look_target(normalized_target: Vector2) -> void:
    look_target = Vector2(
        clampf(normalized_target.x, -1.0, 1.0),
        clampf(normalized_target.y, -1.0, 1.0)
    )
    enabled = enabled or look_enabled

func clear_look_target() -> void:
    look_target = Vector2.ZERO

func set_mood(name: String, intensity: float = 1.0, transition: float = 0.20) -> bool:
    var preset = _preset(name)
    if typeof(preset) != TYPE_DICTIONARY:
        return false
    var safe_intensity := clampf(intensity if is_finite(intensity) else 0.0, 0.0, 1.0)
    var neutral := _neutral_preset()
    var target: Dictionary = {}
    for key in MOOD_KEYS:
        target[key] = lerpf(float(neutral[key]), float(preset[key]), safe_intensity)
    _mood_target = target
    mood_name = name
    mood_intensity = safe_intensity
    _mood_transition = clampf(transition if is_finite(transition) else 0.20, 0.0, 10.0)
    enabled = true
    return true

func _interval_for_index(index: int) -> float:
    # Golden-ratio progression gives deterministic non-repeating-looking blink
    # spacing without allocating/using RNG state per character.
    var unit := fmod(_seed_phase + 0.271828 + float(index) * 0.61803398875, 1.0)
    if unit < 0.0:
        unit += 1.0
    return lerpf(blink_min_interval, blink_max_interval, unit)

func _blink_amount() -> float:
    if not blink_enabled or _blink_start < 0.0:
        return 0.0
    var p := (_clock - _blink_start) / maxf(blink_duration, 0.0001)
    if p >= 1.0:
        _blink_start = -1.0
        return 0.0
    return sin(PI * clampf(p, 0.0, 1.0))

func _step_blink() -> float:
    if not blink_enabled:
        return 0.0
    if _blink_start < 0.0 and _clock >= _next_blink:
        _blink_start = _clock
        _blink_index += 1
        _next_blink = _clock + blink_duration + _interval_for_index(_blink_index)
    return _blink_amount()

func _step_look(delta: float) -> void:
    var target := look_target if look_enabled else Vector2.ZERO
    if delta <= 0.0:
        return
    var alpha := 1.0 - exp(-look_response * delta)
    look_current = look_current.lerp(target, clampf(alpha, 0.0, 1.0))
    look_current.x = clampf(look_current.x, -1.0, 1.0)
    look_current.y = clampf(look_current.y, -1.0, 1.0)

func _step_mood(delta: float) -> void:
    if _mood_current.is_empty():
        _mood_current = _neutral_preset()
    if _mood_target.is_empty():
        _mood_target = _neutral_preset()
    if _mood_transition <= 0.0001:
        _mood_current = _mood_target.duplicate(true)
        return
    if delta <= 0.0:
        return
    var alpha := 1.0 - exp(-4.0 * delta / _mood_transition)
    alpha = clampf(alpha, 0.0, 1.0)
    for key in MOOD_KEYS:
        _mood_current[key] = lerpf(float(_mood_current.get(key, 0.0)), float(_mood_target.get(key, 0.0)), alpha)

func semantic_snapshot() -> Dictionary:
    var blink := _blink_amount()
    var eye_open := clampf(float(_mood_current.get("eye_open", 1.0)) * (1.0 - blink), 0.0, 1.0)
    return {
        "mood": mood_name,
        "mood_intensity": mood_intensity,
        "blink": clampf(blink, 0.0, 1.0),
        "eye_openness": eye_open,
        "gaze": look_current * max_eye,
        "brow": clampf(float(_mood_current.get("brow", 0.0)), -1.0, 1.0),
        "mouth_curve": clampf(float(_mood_current.get("mouth_curve", 0.0)), -1.0, 1.0),
        "mouth_open": clampf(float(_mood_current.get("mouth_open", 0.0)), 0.0, 1.0),
        "head_yaw_deg": look_current.x * max_head_deg,
        "head_pitch_deg": look_current.y * max_head_deg * 0.65,
    }

func step(delta: float) -> Dictionary:
    var safe_delta := delta if is_finite(delta) and delta >= 0.0 else 0.0
    if not enabled:
        return {"joint_offsets": {}, "channels": semantic_snapshot()}

    _clock += safe_delta
    var blink := _step_blink()
    _step_look(safe_delta)
    _step_mood(safe_delta)

    var head_scale := clampf(max_head_deg / 16.0, 0.0, 2.8)
    var head_offset := Vector2(
        look_current.x * 0.018 * head_scale + float(_mood_current.get("head_x", 0.0)),
        look_current.y * 0.010 * head_scale + float(_mood_current.get("head_y", 0.0))
    )
    var neck_offset := head_offset * 0.35

    var channels := semantic_snapshot()
    channels["blink"] = clampf(blink, 0.0, 1.0)
    channels["eye_openness"] = clampf(float(_mood_current.get("eye_open", 1.0)) * (1.0 - blink), 0.0, 1.0)
    return {
        "joint_offsets": {
            "head": head_offset,
            "neck": neck_offset,
        },
        "channels": channels,
    }
