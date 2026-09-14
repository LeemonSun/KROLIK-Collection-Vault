extends SceneTree

## C5 regression for semantic facial/mood state plus the honestly renderable
## head/neck posture portion. Eye/mouth values are semantic until dedicated face
## geometry exists; this harness verifies their deterministic/bounded contract.

const AgentScript = preload("res://scripts/character_agent.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String, code: int) -> void:
    push_error("KROLIK facial state regression failed: %s" % message)
    quit(code)

func _near(a: float, b: float, tolerance := 0.00001) -> bool:
    return absf(a - b) <= tolerance

func _near_vec(a: Vector2, b: Vector2, tolerance := 0.00001) -> bool:
    return a.distance_to(b) <= tolerance

func _config() -> Dictionary:
    return {
        "procedural_blink": {
            "enabled": true,
            "min_interval": 0.40,
            "max_interval": 0.70,
            "duration": 0.12,
        },
        "look_at": {
            "enabled": true,
            "max_head_deg": 16.0,
            "max_eye": 0.06,
        },
    }

func _run() -> void:
    # Determinism: identical config + seed must produce the same blink/gaze
    # sequence frame-for-frame, while a different seed should decorrelate blink
    # timing so hundreds of agents do not all blink simultaneously.
    var a := VaultFacialState.new()
    var b := VaultFacialState.new()
    var c := VaultFacialState.new()
    a.configure(_config(), 42)
    b.configure(_config(), 42)
    c.configure(_config(), 99)
    a.set_look_target(Vector2(2.0, -2.0))
    b.set_look_target(Vector2(2.0, -2.0))
    c.set_look_target(Vector2(2.0, -2.0))

    var first_blink_a := -1
    var first_blink_c := -1
    var peak_blink := 0.0
    for frame in range(180):
        var sa := a.step(1.0 / 60.0)
        var sb := b.step(1.0 / 60.0)
        var sc := c.step(1.0 / 60.0)
        var ca: Dictionary = sa.get("channels", {})
        var cb: Dictionary = sb.get("channels", {})
        var cc: Dictionary = sc.get("channels", {})
        var blink_a := float(ca.get("blink", 0.0))
        var blink_b := float(cb.get("blink", 0.0))
        var blink_c := float(cc.get("blink", 0.0))
        if not _near(blink_a, blink_b):
            _fail("same seed produced divergent blink sequence at frame %d" % frame, 141)
            return
        if first_blink_a < 0 and blink_a > 0.05:
            first_blink_a = frame
        if first_blink_c < 0 and blink_c > 0.05:
            first_blink_c = frame
        peak_blink = maxf(peak_blink, blink_a)
        var gaze_a: Vector2 = ca.get("gaze", Vector2.ZERO)
        var gaze_b: Vector2 = cb.get("gaze", Vector2.ZERO)
        if not _near_vec(gaze_a, gaze_b):
            _fail("same seed/config produced divergent gaze", 142)
            return
        if absf(gaze_a.x) > 0.06001 or absf(gaze_a.y) > 0.06001:
            _fail("gaze exceeded max_eye: %s" % str(gaze_a), 143)
            return
        if absf(float(ca.get("head_yaw_deg", 0.0))) > 16.001:
            _fail("head yaw exceeded authored max", 144)
            return
        if absf(float(ca.get("head_pitch_deg", 0.0))) > 10.401:
            _fail("head pitch exceeded bounded vertical max", 145)
            return
    if first_blink_a < 0 or peak_blink < 0.80:
        _fail("deterministic blink never produced a real closure", 146)
        return
    if first_blink_c < 0 or first_blink_c == first_blink_a:
        _fail("different seeds did not decorrelate first blink", 147)
        return

    var settled := a.semantic_snapshot()
    var gaze: Vector2 = settled.get("gaze", Vector2.ZERO)
    if gaze.x < 0.055 or gaze.y > -0.055:
        _fail("look smoothing failed to approach clamped target: %s" % str(gaze), 148)
        return

    # Mood channels transition independently from body clips and stay bounded.
    if not a.set_mood("happy", 0.8, 0.25):
        _fail("known mood was rejected", 149)
        return
    var start_curve := float(a.semantic_snapshot().get("mouth_curve", 0.0))
    for _i in range(45):
        a.step(1.0 / 60.0)
    var happy := a.semantic_snapshot()
    var end_curve := float(happy.get("mouth_curve", 0.0))
    if end_curve <= start_curve + 0.20 or end_curve > 1.0:
        _fail("happy mood did not transition/bound mouth semantic: %.5f" % end_curve, 150)
        return
    if float(happy.get("eye_openness", 0.0)) < 0.0 or float(happy.get("eye_openness", 0.0)) > 1.0:
        _fail("eye openness escaped [0,1]", 151)
        return
    var mood_before := a.mood_name
    if a.set_mood("not_a_mood", 1.0, 0.0):
        _fail("unknown mood was accepted", 152)
        return
    if a.mood_name != mood_before:
        _fail("rejected mood mutated current mood", 153)
        return

    # Production CharacterAgent path: face posture must change only real face-capable
    # head/neck joints, expose semantic channels, and still leave explicit wrist
    # interaction IK authoritative after the full animation->face->secondary->IK chain.
    var agent := AgentScript.new() as VaultCharacterAgent
    agent.rig_joints = {
        "head": Vector2(0.50, 0.14),
        "neck": Vector2(0.50, 0.25),
        "left_shoulder": Vector2(0.36, 0.30),
        "left_elbow": Vector2(0.41, 0.41),
        "left_wrist": Vector2(0.46, 0.52),
    }
    agent.facial_state.configure(_config(), 7)
    agent.set_look_target(Vector2(1.0, 0.25))
    if not agent.set_mood("alert", 1.0, 0.0):
        agent.free()
        _fail("CharacterAgent rejected valid mood", 154)
        return
    agent.configure_secondary_motion({})
    agent.runtime_constraints = [{
        "enabled": true,
        "joint": "left_wrist",
        "target_v": Vector2(0.43, 0.47),
        "strength": 1.0,
        "max_stretch": 1.0,
        "min_joint_deg": 20.0,
        "max_joint_deg": 170.0,
    }]

    var base_head: Vector2 = agent.rig_joints["head"]
    for _i in range(30):
        agent._apply_animation_pose({
            "joint_offsets": {
                "head": Vector2(0.004, 0.0),
                "left_wrist": Vector2(0.02, 0.0),
            }
        }, 1.0 / 60.0)
    var animated_head: Vector2 = agent.animated_joints.get("head", Vector2.ZERO)
    if animated_head.x <= base_head.x + 0.004:
        agent.free()
        _fail("production face posture was not added after animation", 155)
        return
    var wrist: Vector2 = agent.solved_joints.get("left_wrist", Vector2.INF)
    var target := Vector2(0.43, 0.47)
    if not _near_vec(wrist, target, 0.001):
        agent.free()
        _fail("facial layer interfered with final IK authority: %s" % str(wrist), 156)
        return
    var face_snapshot := agent.facial_snapshot()
    if str(face_snapshot.get("mood", "")) != "alert":
        agent.free()
        _fail("CharacterAgent did not expose semantic mood snapshot", 157)
        return
    if not face_snapshot.has("blink") or not face_snapshot.has("mouth_curve") or not face_snapshot.has("gaze"):
        agent.free()
        _fail("semantic face channels missing from production snapshot", 158)
        return

    # Disabled/unconfigured controller must be a no-op and must not invent facial
    # deformation on rigs that have no face configuration.
    agent.facial_state.configure({}, 7)
    agent.runtime_constraints.clear()
    agent._apply_animation_pose({"joint_offsets": {}}, 1.0 / 60.0)
    if not _near_vec(agent.animated_joints["head"], base_head, 0.00001):
        agent.free()
        _fail("disabled facial controller changed head pose", 159)
        return

    var head_shift := animated_head.distance_to(base_head + Vector2(0.004, 0.0))
    agent.free()
    print("KROLIK_FACIAL_STATE first_blink=%d decorrelated=%d peak_blink=%.3f gaze=%s mood_curve=%.3f head_shift=%.6f ik_error=%.6f semantic=true" % [
        first_blink_a,
        first_blink_c,
        peak_blink,
        str(gaze),
        end_curve,
        head_shift,
        wrist.distance_to(target),
    ])
    quit(0)
