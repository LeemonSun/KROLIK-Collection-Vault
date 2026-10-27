extends Window
const ChatView=preload("res://src/ui/chat_view.gd")
var app
var view
var transition: Tween
func _ready():
	app=get_tree().root.get_node("App")
	title="Signal — "+app.t("talk")
	borderless=true
	transparent=true
	transparent_bg=true
	always_on_top=true
	exclude_from_capture=false
	min_size=Vector2i(320,280)
	size=Vector2i(460,460)
	view=ChatView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
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
	show()
	if not app.motion.reduced_motion and not app.paused:
		view.modulate.a=0
		transition=create_tween()
		transition.tween_property(view,"modulate:a",1.0,0.16)
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
