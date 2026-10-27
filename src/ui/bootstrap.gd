extends Node
## Main Window = character; settings and chat are separate native windows.
var panel_window
var main_view
func _ready():
	get_tree().auto_accept_quit=false
	# The main native window will contain the character. It remains recoverable
	# from the Windows taskbar instead of being parked at (-10000,-10000).
	var host=get_tree().root
	host.borderless=true
	host.transparent=true
	host.transparent_bg=true
	host.exclude_from_capture=false
	panel_window=Window.new()
	panel_window.name="ControlPanel"
	panel_window.title="Signal — settings"
	panel_window.size=Vector2i(800,600)
	panel_window.min_size=Vector2i(360,320)
	panel_window.visible=false
	add_child(panel_window)
	main_view=load("res://scenes/main.tscn").instantiate()
	panel_window.add_child(main_view)
