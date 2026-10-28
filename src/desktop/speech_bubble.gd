extends Window
## Non-modal, bounded notification near Leemon. Full text remains in the chat.
const V=preload("res://src/ui/visual_theme.gd")
var body
var life
var app
var transition
func _init():
	visible=false;borderless=true;unresizable=true;unfocusable=true
	transient=true;always_on_top=false;mouse_passthrough=true
	disable_3d=true;size=Vector2i(300,160)
func _ready():
	app=get_tree().root.get_node("App");title="Leemon — reply"
	var panel=PanelContainer.new();panel.theme=V.make()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style=V.box(V.PANEL,14,14);style.border_width_left=2;style.border_color=V.RED
	panel.add_theme_stylebox_override("panel",style);add_child(panel)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",7);panel.add_child(column)
	var heading=Label.new();heading.text="LEEMON";heading.add_theme_color_override("font_color",V.RED);heading.add_theme_font_size_override("font_size",10);column.add_child(heading)
	body=Label.new();body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size",14);body.max_lines_visible=5
	body.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(body)
	life=Timer.new();life.one_shot=true;life.timeout.connect(dismiss);add_child(life)
func say(text,anchor):
	if app.paused or not app.store.data.settings.get("speech_bubbles",true):return false
	var screen=DisplayServer.get_screen_from_rect(anchor)
	if screen<0:screen=DisplayServer.get_primary_screen()
	var bounds=DisplayServer.screen_get_usable_rect(screen)
	size=Vector2i(mini(300,bounds.size.x),mini(160,bounds.size.y))
	var left=anchor.position.x-size.x-10
	if left<bounds.position.x:left=anchor.end.x+10
	position=Vector2i(clampi(left,bounds.position.x,maxi(bounds.position.x,bounds.end.x-size.x)),clampi(anchor.position.y-24,bounds.position.y,maxi(bounds.position.y,bounds.end.y-size.y)))
	body.text=text.strip_edges().left(190)+( "…" if text.length()>190 else "")
	if transition:transition.kill()
	get_child(0).modulate.a=1;show()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,get_window_id())
	if not app.motion.reduced_motion:
		get_child(0).modulate.a=0.3
		transition=create_tween();transition.tween_property(get_child(0),"modulate:a",1.0,0.18)
	life.start(clampf(text.length()/14.0+2,4,12));return true
func dismiss():
	if transition:transition.kill()
	if is_instance_valid(life):life.stop()
	hide()
	if is_instance_valid(body):body.text=""
