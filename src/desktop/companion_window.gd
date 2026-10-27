extends Window
## Native full-body desktop prototype. Texture movement and FX, not a finished body rig.
signal chat_requested
signal settings_requested
signal pause_requested
signal hide_requested
signal quit_requested
const VisualTheme = preload("res://src/ui/visual_theme.gd")
const BODY_PATH = "res://assets/characters/signal_01/body_v1.png"
var art
var canvas
var dragging = false
var drag_offset = Vector2i.ZERO
var reduced_motion = false
var effect_time = 0.0
var effect_kind = ""
var original_position = Vector2i.ZERO
var target_position = Vector2i.ZERO
var phase = 0.0
var elapsed = 0.0
var auto_move = false
var next_move = 20.0
var last_tick_ms = 0
var app
var press_position = Vector2i.ZERO
var moved = false
var quick_menu
var _hit_polygon = PackedVector2Array()

class Surface extends Control:
	var owner_window
	func _draw():
		var w = owner_window
		if w.effect_time > 0 and not w.reduced_motion:
			var alpha = minf(1.0, w.effect_time / 0.15)
			for i in range(3):
				var x = 65 + i * 45
				draw_polyline(PackedVector2Array([Vector2(x, 330), Vector2(x+65, 250), Vector2(x+40, 210), Vector2(x+100, 120)]), Color(1.0, 0.18, 0.32, alpha * (0.45-i*0.1)), 2.0, true)

func _ready():
	app = get_tree().root.get_node("App")
	title = "Signal 01"
	borderless = true
	unresizable = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	exclude_from_capture = true
	size = Vector2i(330, 500)
	min_size = size
	canvas = Surface.new()
	canvas.owner_window = self
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var texture = load(BODY_PATH)
	if not texture is Texture2D:
		hide()
		return
	var image = texture.get_image()
	if image.is_compressed():
		image.decompress()
	art = TextureRect.new()
	art.texture = texture
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size = Vector2(330, 495)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(art)
	# Follow the generated alpha outline, leaving transparent desktop areas clickable.
	var bitmap = BitMap.new()
	bitmap.create_from_image_alpha(image, 0.3)
	var polygons = bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), 12.0)
	var largest = PackedVector2Array()
	for polygon in polygons:
		if polygon.size() > largest.size():
			largest = polygon
	for point in largest:
		_hit_polygon.append(point * Vector2(330.0 / image.get_width(), 495.0 / image.get_height()))
	if _hit_polygon.size() >= 3:
		mouse_passthrough_polygon = _hit_polygon
	window_input.connect(_input_event)
	close_requested.connect(hide)
	var bounds = DisplayServer.screen_get_usable_rect(current_screen)
	position = bounds.end - size - Vector2i(30, 0)
	last_tick_ms = Time.get_ticks_msec()
	quick_menu = PopupMenu.new()
	quick_menu.theme = VisualTheme.make()
	for key in ["talk","settings","menu_dash","pause","menu_hide","menu_quit"]:
		quick_menu.add_item(app.t(key))
	quick_menu.id_pressed.connect(_menu_action)
	add_child(quick_menu)
	if not reduced_motion:
		art.modulate.a = 0
		phase = 0
		effect_kind = "spawn"
		effect_time = 0.52

func _input_event(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				moved = false
				press_position = DisplayServer.mouse_get_position()
				effect_kind = ""
				art.modulate.a = 1.0
				drag_offset = press_position-position
			else:
				dragging = false
				if moved:
					position = bounded(position)
					effect_time = 0.25
				else:
					chat_requested.emit()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			quick_menu.position = DisplayServer.mouse_get_position()
			var keys = ["talk","settings","menu_dash","resume" if app.paused else "pause","menu_hide","menu_quit"]
			for index in range(keys.size()):
				quick_menu.set_item_text(index,app.t(keys[index]))
			quick_menu.popup()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			hide_requested.emit()
	elif event is InputEventMouseMotion and dragging:
		if DisplayServer.mouse_get_position().distance_to(press_position)>=6:
			moved = true
		if moved:
			position = bounded(DisplayServer.mouse_get_position()-drag_offset)

func _menu_action(id):
	match id:
		0: chat_requested.emit()
		1: settings_requested.emit()
		2: dash_random()
		3: pause_requested.emit()
		4: hide_requested.emit()
		5: quit_requested.emit()

func bounded(candidate):
	var screen = DisplayServer.get_screen_from_rect(Rect2i(candidate, size))
	if screen < 0:
		screen = current_screen
	var bounds = DisplayServer.screen_get_usable_rect(screen)
	return Vector2i(clampi(candidate.x, bounds.position.x, maxi(bounds.position.x, bounds.end.x-size.x)), clampi(candidate.y, bounds.position.y, maxi(bounds.position.y, bounds.end.y-size.y)))

func dash_random():
	if dragging or not visible:
		return
	var bounds = DisplayServer.screen_get_usable_rect(current_screen)
	var candidate = Vector2i(randi_range(bounds.position.x, maxi(bounds.position.x, bounds.end.x-size.x)), position.y)
	dash_to(candidate)

func dash_to(candidate):
	original_position = position
	target_position = bounded(candidate)
	if reduced_motion:
		position = target_position
		return
	effect_kind = "dash"
	phase = 0
	effect_time = 0.52
	set_process(true)

func set_reduced(value):
	reduced_motion = value
	effect_kind = ""
	effect_time = 0
	if art:
		art.modulate.a = 1.0

func _process(delta):
	if not visible or art == null:
		return
	elapsed += delta
	if auto_move and not dragging and effect_kind.is_empty():
		next_move -= delta
		if next_move <= 0:
			next_move = randf_range(25.0, 50.0)
			dash_random()
	if effect_time > 0:
		effect_time = maxf(0, effect_time-delta)
		if effect_kind == "spawn":
			phase += delta
			art.modulate.a = minf(1.0,phase/0.32)
			if effect_time <= 0:
				art.modulate.a = 1.0
				effect_kind = ""
		elif effect_kind == "dash":
			phase += delta
			if phase < 0.16:
				art.modulate.a = 1.0 - phase/0.16
			elif phase < 0.29:
				art.modulate.a = 0
				position = target_position
			else:
				art.modulate.a = minf(1, (phase-0.29)/0.15)
			if effect_time <= 0:
				position = target_position
				art.modulate.a = 1
				effect_kind = ""
		canvas.queue_redraw()
