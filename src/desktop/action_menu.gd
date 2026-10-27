extends Window
signal action(id)
const V=preload('res://src/ui/visual_theme.gd')
const Surface=preload('res://src/ui/signal_surface.gd')
var buttons=[]
var app
var caption
func _ready():
	app=get_tree().root.get_node('App')
	title='Signal — actions'
	borderless=true
	transparent=true
	transparent_bg=true
	always_on_top=true
	unresizable=true
	size=Vector2i(306,264)
	min_size=size
	var panel=Surface.new()
	panel.theme=V.make()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var layout=VBoxContainer.new()
	layout.add_theme_constant_override('separation',12)
	panel.add_child(layout)
	var heading=HBoxContainer.new()
	layout.add_child(heading)
	caption=Label.new()
	caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	caption.add_theme_font_size_override('font_size',18)
	heading.add_child(caption)
	var close=Button.new()
	close.icon=load('res://assets/ui/close.svg')
	close.expand_icon=true
	close.add_theme_constant_override('icon_max_width',16)
	close.pressed.connect(hide)
	V.quiet(close)
	heading.add_child(close)
	var grid=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override('h_separation',8)
	grid.add_theme_constant_override('v_separation',8)
	grid.size_flags_vertical=Control.SIZE_EXPAND_FILL
	layout.add_child(grid)
	for index in range(6):
		var button=Button.new()
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.custom_minimum_size=Vector2(132,48)
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text=true
		button.icon=load('res://assets/ui/'+['chat','settings','dash','pause','hide','quit'][index]+'.svg')
		button.expand_icon=true
		button.add_theme_constant_override('icon_max_width',18)
		button.add_theme_font_size_override('font_size',13)
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		button.pressed.connect(func():hide();action.emit(index))
		grid.add_child(button)
		buttons.append(button)
	V.primary(buttons[0])
	focus_exited.connect(hide)
	window_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:hide())
func open_at(point):
	var keys=['talk','settings','menu_dash','resume' if app.paused else 'pause','menu_hide_short','menu_quit']
	caption.text=app.t('menu_caption')
	for i in range(keys.size()):buttons[i].text=app.t(keys[i])
	var screen=DisplayServer.get_screen_from_rect(Rect2i(point,Vector2i.ONE))
	if screen<0:screen=DisplayServer.get_primary_screen()
	var bounds=DisplayServer.screen_get_usable_rect(screen)
	position=Vector2i(clampi(point.x-24,bounds.position.x,maxi(bounds.position.x,bounds.end.x-size.x)),clampi(point.y-size.y/2,bounds.position.y,maxi(bounds.position.y,bounds.end.y-size.y)))
	show()
	grab_focus()
