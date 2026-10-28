extends Node
## The visible character uses the MAIN window. No invisible offscreen host.
## Articulated 2D companion; the native input region is stable between size changes.
signal file_requested
signal chat_requested
signal settings_requested
signal pause_requested
signal hide_requested
signal quit_requested
const ActionMenu = preload("res://src/desktop/action_menu.gd")
const VisualTheme = preload("res://src/ui/visual_theme.gd")
const BODY_PATH = "res://assets/characters/leemon_01/master_v1.png"
const Behavior=preload("res://src/desktop/companion_behavior.gd")
const Locomotion=preload("res://src/desktop/locomotion.gd")
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
var auto_move = true
var home_position=Vector2i.ZERO
var target_location_key=""
var last_chat_rect=Rect2i()
var park_delay=0.0
var activity_key="idle"
var activity_elapsed=0.0
var fx_kind=""
var fx_time=0.0
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
var locomotion=Locomotion.new()
var reaction_clip=""
var reaction_left=0.0
var reaction_priority=0
var pose_elapsed=0.0

class Surface extends Control:
	var owner_window
	func _draw():
		var w = owner_window
		draw_set_transform(Vector2.ZERO,0,Vector2(w.size)/Vector2(330,500))
		if w.fx_time>0 and not w.reduced_motion:
			var progress=1.0-w.fx_time/0.85
			var opacity=sin(progress*PI)*0.65
			var tint=Color(1.0,0.77,0.25,opacity)
			if w.fx_kind=="scan":
				var y=80+progress*280
				draw_line(Vector2(110,y),Vector2(225,y),tint,1.4,true)
			elif w.fx_kind=="success":
				for i in range(6):
					var angle=float(i)*TAU/6.0
					var p=Vector2(166,220)+Vector2(cos(angle),sin(angle))*(55+progress*35)
					draw_line(p,p+Vector2(cos(angle),sin(angle))*7,tint,1.8,true)
			else:
				draw_arc(Vector2(166,440),45+progress*15,0,TAU,32,tint,1.3,true)
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
	auto_move=bool(app.store.data.settings.get("companion_roam",true))
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
	host.focus_exited.connect(_release_drag)
	host.close_requested.connect(func(): get_tree().quit())
	var bounds = DisplayServer.screen_get_usable_rect(current_screen)
	last_display_bounds=bounds
	position = bounds.end - size - Vector2i(30, 0)
	home_position=position
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
				if is_instance_valid(app.speech_bubble):app.speech_bubble.dismiss()
				_cancel_travel()
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
				perform_gesture("settle",0.8) if moved else _sync_pose()
				Input.use_accumulated_input=true
				if moved:
					position=bounded(DisplayServer.mouse_get_position()-drag_offset)
					home_position=position
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
		6: file_requested.emit()

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
	if dragging or not visible or app.paused:return
	_cancel_travel()
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
	_cancel_travel()
	if is_instance_valid(host):position=bounded(position)
	reduced_motion = value
	effect_kind = ""
	effect_time = 0
	fx_time=0
	if is_instance_valid(canvas):canvas.queue_redraw()
	if art:
		art.modulate.a = 1.0
		art.set_reduced(value)

func _process(delta):
	if is_instance_valid(art) and art.suspended==visible:art.set_suspended(not visible)
	if not visible or art == null:
		return
	if dragging:
		app.mark_active()
		if moved:position=bounded(drag_mouse-drag_offset)
	if reaction_left>0:reaction_left=maxf(0,reaction_left-delta)
	activity_elapsed+=delta
	if activity_elapsed>=0.15 and not dragging:
		activity_elapsed=0
		if effect_kind not in ["walk","edge_enter","dash"]:
			if is_instance_valid(app.chat_window) and app.chat_window.visible:
				var anchor=Rect2i(app.chat_window.position,app.chat_window.size)
				if anchor!=last_chat_rect:last_chat_rect=anchor;park_delay=0.45
				elif park_delay>0:
					park_delay-=0.15
					if park_delay<=0:park_near(anchor)
		_sync_pose()
	if fx_time>0:
		fx_time=maxf(0,fx_time-delta);canvas.queue_redraw()
	# The static effect surface redraws only during the short effect, not each idle frame.
	if art.clip=="idle" and not reduced_motion and not dragging:
		idle_variation-=delta
		if idle_variation<=0:
			perform_gesture(["stretch","rest","nod"][randi()%3],2.2,0);idle_variation=randf_range(55,95)
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
			perform_gesture("hello",1.3,2)
	if effect_kind=="walk":
		app.mark_active()
		var travel=locomotion.sample(delta)
		position=bounded(Vector2i(travel.position.round()))
		if travel.stage=="prepare":
			if art.clip!="turn":art.play("turn")
		else:
			if art.clip!="walk":art.play("walk")
			art.set_locomotion(travel.direction,travel.speed,travel.distance)
		if not travel.active:
			position=bounded(target_position);effect_kind=""
			art.clear_locomotion()
			perform_gesture("settle",0.65,2)
	if overlay_pending and app.desktop_actions.pid<=0:
		overlay_pending=false
		if OS.get_name()=="Windows" and is_instance_valid(tray):app.desktop_actions.request_overlay(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,host.get_window_id()))
	var lean = clampf(float(DisplayServer.mouse_get_position().x-press_position.x)*0.0005,-0.07,0.07) if dragging and moved else 0.0
	art.rotation = lerp_angle(art.rotation,lean,minf(1.0,delta*12.0))
	if reduced_motion: art.rotation=0.0
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
	_cancel_travel()
	# A taskbar restore must never return an invisible animation frame.
	if art:
		art.modulate.a = 1.0
	effect_kind = ""
	effect_time = 0

func show():
	if not is_instance_valid(host): return
	host.mode = Window.MODE_WINDOWED
	host.show()
	if is_instance_valid(art):art.set_suspended(false)
	refresh_bounds()
	position = bounded(position)
	_restore_opacity()

func hide():
	_release_drag()
	_cancel_travel()
	if is_instance_valid(art):art.set_suspended(true)
	if is_instance_valid(app.speech_bubble):app.speech_bubble.dismiss()
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
	_cancel_travel()
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
func focus_target(identity):
	var rect=identity.get("bounds",{})
	if not rect is Dictionary or not rect.has_all(["x","y","width","height"]):return false
	var key=str(identity.get("handle",""))+":"+JSON.stringify(rect)
	if key==target_location_key and not Rect2i(position,size).intersects(Rect2i(int(rect.x),int(rect.y),int(rect.width),int(rect.height))):return false
	var anchor=Rect2i(int(rect.x),int(rect.y),int(rect.width),int(rect.height))
	if anchor.size.x<=0 or anchor.size.y<=0:return false
	var moved_to_target=park_near(anchor)
	if moved_to_target:target_location_key=key
	return moved_to_target
func park_near(anchor):
	if not auto_move or dragging or app.paused or reduced_motion or not visible:return false
	var target_screen=DisplayServer.get_screen_from_rect(anchor)
	var bounds=DisplayServer.screen_get_usable_rect(target_screen if target_screen>=0 else current_screen)
	var destination=Behavior.beside(anchor,bounds,size,position)
	return walk_to(destination)
func return_home():
	if not auto_move or dragging or app.paused or reduced_motion or not visible:return false
	return walk_to(bounded(home_position))
func walk_to(destination):
	if dragging or not visible or app.paused or not art:return false
	var target=bounded(destination)
	if Vector2(target).distance_to(Vector2(position))<8:return false
	if effect_kind=="walk" and target==target_position:return false
	_cancel_travel()
	original_position=position;target_position=target
	if reduced_motion:position=target_position;return true
	if not locomotion.start(position,target_position,180.0*user_scale):return false
	effect_kind="walk";phase=0
	walk_duration=locomotion.travel_seconds+locomotion.anticipation
	art.play("turn");return true

func _cancel_travel():
	locomotion.cancel()
	if is_instance_valid(art):
		art.clear_locomotion()
		art.modulate.a=1.0
	effect_kind="";effect_time=0
	reaction_clip="";reaction_left=0;reaction_priority=0

func _release_drag():
	var was_dragging=dragging
	dragging=false
	Input.use_accumulated_input=true
	if was_dragging and is_instance_valid(art):
		position=bounded(position)
		home_position=position
		perform_gesture("settle",0.65,2)

func perform_gesture(id,seconds=1.4,priority=1):
	if not is_instance_valid(art) or reduced_motion or app.paused or dragging or not visible:return false
	if id not in Rig.CLIPS or not is_finite(seconds) or seconds<=0:return false
	if reaction_left>0 and priority<reaction_priority:return false
	reaction_clip=id;reaction_left=clampf(seconds,0.2,8.0);reaction_priority=priority
	_sync_pose()
	return true

func _sync_pose():
	if not is_instance_valid(art) or dragging or reduced_motion or effect_kind in ["walk","edge_enter","dash","spawn"]:return
	var next=Behavior.activity(app)
	if next!=activity_key:
		activity_key=next
		if next in ["scan","read","wait"]:pulse("scan" if next!="wait" else "wait")
	var desired=next
	# Real work/listening takes precedence; short reactions never strand a busy pose.
	if next=="idle" and reaction_left>0:desired=reaction_clip
	if art.clip!=desired:art.play(desired)

func pulse(kind):
	if reduced_motion or app.paused:return
	fx_kind=kind;fx_time=0.85
	canvas.queue_redraw()
func walk_random():
	if dragging or not visible or app.paused:return
	var distance=randf_range(80,160)*(1 if randf()>0.5 else -1)
	walk_to(position+Vector2i(int(distance),0))
func react(event_id):
	if not art or reduced_motion:return false
	if event_id=="dialogue.think_loop":return perform_gesture("thinking",1.0)
	elif event_id=="dialogue.explain_small":return perform_gesture("talk",2.8)
	elif event_id in ["work.note_saved","work.timer_notice"]:
		pulse("success");return perform_gesture("celebrate",1.4,2)
	elif event_id in ["work.error_recover","work.model_missing"]:return perform_gesture("error",1.8,3)
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
