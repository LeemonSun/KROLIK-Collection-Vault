extends SceneTree

## Runtime regression for malformed animation content.  This executes the real
## VaultAnimationDriver and proves invalid clips are isolated rather than
## poisoning a character pose or silently redirecting a state to bad data.

const DriverScript = preload("res://scripts/animation_driver.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String, code: int) -> void:
    push_error("KROLIK animation validation failed: %s" % message)
    quit(code)

func _sample_is_finite(sample: Dictionary) -> bool:
    var offset: Vector2 = sample.get("offset", Vector2.ZERO)
    var scale: Vector2 = sample.get("scale", Vector2.ONE)
    if not (is_finite(offset.x) and is_finite(offset.y) and is_finite(scale.x) and is_finite(scale.y)):
        return false
    if not is_finite(float(sample.get("rotation", 0.0))):
        return false
    var joints: Dictionary = sample.get("joint_offsets", {})
    for value in joints.values():
        var v: Vector2 = value
        if not (is_finite(v.x) and is_finite(v.y)):
            return false
    return true

func _run() -> void:
    var driver := DriverScript.new() as VaultAnimationDriver
    driver.configure({
        "default_clip": "missing_default",
        "state_graph": {
            "idle": {"clip": "good", "blend": 0.05},
            "wander": {"clip": "missing_walk", "blend": 0.12},
            "broken_blend": {"clip": "good", "blend": -4.0},
        },
        "clips": {
            "good": {
                "duration": 1.0,
                "loop": false,
                "keyframes": [
                    {"t": 0.0, "joints": {"head": [0.0, 0.0]}, "root": {"x": 0.0, "scale_x": 1.0}},
                    {"t": 1.0, "joints": {"head": [0.2, -0.1]}, "root": {"x": 10.0, "scale_x": 1.1}},
                ],
            },
            "bad_order": {
                "duration": 1.0,
                "keyframes": [{"t": 0.8}, {"t": 0.2}],
            },
            "bad_duplicate": {
                "duration": 1.0,
                "keyframes": [{"t": 0.2}, {"t": 0.2}],
            },
            "bad_duration": {
                "duration": -1.0,
                "keyframes": [{"t": 0.0}],
            },
            "bad_joint": {
                "duration": 1.0,
                "keyframes": [{"t": 0.0, "joints": {"head": "not-a-vector"}}],
            },
            "bad_root_scale": {
                "duration": 1.0,
                "keyframes": [{"t": 0.0, "root": {"scale_x": 0.0}}],
            },
            "bad_frame": {
                "duration": 1.0,
                "keyframes": ["not-a-frame"],
            },
        },
    })

    var report := driver.validation_report()
    if int(report.get("valid_clip_count", -1)) != 1:
        _fail("expected exactly one valid clip, report=%s" % str(report), 31)
        return
    if driver.current != "good" or str(report.get("default_clip", "")) != "good":
        _fail("missing default did not deterministically fall back to good", 32)
        return
    if driver.clip_for_state("wander") != "good":
        _fail("state referencing missing clip did not use safe default", 33)
        return
    if driver.validation_errors.size() < 6:
        _fail("malformed clips were not all reported: %s" % str(driver.validation_errors), 34)
        return
    if driver.validation_warnings.size() < 3:
        _fail("default/state/blend warnings missing: %s" % str(driver.validation_warnings), 35)
        return

    driver.set_state("idle")
    var half := driver.step(0.5)
    if not _sample_is_finite(half):
        _fail("valid sampled pose contains non-finite values", 36)
        return
    var head: Vector2 = half.get("joint_offsets", {}).get("head", Vector2.ZERO)
    if head.x <= 0.0 or head.x >= 0.2:
        _fail("valid keyframes were not interpolated: head=%s" % str(head), 37)
        return

    # Negative deltas must not rewind/corrupt the animation clock.
    var phase_before := driver.phase
    var after_negative := driver.step(-100.0)
    if absf(driver.phase - phase_before) > 0.000001 or not _sample_is_finite(after_negative):
        _fail("negative delta corrupted phase/sample", 38)
        return

    # A direct request for an invalid clip must remain on the safe data clip.
    driver.set_animation("bad_duration", 0.0)
    if driver.current != "good":
        _fail("invalid direct clip request escaped validation", 39)
        return

    print("KROLIK_ANIMATION_VALIDATION valid_clips=%d errors=%d warnings=%d default=%s head_half=(%.4f,%.4f)" % [
        int(report.get("valid_clip_count", 0)),
        driver.validation_errors.size(),
        driver.validation_warnings.size(),
        driver.current,
        head.x,
        head.y,
    ])
    quit(0)
