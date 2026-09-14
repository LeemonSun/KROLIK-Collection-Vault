extends SceneTree

## Runtime regression for C2 joint-angle limits. Exercises both the low-level
## two-bone solver and the exact VaultCharacterAgent animation -> IK path.

const AgentScript = preload("res://scripts/character_agent.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String, code: int) -> void:
    push_error("KROLIK IK limit regression failed: %s" % message)
    quit(code)

func _near(a: float, b: float, tolerance := 0.001) -> bool:
    return absf(a - b) <= tolerance

func _chain_angle(joints: Dictionary, root_name: String, mid_name: String, end_name: String) -> float:
    return VaultIKSolver.joint_angle_deg(
        joints[root_name], joints[mid_name], joints[end_name]
    )

func _check_segment_lengths(joints: Dictionary, expected_a: float, expected_b: float, code: int) -> bool:
    var l1: float = joints["root"].distance_to(joints["mid"])
    var l2: float = joints["mid"].distance_to(joints["end"])
    if not _near(l1, expected_a, 0.0005) or not _near(l2, expected_b, 0.0005):
        _fail("segment lengths changed: %.6f / %.6f" % [l1, l2], code)
        return false
    return true

func _run() -> void:
    var root := Vector2(0.0, 0.0)
    var mid := Vector2(1.0, 0.0)
    var end := Vector2(2.0, 0.0)

    # Far target would lock the limb straight without the configured maximum.
    var far: Dictionary = VaultIKSolver.solve_two_bone(
        root, mid, end, Vector2(8.0, 0.0), 1.0, 1.0, 20.0, 150.0
    )
    var far_angle := VaultIKSolver.joint_angle_deg(far.root, far.mid, far.end)
    if far_angle < 19.99 or far_angle > 150.01:
        _fail("far target escaped [20,150] joint limit: %.5f" % far_angle, 81)
        return
    if not bool(far.get("limited", false)):
        _fail("far target was clamped but solver did not report limited=true", 82)
        return
    var far_joints := {"root": far.root, "mid": far.mid, "end": far.end}
    if not _check_segment_lengths(far_joints, 1.0, 1.0, 83):
        return

    # Near target would fold an equal-length limb almost completely without the
    # configured minimum interior angle.
    var close: Dictionary = VaultIKSolver.solve_two_bone(
        root, mid, end, Vector2(0.01, 0.0), 1.0, 1.0, 25.0, 170.0
    )
    var close_angle := VaultIKSolver.joint_angle_deg(close.root, close.mid, close.end)
    if close_angle < 24.99 or close_angle > 170.01:
        _fail("near target escaped [25,170] joint limit: %.5f" % close_angle, 84)
        return

    # The public apply_chain API must retain configurability and preserve lengths
    # even at fractional constraint strength.
    var source := {
        "left_shoulder": root,
        "left_elbow": mid,
        "left_wrist": end,
    }
    var custom := VaultIKSolver.apply_chain(
        source, "left_shoulder", "left_elbow", "left_wrist",
        Vector2(7.0, 0.0), 0.45, 1.0, 35.0, 125.0
    )
    var custom_angle := _chain_angle(custom, "left_shoulder", "left_elbow", "left_wrist")
    if custom_angle < 34.99 or custom_angle > 125.01:
        _fail("custom apply_chain limits were not enforced: %.5f" % custom_angle, 85)
        return
    if not _near(custom["left_shoulder"].distance_to(custom["left_elbow"]), 1.0, 0.0005):
        _fail("apply_chain changed upper segment length", 86)
        return
    if not _near(custom["left_elbow"].distance_to(custom["left_wrist"]), 1.0, 0.0005):
        _fail("apply_chain changed lower segment length", 87)
        return

    # End-to-end: feed an already animated base pose into the same method used by
    # CharacterAgent after animation sampling, then apply a user-authored
    # interaction constraint with explicit max_stretch and angle limits.
    var agent := AgentScript.new() as VaultCharacterAgent
    agent.rig_joints = {
        "left_shoulder": Vector2(0.25, 0.30),
        "left_elbow": Vector2(0.38, 0.39),
        "left_wrist": Vector2(0.48, 0.50),
    }
    agent.animated_joints = {
        "left_shoulder": Vector2(0.25, 0.30),
        "left_elbow": Vector2(0.40, 0.36),
        "left_wrist": Vector2(0.52, 0.44),
    }
    agent.runtime_constraints = [{
        "enabled": true,
        "joint": "left_wrist",
        "target_v": Vector2(1.4, 0.22),
        "strength": 1.0,
        "max_stretch": 1.0,
        "min_joint_deg": 30.0,
        "max_joint_deg": 118.0,
    }]
    agent._solve_runtime_constraints(agent.animated_joints)
    var agent_angle := _chain_angle(
        agent.solved_joints, "left_shoulder", "left_elbow", "left_wrist"
    )
    if agent_angle < 29.99 or agent_angle > 118.01:
        _fail("CharacterAgent animation->IK path escaped authored limits: %.5f" % agent_angle, 88)
        return

    # Default elbow limits must also be active when old interaction payloads do
    # not provide the optional fields.
    agent.runtime_constraints = [{
        "enabled": true,
        "joint": "left_wrist",
        "target_v": Vector2(2.5, 0.30),
        "strength": 1.0,
    }]
    agent._solve_runtime_constraints(agent.animated_joints)
    var default_angle := _chain_angle(
        agent.solved_joints, "left_shoulder", "left_elbow", "left_wrist"
    )
    var defaults := VaultIKSolver.default_limits("left_elbow")
    if default_angle < defaults.x - 0.01 or default_angle > defaults.y + 0.01:
        _fail("CharacterAgent did not apply default elbow limits: %.5f" % default_angle, 89)
        return

    print("KROLIK_IK_LIMITS far=%.3f close=%.3f custom=%.3f agent=%.3f default=%.3f" % [
        far_angle, close_angle, custom_angle, agent_angle, default_angle
    ])
    quit(0)
