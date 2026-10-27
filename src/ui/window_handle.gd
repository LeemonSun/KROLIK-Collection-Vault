extends HBoxContainer
## Small native-window drag handle; other controls keep their input.
var held=false
var origin=Vector2i.ZERO
var window_origin=Vector2i.ZERO
func _gui_input(event):
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		held=event.pressed
		origin=DisplayServer.mouse_get_position()
		window_origin=get_window().position
	elif event is InputEventMouseMotion and held:
		get_window().position=window_origin+DisplayServer.mouse_get_position()-origin
