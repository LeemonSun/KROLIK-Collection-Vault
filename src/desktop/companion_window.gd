extends Node
## The visible character uses the MAIN window. No invisible offscreen host.
## Articulated 2D companion; the native input region is stable between size changes.
signal chat_requested
signal settings_requested
signal pause_requested
signal hide_requested
signal quit_requested
const ActionMenu = preload("res://src/desktop/action_menu.gd")
const VisualTheme = preload("res://src/ui/visual_theme.gd")
const BODY_PATH = "res://assets/characters/leemon_01/master_v1.png"
const Rig=preload("res://src/animation/leemon_rig.gd")
const BASE_SIZE=Vector2i(210,232)
var user_scale=1.0
var host: Window
var position: Vector2i:
	get: return host.position if is_instance_valid(host) else Vector2i.ZERO
	set(value):
		if is_instance_valid(host): host.position = value
var size: Vector2i:
	get: return host.size if is_instance_valid(host) else BASE_SIZE
	set(value):
		if is_instance_valid(host): host.size = value
var current_screen: int:
	get: return host.current_screen if is_instance_valid(host) else 0
var visible: bool:
	get: return is_instance_valid(host) and host.mode != Window.MODE_MINIMIZED
var art
var tray
var startup_error = false
var canvas
var dragging = false
var drag_mouse=Vector2i.ZERO
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
var normalized_outline=PackedVector2Array()
var last_display_bounds=Rect2i()
var boundary_elapsed=0.0
var idle_variation=45.0
var region_updates=0
var overlay_pending=false

class Surface extends Control:
	var owner_window
	func _draw():
		var w = owner_window
		draw_set_transform(Vector2.ZERO,0,Vector2(w.size)/Vector2(330,500))
		if w.effect_time > 0 and not w.reduced_motion:
			var alpha = minf(1.0, w.effect_time / 0.15)
			var sweep=1.0-w.effect_time/0.52
			for i in range(4):
				var y=470.0-sweep*390.0+i*19.0
				var offset=sin(sweep*PI)*12.0
				draw_polyline(PackedVector2Array([Vector2(76+offset,y+15),Vector2(104+offset,y),Vector2(250-offset,y),Vector2(270-offset,y-14)]),Color(1.0,0.78,0.26,alpha*(0.4-i*0.07)),1.4,true)

func _ready():
	app = get_tree().root.get_node("App")
	host = get_tree().root
	host.title = "Leemon"
	host.mode = Window.MODE_WINDOWED
	host.borderless = true
	host.unresizable = true
	host.transparent = true
	host.transparent_bg = true
	host.always_on_top = true
	host.unfocusable = false
	host.mouse_passthrough = false
	host.exclude_from_capture = false
	host.disable_3d=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,host.get_window_id())
	user_scale=clampf(float(app.store.data.settings.get("character_scale",1.0)),0.75,1.5)
	var usable = DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen())
	var fit = minf(1.0,minf(float(usable.size.y)/float(BASE_SIZE.y*user_scale),float(usable.size.x)/float(BASE_SIZE.x*user_scale)))*user_scale
	var fitted = Vector2i(Vector2(BASE_SIZE)*fit)
	host.min_size = fitted
	size = fitted
	canvas = Surface.new()
	canvas.owner_window = self
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(canvas)
	var texture = load(BODY_PATH)
	if not texture is Texture2D:
		_show_fallback()
		return
	var image = texture.get_image()
	if image.is_compressed():
		image.decompress()
	art = Rig.new()
	art.texture = texture
	art.pivot_offset = Vector2(BASE_SIZE)*Vector2(0.5,0.7)*fit
	art.size = Vector2(BASE_SIZE)*fit
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
		normalized_outline.append(point / Vector2(image.get_size()))
		_hit_polygon.append(point * art.size / Vector2(image.get_size()))
	_update_hit_region()
	host.window_input.connect(_input_event)
	host.focus_entered.connect(_restore_opacity)
	host.focus_exited.connect(func(): dragging=false; Input.use_accumulated_input=true)
	host.close_requested.connect(func(): get_tree().quit())
	var bounds = DisplayServer.screen_get_usable_rect(current_screen)
	last_display_bounds=bounds
	position = bounds.end - size - Vector2i(30, 0)
	print("DESKTOP_READY main_window=", host.get_window_id(), " position=", position, " size=", size)
	_setup_tray()
	last_tick_ms = Time.get_ticks_msec()
	quick_menu = ActionMenu.new()
	quick_menu.visible = false
	quick_menu.action.connect(_menu_action)
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
				Input.use_accumulated_input=false
				app.mark_active()
				art.play("grab")
				moved = false
				press_position = DisplayServer.mouse_get_position()
				effect_kind = ""
				art.modulate.a = 1.0
				drag_mouse=press_position
				drag_offset = press_position-position
			else:
				dragging = false
				art.play("settle",0.8) if moved else art.play("idle")
				Input.use_accumulated_input=true
				if moved:
					position=bounded(DisplayServer.mouse_get_position()-drag_offset)
					effect_time = 0.25
				else:
					chat_requested.emit()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			quick_menu.open_at(DisplayServer.mouse_get_position())
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			hide_requested.emit()
	elif event is InputEventMouseMotion and dragging:
		if DisplayServer.mouse_get_position().distance_to(press_position)>=6:
			moved = true
		if moved:
			drag_mouse=DisplayServer.mouse_get_position()

func _menu_action(id):
	match id:
		0: chat_requested.emit()
		1: settings_requested.emit()
		2: walk_random()
		3: pause_requested.emit()
		4: hide_requested.emit()
		5: quit_requested.emit()

func bounded(candidate):
	var screen = DisplayServer.get_screen_from_rect(Rect2i(candidate, size))
	if screen < 0:
		screen = clampi(current_screen,0,maxi(0,DisplayServer.get_screen_count()-1))
	var bounds = DisplayServer.screen_get_usable_rect(screen)
	return clamp_to_bounds(candidate,bounds)

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
		art.set_reduced(value)

func _process(delta):
	if not visible or art == null:
		return
	if dragging:
		app.mark_active()
		if moved:position=bounded(drag_mouse-drag_offset)
	# The static effect surface redraws only during the short effect, not each idle frame.
	if art.clip=="idle" and not reduced_motion and not dragging:
		idle_variation-=delta
		if idle_variation<=0:
			art.play(["stretch","rest","nod"][randi()%3],2.2);idle_variation=randf_range(55,95)
	elapsed += delta
	boundary_elapsed+=delta
	if boundary_elapsed>=1.0 and not dragging:
		boundary_elapsed=0
		refresh_bounds()
	if effect_kind=="edge_enter":
		phase+=delta
		var progress=clampf(phase/0.9,0,1)
		position=Vector2i(Vector2(original_position).lerp(Vector2(target_position),1.0-pow(1.0-progress,3)))
		art.modulate.a=smoothstep(0.0,0.2,progress)
		if progress>=1:
			position=target_position;effect_kind="";art.modulate.a=1
			art.play("hello",1.3)
	if effect_kind=="walk":
		app.mark_active()
		phase+=delta
		var progress=clampf(phase/maxf(0.1,walk_duration),0,1)
		position=bounded(Vector2i(Vector2(original_position).lerp(Vector2(target_position),smoothstep(0,1,progress))))
		if progress>=1.0:effect_kind="";art.play("idle")
	if overlay_pending and app.desktop_actions.pid<=0:
		overlay_pending=false
		if OS.get_name()=="Windows" and is_instance_valid(tray):app.desktop_actions.request_overlay(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,host.get_window_id()))
	var lean = clampf(float(DisplayServer.mouse_get_position().x-press_position.x)*0.0005,-0.07,0.07) if dragging and moved else 0.0
	art.rotation = lerp_angle(art.rotation,lean,minf(1.0,delta*12.0))
	if reduced_motion: art.rotation=0.0
	if auto_move and not dragging and effect_kind.is_empty():
		next_move -= delta
		if next_move <= 0:
			next_move = randf_range(25.0, 50.0)
			walk_random()
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

func get_texture():
	return host.get_texture()

func _restore_opacity():
	# A taskbar restore must never return an invisible animation frame.
	if art:
		art.modulate.a = 1.0
	effect_kind = ""
	effect_time = 0

func show():
	if not is_instance_valid(host): return
	host.mode = Window.MODE_WINDOWED
	host.show()
	refresh_bounds()
	position = bounded(position)
	_restore_opacity()

func hide():
	# The main Window cannot be hidden. Minimize keeps the taskbar recovery path.
	if is_instance_valid(host): host.mode = Window.MODE_MINIMIZED

func recover():
	if not is_instance_valid(host): return
	show()
	var screen = DisplayServer.get_primary_screen()
	var bounds = DisplayServer.screen_get_usable_rect(screen)
	position = bounds.end - size - Vector2i(30,0)
	position = bounded(position)
	host.grab_focus()

func _setup_tray():
	if OS.get_name() not in ["Windows","macOS"] or not ClassDB.class_exists("StatusIndicator"): return
	tray = ClassDB.instantiate("StatusIndicator")
	tray.icon = load("res://assets/foundation.svg")
	tray.tooltip = "Leemon — " + app.t("show_desktop")
	tray.pressed.connect(func(button,_point):
		if button == MOUSE_BUTTON_LEFT:
			recover()
			app.show_chat()
		elif button == MOUSE_BUTTON_RIGHT:
			app.open_settings("assistant_tools"))
	add_child(tray)
	overlay_pending=true

func _show_fallback():
	startup_error = true
	host.mouse_passthrough_polygon = PackedVector2Array()
	host.min_size = Vector2i(360,180)
	size = Vector2i(360,180)
	var bounds = DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen())
	position = bounds.position + (bounds.size-size)/2
	var panel = PanelContainer.new()
	panel.name = "RecoveryPanel"
	panel.theme = VisualTheme.make()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(panel)
	var layout = VBoxContainer.new()
	panel.add_child(layout)
	var label = Label.new()
	label.text = app.t("character_art_missing")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(label)
	var button = Button.new()
	button.text = app.t("settings")
	button.pressed.connect(func(): app.open_settings("assistant_tools"))
	layout.add_child(button)
	var quit_button = Button.new()
	quit_button.text = app.t("menu_quit")
	quit_button.pressed.connect(func(): get_tree().quit())
	layout.add_child(quit_button)
	host.close_requested.connect(func(): get_tree().quit())
	_setup_tray()
	push_warning("Character texture unavailable; visible recovery panel shown")

func play_entrance():
	if reduced_motion or app.paused or not art:return
	var destination=bounded(position)
	var bounds=DisplayServer.screen_get_usable_rect(current_screen)
	target_position=destination
	original_position=Vector2i(bounds.end.x+12,destination.y)
	position=original_position
	phase=0
	effect_kind="edge_enter"
	effect_time=0
	art.modulate.a=0
	art.play("walk")
	canvas.queue_redraw()

func clamp_to_bounds(candidate,bounds):
	return Vector2i(clampi(candidate.x,bounds.position.x,maxi(bounds.position.x,bounds.end.x-size.x)),clampi(candidate.y,bounds.position.y,maxi(bounds.position.y,bounds.end.y-size.y)))

func fit_to_bounds(bounds):
	if not art or bounds.size.x<=0 or bounds.size.y<=0:return
	var fit=minf(1.0,minf(float(bounds.size.y)/float(BASE_SIZE.y*user_scale),float(bounds.size.x)/float(BASE_SIZE.x*user_scale)))*user_scale
	var fitted=Vector2i(Vector2(BASE_SIZE)*fit)
	host.min_size=fitted
	size=fitted
	art.size=Vector2(BASE_SIZE)*fit
	art.pivot_offset=Vector2(BASE_SIZE)*Vector2(0.5,0.7)*fit
	_hit_polygon=PackedVector2Array()
	for point in normalized_outline:_hit_polygon.append(point*art.size)
	_update_hit_region()
	overlay_pending=true
	position=clamp_to_bounds(position,bounds)
	target_position=clamp_to_bounds(target_position,bounds)
	last_display_bounds=bounds

func refresh_bounds(force=false):
	var screen=DisplayServer.get_screen_from_rect(Rect2i(position,size))
	if screen<0:screen=DisplayServer.get_primary_screen()
	var bounds=DisplayServer.screen_get_usable_rect(screen)
	if (force or bounds!=last_display_bounds) and effect_kind!="edge_enter":fit_to_bounds(bounds)

var walk_duration=1.8
var mask_elapsed=0.0
func walk_random():
	if dragging or not visible or app.paused:return
	var distance=randf_range(80,160)*(1 if randf()>0.5 else -1)
	original_position=position
	target_position=bounded(position+Vector2i(int(distance),0))
	if reduced_motion:position=target_position;return
	effect_kind="walk";phase=0
	walk_duration=maxf(1.2,absf(target_position.x-original_position.x)/85.0)
	art.play("walk")
func react(event_id):
	if not art or reduced_motion:return false
	if event_id=="dialogue.think_loop":return art.play("thinking")
	elif event_id=="dialogue.explain_small":return art.play("talk",2.8)
	elif event_id in ["work.note_saved","work.timer_notice"]:return art.play("success",1.4)
	elif event_id in ["work.error_recover","work.model_missing"]:return art.play("error",1.8)
	return false

func _update_hit_region():
	if not art or normalized_outline.is_empty():return
	var outline=art.hit_envelope(normalized_outline)
	if outline.size()>3:
		host.mouse_passthrough_polygon=outline
		region_updates+=1

func set_character_scale(value):
	user_scale=clampf(float(value),0.75,1.5)
	app._save_setting("character_scale",user_scale)
	fit_to_bounds(DisplayServer.screen_get_usable_rect(current_screen))
