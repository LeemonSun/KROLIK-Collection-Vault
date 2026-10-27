extends Node
## Godot's main Window cannot be hidden. Keep it empty; all user UI uses native child windows.
var panel_window
var main_view
func _ready():
	get_tree().auto_accept_quit=false
	var host=get_tree().root
	host.min_size=Vector2i.ONE
	host.size=Vector2i.ONE
	host.borderless=true
	host.transparent=true
	host.transparent_bg=true
	host.mouse_passthrough=true
	host.unfocusable=true
	host.exclude_from_capture=true
	if DisplayServer.get_name()!="headless":
		host.position=Vector2i(-10000,-10000)
	host.close_requested.connect(func(): get_tree().quit())
	panel_window=Window.new()
	panel_window.name="ControlPanel"
	panel_window.title="Signal — settings"
	panel_window.size=Vector2i(800,600)
	panel_window.min_size=Vector2i(360,320)
	panel_window.visible=false
	add_child(panel_window)
	main_view=load("res://scenes/main.tscn").instantiate()
	panel_window.add_child(main_view)
