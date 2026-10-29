extends Window
## Non-modal, bounded notification near Leemon. Full text remains in the chat.
const V=preload("res://src/ui/visual_theme.gd")
const Behavior=preload("res://src/desktop/companion_behavior.gd")
var body
var life
var app
var transition
var follow_elapsed=0.0
func _init():
	visible=false;borderless=true;unresizable=true;unfocusable=true;transparent=true;transparent_bg=true
	transient=true;always_on_top=false;mouse_passthrough=true
	disable_3d=true;size=Vector2i(300,160)
func _ready():
	set_process(false)
	app=get_tree().root.get_node("App");title="Leemon — reply"
	var panel=PanelContainer.new();panel.theme=V.make()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style=V.box(V.PANEL,22,16);style.border_width_left=2;style.border_color=V.RED
	panel.add_theme_stylebox_override("panel",style);add_child(panel)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",7);panel.add_child(column)
	var heading=Label.new();heading.text="Leemon";heading.add_theme_color_override("font_color",V.RED);heading.add_theme_font_size_override("font_size",12);column.add_child(heading)
	body=Label.new();body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size",14);body.max_lines_visible=5
	body.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(body)
	life=Timer.new();life.one_shot=true;life.timeout.connect(dismiss);add_child(life)
func say(text,anchor):
	if app.paused or not app.store.data.settings.get("speech_bubbles",true):return false
	_reposition(anchor)
	follow_elapsed=0
	set_process(true)
	body.text=text.strip_edges().left(190)+( "…" if text.length()>190 else "")
	if transition:transition.kill()
	get_child(0).modulate.a=1;show()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,get_window_id())
	if not app.motion.reduced_motion:
		get_child(0).modulate.a=0.3
		transition=create_tween();transition.tween_property(get_child(0),"modulate:a",1.0,0.18)
	life.start(clampf(text.length()/14.0+2,4,12));return true

func _reposition(anchor):
	var screen=DisplayServer.get_screen_from_rect(anchor)
	if screen<0:screen=DisplayServer.get_primary_screen()
	var bounds=DisplayServer.screen_get_usable_rect(screen)
	size=Vector2i(mini(300,bounds.size.x),mini(160,bounds.size.y))
	var next=Behavior.bubble_position(anchor,bounds,size)
	if next!=position:position=next

func _process(delta):
	if not visible:return
	follow_elapsed+=delta
	if follow_elapsed<0.1:return
	follow_elapsed=0
	if app.paused or not is_instance_valid(app.desktop_companion) or not app.desktop_companion.visible or (is_instance_valid(app.chat_window) and app.chat_window.visible):
		dismiss();return
	_reposition(Rect2i(app.desktop_companion.position,app.desktop_companion.size))

func dismiss():
	set_process(false)
	if transition:transition.kill()
	if is_instance_valid(life):life.stop()
	hide()
	if is_instance_valid(body):body.text=""
