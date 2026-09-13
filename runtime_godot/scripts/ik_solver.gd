class_name VaultIKSolver
extends RefCounted

static func solve_two_bone(root: Vector2, mid: Vector2, end: Vector2, target: Vector2, bend_sign := 0.0, max_stretch := 1.0) -> Dictionary:
    var l1 := maxf(root.distance_to(mid), 0.000001)
    var l2 := maxf(mid.distance_to(end), 0.000001)
    var delta := target - root
    var d := delta.length()
    if d < 0.000001:
        delta = Vector2.RIGHT
        d = 1.0
    var reach := (l1 + l2) * maxf(max_stretch, 0.01)
    var min_reach := absf(l1 - l2) + 0.000001
    var dc := clampf(d, min_reach, reach)
    var u := delta / d
    var solved_end := root + u * dc
    if is_zero_approx(bend_sign):
        var a := mid - root
        var b := end - mid
        var cross := a.x * b.y - a.y * b.x
        bend_sign = -1.0 if cross < 0.0 else 1.0
    bend_sign = -1.0 if bend_sign < 0.0 else 1.0
    var along := (l1*l1 - l2*l2 + dc*dc) / (2.0 * dc)
    var height := sqrt(maxf(0.0, l1*l1 - along*along))
    var base := root + u * along
    var perp := Vector2(-u.y, u.x)
    var solved_mid := base + perp * height * bend_sign
    return {"root": root, "mid": solved_mid, "end": solved_end}

static func apply_chain(joints: Dictionary, root_name: String, mid_name: String, end_name: String, target: Vector2, strength := 1.0) -> Dictionary:
    var out := joints.duplicate(true)
    if not (out.has(root_name) and out.has(mid_name) and out.has(end_name)):
        return out
    var root: Vector2 = out[root_name]
    var mid: Vector2 = out[mid_name]
    var end: Vector2 = out[end_name]
    var solved := solve_two_bone(root, mid, end, target)
    var s := clampf(strength, 0.0, 1.0)
    out[mid_name] = mid.lerp(solved.mid, s)
    out[end_name] = end.lerp(solved.end, s)
    return out
