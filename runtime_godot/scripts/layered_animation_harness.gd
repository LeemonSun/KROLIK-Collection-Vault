extends SceneTree

## C3 end-to-end regression for runtime additive animation layers. It verifies
## that a masked upper-body overlay can ride on a base locomotion pose without
## disturbing excluded joints or the root unless explicitly requested.

const DriverScript = preload("res://scripts/animation_driver.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String, code: int) -> void:
    push_error("KROLIK layered animation regression failed: %s" % message)
    quit(code)

func _near(a: float, b: float, tolerance := 0.0005) -> bool:
    return absf(a - b) <= tolerance

func _near_vec(a: Vector2, b: Vector2, tolerance := 0.0005) -> bool:
    return a.distance_to(b) <= tolerance

func _joint(sample: Dictionary, name: String) -> Vector2:
    var joints = sample.get("joint_offsets", {})
    if typeof(joints) != TYPE_DICTIONARY:
        return Vector2.INF
    var value = joints.get(name, Vector2.ZERO)
    return value if typeof(value) == TYPE_VECTOR2 else Vector2.INF

func _document() -> Dictionary:
    return {
        "default_clip": "base_walk",
        "state_graph": {
            "wander": {"clip": "base_walk", "blend": 0.0},
        },
        "clips": {
            "base_walk": {
                "duration": 1.0,
                "loop": true,
                "keyframes": [{
                    "t": 0.0,
                    "joints": {
                        "left_wrist": [0.10, 0.0],
                        "left_ankle": [0.20, 0.0],
                    },
                    "root": {"y": 1.0, "rotation": 0.10},
                }],
            },
            "base_walk_alt": {
                "duration": 1.0,
                "loop": true,
                "keyframes": [{
                    "t": 0.0,
                    "joints": {
                        "left_wrist": [-0.10, 0.0],
                        "left_ankle": [0.30, 0.0],
                    },
                    "root": {"y": 2.0, "rotation": -0.05},
                }],
            },
            "upper_gesture": {
                "duration": 1.0,
                "loop": true,
                "keyframes": [{
                    "t": 0.0,
                    "joints": {
                        "left_wrist": [0.40, 0.20],
                        "head": [0.20, -0.10],
                        "left_ankle": [9.0, 9.0],
                    },
                    "root": {"y": 4.0, "rotation": 0.20, "scale_x": 1.20, "scale_y": 1.20},
                }],
            },
        },
    }

func _run() -> void:
    var driver := DriverScript.new() as VaultAnimationDriver
    driver.configure(_document())
    if not driver.validation_errors.is_empty():
        _fail("test document rejected: %s" % str(driver.validation_errors), 91)
        return

    var base := driver.step(0.0)
    if not _near_vec(_joint(base, "left_wrist"), Vector2(0.10, 0.0)):
        _fail("unexpected base wrist", 92)
        return
    if not _near_vec(_joint(base, "left_ankle"), Vector2(0.20, 0.0)):
        _fail("unexpected base ankle", 93)
        return

    if not driver.set_additive_layer(
        "gesture", "upper_gesture", 0.5,
        ["left_wrist", "head"], 0.0, 1.0, true
    ):
        _fail("valid additive layer was rejected", 94)
        return
    var masked := driver.step(0.0)
    if not _near_vec(_joint(masked, "left_wrist"), Vector2(0.30, 0.10)):
        _fail("masked wrist did not receive weighted overlay: %s" % str(_joint(masked, "left_wrist")), 95)
        return
    if not _near_vec(_joint(masked, "head"), Vector2(0.10, -0.05)):
        _fail("masked head did not receive weighted overlay", 96)
        return
    if not _near_vec(_joint(masked, "left_ankle"), Vector2(0.20, 0.0)):
        _fail("joint mask leaked overlay into ankle: %s" % str(_joint(masked, "left_ankle")), 97)
        return
    if not _near((masked.get("offset", Vector2.ZERO) as Vector2).y, 1.0):
        _fail("root changed even though root_weight=0", 98)
        return

    # Keep the same masked layer but explicitly allow a quarter-strength root
    # contribution: weight=.5 * root_weight=.5 => root mix=.25.
    if not driver.set_additive_layer(
        "gesture", "upper_gesture", 0.5,
        ["left_wrist", "head"], 0.5, 1.0, true
    ):
        _fail("root-weighted layer was rejected", 99)
        return
    var rooted := driver.step(0.0)
    var rooted_offset: Vector2 = rooted.get("offset", Vector2.ZERO)
    var rooted_scale: Vector2 = rooted.get("scale", Vector2.ONE)
    if not _near(rooted_offset.y, 2.0):
        _fail("weighted root offset wrong: %.5f" % rooted_offset.y, 100)
        return
    if not _near(float(rooted.get("rotation", 0.0)), 0.15):
        _fail("weighted root rotation wrong: %.5f" % float(rooted.get("rotation", 0.0)), 101)
        return
    if not _near_vec(rooted_scale, Vector2(1.05, 1.05)):
        _fail("weighted root scale wrong: %s" % str(rooted_scale), 102)
        return

    if not driver.set_additive_layer_weight("gesture", 0.25):
        _fail("could not adjust active layer weight", 103)
        return
    var quarter := driver.step(0.0)
    if not _near_vec(_joint(quarter, "left_wrist"), Vector2(0.20, 0.05)):
        _fail("layer weight update not applied exactly once", 104)
        return

    # A bad clip request must fail without deleting/replacing the valid layer.
    if driver.set_additive_layer("gesture", "missing_clip", 1.0):
        _fail("missing overlay clip was accepted", 105)
        return
    if driver.active_layer_names() != ["gesture"]:
        _fail("rejected layer request mutated active layers", 106)
        return

    # Switching the base while the overlay is live must not bake the overlay into
    # _blend_from and then add it a second time.
    driver.set_animation("base_walk_alt", 0.0)
    var switched := driver.step(0.0)
    if not _near_vec(_joint(switched, "left_wrist"), Vector2(0.0, 0.05)):
        _fail("overlay was lost or double-applied after base switch: %s" % str(_joint(switched, "left_wrist")), 107)
        return
    if not _near_vec(_joint(switched, "left_ankle"), Vector2(0.30, 0.0)):
        _fail("masked ankle changed after base switch", 108)
        return

    # Layer speed has its own phase, independent of base phase.
    if not driver.set_additive_layer(
        "gesture", "upper_gesture", 0.25,
        ["left_wrist", "head"], 0.0, 2.0, true
    ):
        _fail("speed test layer rejected", 109)
        return
    driver.step(0.25)
    var layer: Dictionary = driver.layers.get("gesture", {})
    if not _near(float(layer.get("phase", -1.0)), 0.5):
        _fail("independent layer phase/speed wrong: %s" % str(layer.get("phase", null)), 110)
        return

    if not driver.clear_additive_layer("gesture"):
        _fail("active layer could not be cleared", 111)
        return
    var cleared := driver.step(0.0)
    if not _near_vec(_joint(cleared, "left_wrist"), Vector2(-0.10, 0.0)):
        _fail("clearing layer did not restore pure base pose", 112)
        return
    if not driver.active_layer_names().is_empty():
        _fail("layer registry not empty after clear", 113)
        return

    print("KROLIK_LAYERED_ANIMATION base_wrist=%s masked_wrist=%s masked_ankle=%s rooted_y=%.3f switched_wrist=%s layers=%d" % [
        str(_joint(base, "left_wrist")),
        str(_joint(masked, "left_wrist")),
        str(_joint(masked, "left_ankle")),
        rooted_offset.y,
        str(_joint(switched, "left_wrist")),
        driver.layers.size(),
    ])
    quit(0)
