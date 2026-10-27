extends Window
const ChatView=preload("res://src/ui/chat_view.gd")
var app
var view
func _ready():
	app=get_tree().root.get_node("App")
	title="Signal — "+app.t("talk")
	borderless=true
	transparent=true
	transparent_bg=true
	always_on_top=true
	exclude_from_capture=true
	min_size=Vector2i(320,280)
	size=Vector2i(440,440)
	view=ChatView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.close_requested.connect(hide)
	view.settings_requested.connect(func(): app.open_settings("assistant_tools"))
	close_requested.connect(hide)
	window_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			hide())
func open_near(anchor):
	var screen=DisplayServer.get_screen_from_rect(anchor)
	if screen<0:
		screen=DisplayServer.get_primary_screen()
	var bounds=DisplayServer.screen_get_usable_rect(screen)
	size=Vector2i(mini(440,maxi(320,bounds.size.x-24)),mini(440,maxi(280,bounds.size.y-24)))
	var left=anchor.position.x-size.x-12
	if left<bounds.position.x:
		left=anchor.end.x+12
	position=Vector2i(clampi(left,bounds.position.x,maxi(bounds.position.x,bounds.end.x-size.x)),clampi(anchor.end.y-size.y,bounds.position.y,maxi(bounds.position.y,bounds.end.y-size.y)))
	show()
	grab_focus()
	view.editor.grab_focus.call_deferred()
