extends Window
## Small open orbit. Extra actions stay in a contextual list, not a permanent dashboard.
signal action(id)
const V=preload('res://src/ui/visual_theme.gd')
var buttons=[]
var app
var caption
var canvas
var more
var transition
class Orbit extends Control:
	func _draw():
		draw_arc(Vector2(26,146),112,-1.52,1.05,48,Color('#ad8a3a'),1.5,true)
func _init():
	visible=false;transparent=true;transparent_bg=true;disable_3d=true
func _ready():
	app=get_tree().root.get_node('App');title='Leemon — Orbit'
	borderless=true;always_on_top=true;unresizable=true
	size=Vector2i(218,294);min_size=size
	canvas=Orbit.new();canvas.theme=V.make();canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(canvas)
	caption=Label.new();caption.text='LEEMON';caption.position=Vector2(12,7);caption.add_theme_font_size_override('font_size',11);caption.modulate=V.TEXT;canvas.add_child(caption)
	for i in range(9):
		var button=Button.new();buttons.append(button);canvas.add_child(button)
		button.visible=i in [0,1,7,8];button.size=Vector2(52,52);button.custom_minimum_size=Vector2(52,52)
		button.icon=load('res://assets/ui/'+['chat','settings','dash','pause','hide','quit','note','mic','screen'][i]+'.svg')
		button.expand_icon=true;button.add_theme_constant_override('icon_max_width',21)
		button.add_theme_stylebox_override('normal',V.box(V.PANEL,26,10));button.add_theme_stylebox_override('hover',V.box(V.LAYER,26,10))
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		button.pressed.connect(func():hide();action.emit(i))
	buttons[0].position=Vector2(38,32);buttons[7].position=Vector2(108,71);buttons[8].position=Vector2(123,148);buttons[1].position=Vector2(80,216)
	V.primary(buttons[0]);buttons[0].add_theme_stylebox_override('normal',V.box(V.RED,26,10))
	var extra=Button.new();extra.text='···';extra.position=Vector2(12,238);extra.size=Vector2(42,42);extra.add_theme_stylebox_override('normal',V.box(V.PANEL,21,8));canvas.add_child(extra)
	more=PopupMenu.new();more.theme=V.make();add_child(more)
	more.id_pressed.connect(func(id):hide();action.emit(id))
	extra.pressed.connect(func():more.popup(Rect2i(position+Vector2i(0,110),Vector2i(200,0))))
	focus_exited.connect(func():if not more.visible:hide())
	window_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:hide())
func open_at(point):
	var keys=['talk','settings','menu_dash','resume' if app.paused else 'pause','menu_hide_short','menu_quit','file_patch_title','voice_start','vision_button']
	for i in range(keys.size()):buttons[i].tooltip_text=app.t(keys[i])
	if app.speech_input.state=="recording":buttons[7].tooltip_text=app.t("voice_finish")
	buttons[7].modulate=V.RED if app.speech_input.state=="recording" else Color.WHITE
	more.clear()
	for i in [2,3,4,5,6]:more.add_item(app.t(keys[i]),i)
	var screen=DisplayServer.get_screen_from_rect(Rect2i(point,Vector2i.ONE))
	var bounds=DisplayServer.screen_get_usable_rect(screen if screen>=0 else DisplayServer.get_primary_screen())
	position=Vector2i(clampi(point.x-32,bounds.position.x,maxi(bounds.position.x,bounds.end.x-size.x)),clampi(point.y-145,bounds.position.y,maxi(bounds.position.y,bounds.end.y-size.y)))
	if transition:transition.kill()
	canvas.modulate.a=1;show();app.mark_active();grab_focus()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,get_window_id())
	if not app.motion.reduced_motion and not app.paused:
		canvas.modulate.a=0;transition=create_tween();transition.tween_property(canvas,'modulate:a',1.0,0.16)
