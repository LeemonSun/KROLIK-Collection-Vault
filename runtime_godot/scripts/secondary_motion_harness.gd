extends SceneTree

## C4 regression for spring/secondary motion. Exercises the solver directly and
## the production CharacterAgent order: animation -> secondary motion -> IK.

const AgentScript = preload("res://scripts/character_agent.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String, code: int) -> void:
    push_error("KROLIK secondary motion regression failed: %s" % message)
    quit(code)

func _near_vec(a: Vector2, b: Vector2, tolerance := 0.001) -> bool:
    return a.distance_to(b) <= tolerance

func _run() -> void:
    var config := {
        "hair": {"stiffness": 0.5, "damping": 0.8, "max_offset": 0.01},
        "accessories": {"stiffness": 0.35, "damping": 0.72, "max_offset": 0.012},
    }

    # Low-level spring proof: acceleration produces bounded lag, then damping
    # returns it toward rest once the character stops.
    var solver := VaultSecondaryMotion.new()
    solver.configure(config)
    var initial := solver.step(1.0 / 60.0, Vector2.ZERO)
    var initial_hair: Vector2 = initial.get("hair", Vector2.ZERO)
    if initial_hair.length() > 0.00001:
        _fail("spring did not initialize at rest", 121)
        return

    var impulse := solver.step(1.0 / 60.0, Vector2(120.0, 0.0))
    var impulse_hair: Vector2 = impulse.get("hair", Vector2.ZERO)
    if impulse_hair.length() <= 0.00001:
        _fail("velocity/acceleration produced no secondary lag", 122)
        return
    if absf(impulse_hair.x) > 0.01001 or absf(impulse_hair.y) > 0.01001:
        _fail("hair spring exceeded authored max_offset: %s" % str(impulse_hair), 123)
        return

    var peak := impulse_hair.length()
    var relaxed := impulse_hair
    for _i in range(180):
        var frame := solver.step(1.0 / 60.0, Vector2.ZERO)
        relaxed = frame.get("hair", Vector2.ZERO)
    if relaxed.length() >= peak * 0.25:
        _fail("spring did not damp back toward rest: peak=%.6f relaxed=%.6f" % [peak, relaxed.length()], 124)
        return

    # Production agent path. Hair must affect the animated base pose, while an
    # explicitly constrained wrist remains governed by IK rather than accessory
    # spring displacement.
    var agent := AgentScript.new() as VaultCharacterAgent
    agent.rig_joints = {
        "head": Vector2(0.50, 0.14),
        "neck": Vector2(0.50, 0.25),
        "left_shoulder": Vector2(0.36, 0.30),
        "left_elbow": Vector2(0.41, 0.41),
        "left_wrist": Vector2(0.46, 0.52),
    }
    agent.animated_joints = agent.rig_joints.duplicate(true)
    agent.configure_secondary_motion(config)
    if not agent.secondary_motion_enabled:
        agent.free()
        _fail("non-empty secondary config did not enable production path", 125)
        return

    agent.velocity = Vector2.ZERO
    agent._apply_animation_pose({"joint_offsets": {}}, 1.0 / 60.0)
    var rest_head: Vector2 = agent.animated_joints.get("head", Vector2.ZERO)

    agent.velocity = Vector2(120.0, 0.0)
    agent._apply_animation_pose({"joint_offsets": {}}, 1.0 / 60.0)
    var lagged_head: Vector2 = agent.animated_joints.get("head", Vector2.ZERO)
    if _near_vec(lagged_head, rest_head, 0.00001):
        agent.free()
        _fail("CharacterAgent did not apply secondary hair offset before IK", 126)
        return

    var target := Vector2(0.43, 0.47)
    agent.runtime_constraints = [{
        "enabled": true,
        "joint": "left_wrist",
        "target_v": target,
        "strength": 1.0,
        "max_stretch": 1.0,
        "min_joint_deg": 20.0,
        "max_joint_deg": 170.0,
    }]
    agent.velocity = Vector2(-120.0, 0.0)
    agent._apply_animation_pose({"joint_offsets": {}}, 1.0 / 60.0)
    var constrained_wrist: Vector2 = agent.solved_joints.get("left_wrist", Vector2.INF)
    if not _near_vec(constrained_wrist, target, 0.001):
        agent.free()
        _fail("IK endpoint lost authority after secondary motion: %s vs %s" % [str(constrained_wrist), str(target)], 127)
        return

    # Empty configuration must use the near-zero-cost path: no solver step and
    # no pose mutation. Resetting also clears spring state from a reused agent.
    agent.configure_secondary_motion({})
    if agent.secondary_motion_enabled:
        agent.free()
        _fail("empty config left secondary path enabled", 128)
        return
    if agent.secondary_motion._initialized:
        agent.free()
        _fail("empty config did not reset secondary solver state", 129)
        return
    agent.runtime_constraints.clear()
    agent.velocity = Vector2(300.0, 0.0)
    agent._apply_animation_pose({"joint_offsets": {}}, 1.0 / 60.0)
    var disabled_head: Vector2 = agent.animated_joints.get("head", Vector2.ZERO)
    if not _near_vec(disabled_head, agent.rig_joints["head"], 0.00001):
        agent.free()
        _fail("disabled secondary path still changed pose", 130)
        return
    if agent.secondary_motion._initialized:
        agent.free()
        _fail("disabled secondary path still stepped solver", 131)
        return

    agent.free()
    print("KROLIK_SECONDARY_MOTION impulse=%s peak=%.6f relaxed=%.6f head_shift=%.6f ik_error=%.6f disabled=true" % [
        str(impulse_hair),
        peak,
        relaxed.length(),
        lagged_head.distance_to(rest_head),
        constrained_wrist.distance_to(target),
    ])
    quit(0)
