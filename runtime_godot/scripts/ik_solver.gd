class_name VaultIKSolver
extends RefCounted

## Two-bone IK with conservative, configurable interior-joint limits.
## Interior angle convention: 180 degrees is a straight limb; smaller values
## are progressively more folded. Defaults prevent full lock/hyperextension and
## pathological full folding while preserving the legacy API for callers.

const DEFAULT_JOINT_LIMITS := {
    "left_elbow": Vector2(8.0, 175.0),
    "right_elbow": Vector2(8.0, 175.0),
    "left_knee": Vector2(12.0, 175.0),
    "right_knee": Vector2(12.0, 175.0),
}

static func default_limits(mid_name: String) -> Vector2:
    var value = DEFAULT_JOINT_LIMITS.get(mid_name, Vector2(0.0, 180.0))
    return value if typeof(value) == TYPE_VECTOR2 else Vector2(0.0, 180.0)

static func joint_angle_deg(root: Vector2, mid: Vector2, end: Vector2) -> float:
    var a := root - mid
    var b := end - mid
    if a.length_squared() <= 1e-12 or b.length_squared() <= 1e-12:
        return 180.0
    var dot_value := clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)
    return rad_to_deg(acos(dot_value))

static func _distance_for_joint_angle(l1: float, l2: float, angle_deg: float) -> float:
    var angle := deg_to_rad(clampf(angle_deg, 0.0, 180.0))
    return sqrt(maxf(0.0, l1 * l1 + l2 * l2 - 2.0 * l1 * l2 * cos(angle)))

static func _safe_limits(min_joint_deg: float, max_joint_deg: float) -> Vector2:
    var min_deg := min_joint_deg if is_finite(min_joint_deg) else 0.0
    var max_deg := max_joint_deg if is_finite(max_joint_deg) else 180.0
    min_deg = clampf(min_deg, 0.0, 179.9)
    max_deg = clampf(max_deg, min_deg + 0.01, 180.0)
    return Vector2(min_deg, max_deg)

static func solve_two_bone(
    root: Vector2,
    mid: Vector2,
    end: Vector2,
    target: Vector2,
    bend_sign := 0.0,
    max_stretch := 1.0,
    min_joint_deg := 0.0,
    max_joint_deg := 180.0
) -> Dictionary:
    var l1 := maxf(root.distance_to(mid), 0.000001)
    var l2 := maxf(mid.distance_to(end), 0.000001)
    var delta := target - root
    var d := delta.length()
    if d < 0.000001:
        delta = Vector2.RIGHT
        d = 1.0

    var limits := _safe_limits(min_joint_deg, max_joint_deg)
    var stretch := max_stretch if is_finite(max_stretch) else 1.0
    stretch = maxf(stretch, 0.01)
    var legacy_min_reach := absf(l1 - l2) + 0.000001
    var min_angle_reach := _distance_for_joint_angle(l1, l2, limits.x)
    var max_angle_reach := _distance_for_joint_angle(l1, l2, limits.y)
    var min_reach := maxf(legacy_min_reach, min_angle_reach)
    var stretch_reach := (l1 + l2) * stretch
    var max_reach := maxf(min_reach, minf(stretch_reach, max_angle_reach))
    var dc := clampf(d, min_reach, max_reach)
    var u := delta / d
    var solved_end := root + u * dc

    if is_zero_approx(bend_sign):
        var a := mid - root
        var b := end - mid
        var cross := a.x * b.y - a.y * b.x
        bend_sign = -1.0 if cross < 0.0 else 1.0
    bend_sign = -1.0 if bend_sign < 0.0 else 1.0

    var along := (l1 * l1 - l2 * l2 + dc * dc) / (2.0 * dc)
    var height := sqrt(maxf(0.0, l1 * l1 - along * along))
    var base := root + u * along
    var perp := Vector2(-u.y, u.x)
    var solved_mid := base + perp * height * bend_sign
    var angle := joint_angle_deg(root, solved_mid, solved_end)
    var limited := absf(dc - d) > 0.00001
    return {
        "root": root,
        "mid": solved_mid,
        "end": solved_end,
        "joint_angle_deg": angle,
        "limited": limited,
        "min_joint_deg": limits.x,
        "max_joint_deg": limits.y,
    }

static func apply_chain(
    joints: Dictionary,
    root_name: String,
    mid_name: String,
    end_name: String,
    target: Vector2,
    strength := 1.0,
    max_stretch := 1.0,
    min_joint_deg := -1.0,
    max_joint_deg := -1.0
) -> Dictionary:
    var out := joints.duplicate(true)
    if not (out.has(root_name) and out.has(mid_name) and out.has(end_name)):
        return out
    var root: Vector2 = out[root_name]
    var mid: Vector2 = out[mid_name]
    var end: Vector2 = out[end_name]
    var s := clampf(strength if is_finite(strength) else 1.0, 0.0, 1.0)
    if s <= 0.0:
        return out

    var defaults := default_limits(mid_name)
    var min_deg := defaults.x if min_joint_deg < 0.0 or not is_finite(min_joint_deg) else min_joint_deg
    var max_deg := defaults.y if max_joint_deg < 0.0 or not is_finite(max_joint_deg) else max_joint_deg
    # Blend the goal, not the solved joint positions. Solving once against the
    # blended goal preserves segment lengths and guarantees the final pose obeys
    # the configured angle limits even when strength is fractional.
    var effective_target := end.lerp(target, s)
    var solved := solve_two_bone(
        root, mid, end, effective_target, 0.0, max_stretch, min_deg, max_deg
    )
    out[mid_name] = solved.mid
    out[end_name] = solved.end
    return out
