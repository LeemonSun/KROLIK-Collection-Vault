extends Window
const ChatView=preload("res://src/ui/chat_view.gd")
var app
var view
var transition: Tween
func _init():
	visible=false
	borderless=true
	transparent=false
	transparent_bg=false
	always_on_top=true
	min_size=Vector2i(320,280)
	size=Vector2i(460,460)
	disable_3d=true
func _ready():
	app=get_tree().root.get_node("App")
	title="Leemon — "+app.t("talk")
	borderless=true
	transparent=false
	transparent_bg=false
	always_on_top=true
	exclude_from_capture=false
	min_size=Vector2i(320,280)
	size=Vector2i(460,460)
	view=ChatView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,get_window_id())
	view.close_requested.connect(close_soft)
	view.settings_requested.connect(func(): app.open_settings("assistant_tools"))
	close_requested.connect(close_soft)
	window_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			close_soft())
func open_near(anchor):
	var screen=DisplayServer.get_screen_from_rect(anchor)
	if screen<0:
		screen=DisplayServer.get_primary_screen()
	var bounds=DisplayServer.screen_get_usable_rect(screen)
	size=Vector2i(mini(460,maxi(320,bounds.size.x-24)),mini(460,maxi(280,bounds.size.y-24)))
	var left=anchor.position.x-size.x-12
	if left<bounds.position.x:
		left=anchor.end.x+12
	position=Vector2i(clampi(left,bounds.position.x,maxi(bounds.position.x,bounds.end.x-size.x)),clampi(anchor.end.y-size.y,bounds.position.y,maxi(bounds.position.y,bounds.end.y-size.y)))
	if transition:transition.kill()
	view.modulate.a=1.0
	view.position=Vector2.ZERO
	show()
	app.mark_active()
	if not app.motion.reduced_motion and not app.paused:
		view.modulate.a=0.2
		view.position=Vector2(0,12)
		transition=create_tween().set_parallel(true)
		transition.tween_property(view,"modulate:a",1.0,0.2)
		transition.tween_property(view,"position",Vector2.ZERO,0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	grab_focus()
	view.editor.grab_focus.call_deferred()

func close_soft():
	if transition:transition.kill()
	if app.motion.reduced_motion or app.paused:
		hide()
		return
	transition=create_tween()
	transition.tween_property(view,"modulate:a",0.0,0.12)
	transition.tween_callback(hide)
	app.mark_active()
