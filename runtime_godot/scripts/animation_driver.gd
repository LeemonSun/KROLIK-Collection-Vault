class_name VaultAnimationDriver
extends RefCounted

var current := "idle_breathe"
var phase := 0.0
var speed := 1.0

func set_animation(name: String) -> void:
    if name == current:
        return
    current = name
    phase = 0.0

func step(delta: float) -> Dictionary:
    phase += delta * speed
    var out := {
        "offset": Vector2.ZERO,
        "rotation": 0.0,
        "scale": Vector2.ONE,
        "head": Vector2.ZERO,
        "breath": 0.0,
    }
    match current:
        "walk":
            out.offset.y = sin(phase * 8.0) * 2.2
            out.rotation = sin(phase * 4.0) * 0.012
            out.breath = sin(phase * 4.0) * 0.004
        "inspect":
            out.head.x = sin(phase * 1.7) * 6.0
            out.rotation = sin(phase * 0.8) * 0.008
            out.breath = sin(phase * 2.0) * 0.003
        "social_idle":
            out.head.x = sin(phase * 1.2) * 4.0
            out.offset.y = sin(phase * 1.6) * 1.2
            out.breath = sin(phase * 2.2) * 0.004
        "contained_idle":
            out.head.x = sin(phase * 0.9) * 3.5
            out.rotation = sin(phase * 0.7) * 0.006
            out.breath = sin(phase * 1.8) * 0.003
        "rest":
            out.offset.y = abs(sin(phase * 1.15)) * 0.8
            out.breath = sin(phase * 1.25) * 0.002
        "idle_static":
            pass
        _:
            out.offset.y = sin(phase * 1.4) * 1.0
            out.rotation = sin(phase * 0.55) * 0.005
            out.breath = sin(phase * 1.9) * 0.003
    out.scale = Vector2(1.0 + out.breath, 1.0 + out.breath)
    return out
