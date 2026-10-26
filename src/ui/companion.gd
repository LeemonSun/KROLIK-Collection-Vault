extends Control
## Original geometric placeholder; no borrowed character art.
var phase = 0.0

func _ready():
	custom_minimum_size = Vector2(230, 280)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta):
	if App.paused:
		return
	phase += delta
	queue_redraw()

func _draw():
	var center = size * Vector2(0.5, 0.49)
	var bob = 0.0 if App.paused else sin(phase * 1.6) * 5.0
	var point = center + Vector2(0, bob)
	draw_ellipse_shadow(center + Vector2(0, 85))
	draw_circle(point, 66, Color("#1e343c"))
	draw_arc(point, 76, 0.3, TAU - 0.3, 72, Color("#345c62"), 1.5, true)
	var orbit = phase * 0.7 if App.state.current == "thinking" else 0.35
	var dot = point + Vector2(cos(orbit), sin(orbit)) * 76
	draw_circle(dot, 4, Color("#89c9c0"))
	var body = PackedVector2Array([point + Vector2(-48,-38), point + Vector2(36,-48), point + Vector2(56,-10), point + Vector2(37,48), point + Vector2(-36,48), point + Vector2(-56,8)])
	draw_colored_polygon(body, Color("#e5e5db"))
	draw_polyline(PackedVector2Array([body[0],body[1],body[2],body[3],body[4],body[5],body[0]]), Color("#ffffff"), 1.0, true)
	if App.paused:
		draw_line(point + Vector2(-23,-2), point + Vector2(-9,-2), Color("#263c48"), 3, true)
		draw_line(point + Vector2(9,-2), point + Vector2(23,-2), Color("#263c48"), 3, true)
	else:
		draw_circle(point + Vector2(-16,-3), 5, Color("#263c48"))
		draw_circle(point + Vector2(16,-3), 5, Color("#263c48"))
	draw_arc(point + Vector2(0,12), 8, 0.2, PI - 0.2, 16, Color("#3d6b70"), 2, true)
	draw_line(point + Vector2(0,-53), point + Vector2(0,-67), Color("#89c9c0"), 2, true)
	draw_circle(point + Vector2(0,-72), 4, Color("#89c9c0"))

func draw_ellipse_shadow(point):
	draw_set_transform(point, 0.0, Vector2(1.0, 0.18))
	draw_circle(Vector2.ZERO, 60, Color(0,0,0,0.22))
	draw_set_transform(Vector2.ZERO)

