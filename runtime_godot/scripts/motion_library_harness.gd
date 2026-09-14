extends SceneTree

## End-to-end runtime regression for the authored motion library. CI copies the
## repository's content/animations/default_v1.json into the Godot project, so
## this harness exercises the exact external asset through VaultAnimationDriver.

const DriverScript = preload("res://scripts/animation_driver.gd")
const MOTION_PATH := "res://.ci_motion_library.json"
const MIN_CLIPS := 30

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String, code: int) -> void:
    push_error("KROLIK motion library runtime failed: %s" % message)
    quit(code)

func _sample_is_finite(sample: Dictionary) -> bool:
    var offset: Vector2 = sample.get("offset", Vector2.ZERO)
    var scale: Vector2 = sample.get("scale", Vector2.ONE)
    if not (is_finite(offset.x) and is_finite(offset.y)):
        return false
    if not (is_finite(scale.x) and is_finite(scale.y) and scale.x > 0.0 and scale.y > 0.0):
        return false
    if not is_finite(float(sample.get("rotation", 0.0))):
        return false
    var joints = sample.get("joint_offsets", {})
    if typeof(joints) != TYPE_DICTIONARY:
        return false
    for value in joints.values():
        if typeof(value) != TYPE_VECTOR2:
            return false
        var point: Vector2 = value
        if not (is_finite(point.x) and is_finite(point.y)):
            return false
    return true

func _load_document():
    if not FileAccess.file_exists(MOTION_PATH):
        _fail("CI motion library is missing at %s" % MOTION_PATH, 61)
        return null
    var file := FileAccess.open(MOTION_PATH, FileAccess.READ)
    if file == null:
        _fail("cannot read CI motion library", 62)
        return null
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("motion library must parse as a JSON object", 63)
        return null
    return parsed

func _run() -> void:
    var document = _load_document()
    if typeof(document) != TYPE_DICTIONARY:
        return
    if str(document.get("schema", "")) != "krolik.animation-library/1":
        _fail("unexpected animation schema", 64)
        return
    if int(document.get("format_version", 0)) != 1:
        _fail("unexpected animation format version", 65)
        return

    var raw_clips = document.get("clips", {})
    if typeof(raw_clips) != TYPE_DICTIONARY or raw_clips.size() < MIN_CLIPS:
        _fail("expected at least %d clips, got %d" % [MIN_CLIPS, raw_clips.size() if typeof(raw_clips) == TYPE_DICTIONARY else 0], 66)
        return

    var driver := DriverScript.new() as VaultAnimationDriver
    driver.configure(document)
    var report := driver.validation_report()
    if not driver.validation_errors.is_empty():
        _fail("driver rejected authored clips: %s" % str(driver.validation_errors), 67)
        return
    if int(report.get("valid_clip_count", 0)) != raw_clips.size():
        _fail("driver accepted %d/%d clips" % [int(report.get("valid_clip_count", 0)), raw_clips.size()], 68)
        return

    var names := raw_clips.keys()
    names.sort()
    var samples := 0
    for raw_name in names:
        var clip_name := str(raw_name)
        var clip = raw_clips[raw_name]
        if typeof(clip) != TYPE_DICTIONARY:
            _fail("clip %s is not a dictionary" % clip_name, 69)
            return
        var duration := float(clip.get("duration", 1.0))
        driver.set_animation(clip_name, 0.0)
        if driver.current != clip_name:
            _fail("driver could not select clip %s" % clip_name, 70)
            return
        var deltas := [0.0, duration * 0.23, duration * 0.27, duration * 0.31]
        for delta in deltas:
            var sample := driver.step(float(delta))
            samples += 1
            if not _sample_is_finite(sample):
                _fail("clip %s emitted a non-finite/invalid sample at phase %.5f" % [clip_name, driver.phase], 71)
                return

    var raw_graph = document.get("state_graph", {})
    var state_count := 0
    if typeof(raw_graph) == TYPE_DICTIONARY:
        var states := raw_graph.keys()
        states.sort()
        for raw_state in states:
            var state_name := str(raw_state)
            var entry = raw_graph[raw_state]
            if typeof(entry) != TYPE_DICTIONARY:
                _fail("state %s is not a dictionary" % state_name, 72)
                return
            var expected := str(entry.get("clip", ""))
            driver.set_state(state_name)
            if driver.current != expected:
                _fail("state %s resolved to %s instead of %s" % [state_name, driver.current, expected], 73)
                return
            if not _sample_is_finite(driver.step(0.016)):
                _fail("state %s emitted an invalid sample" % state_name, 74)
                return
            state_count += 1

    print("KROLIK_MOTION_RUNTIME clips=%d states=%d samples=%d validation_errors=%d validation_warnings=%d" % [
        raw_clips.size(),
        state_count,
        samples,
        driver.validation_errors.size(),
        driver.validation_warnings.size(),
    ])
    quit(0)
