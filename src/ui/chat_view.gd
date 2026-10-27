extends "res://src/ui/signal_surface.gd"
## Input/actions always remain visible. Conversation is the only expanding region.
signal close_requested
signal settings_requested
const VisualTheme=preload('res://src/ui/visual_theme.gd')
const Handle=preload('res://src/ui/window_handle.gd')
var embedded=false
var app
var history
var editor
var send_button
var stop_button
var setup_button
var status_label
var settings_button
var close_button
var last_locale=''
var chips=[]
var footer_hint
var setup_hint
var status_dot
func _ready():
	if embedded:inset=0
	super._ready()
	app=get_tree().root.get_node('App')
	theme=VisualTheme.make()
	var layout=VBoxContainer.new()
	layout.add_theme_constant_override('separation',8)
	add_child(layout)
	var header=Handle.new()
	header.custom_minimum_size.y=34
	layout.add_child(header)
	header.visible=not embedded
	var mark=TextureRect.new()
	mark.texture=load('res://assets/ui/mark.svg')
	mark.custom_minimum_size=Vector2(30,28)
	mark.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.modulate=VisualTheme.RED
	mark.mouse_filter=Control.MOUSE_FILTER_IGNORE
	header.add_child(mark)
	var title=Label.new()
	title.text='L E E M O N'
	title.add_theme_font_size_override('font_size',20)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.mouse_filter=Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	settings_button=_icon('settings',header,func():settings_requested.emit())
	close_button=_icon('close',header,func():close_requested.emit())
	var status_row=HBoxContainer.new()
	layout.add_child(status_row)
	status_dot=Label.new()
	status_dot.text='●'
	status_dot.add_theme_font_size_override('font_size',9)
	status_row.add_child(status_dot)
	status_label=Label.new()
	status_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_font_size_override('font_size',12)
	status_label.add_theme_color_override('font_color',VisualTheme.MUTED)
	status_row.add_child(status_label)
	setup_hint=Label.new()
	setup_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	setup_hint.add_theme_font_size_override('font_size',12)
	setup_hint.add_theme_color_override('font_color',VisualTheme.MUTED)
	layout.add_child(setup_hint)
	history=RichTextLabel.new()
	history.bbcode_enabled=false
	history.selection_enabled=true
	history.scroll_active=true
	history.scroll_following=true
	history.fit_content=false
	history.size_flags_vertical=Control.SIZE_EXPAND_FILL
	history.custom_minimum_size.y=24
	history.add_theme_constant_override('line_separation',5)
	layout.add_child(history)
	var suggestions=HBoxContainer.new()
	suggestions.add_theme_constant_override('separation',6)
	layout.add_child(suggestions)
	for spec in [['clock','quick_timer','/timer 300'],['note','quick_note','/note '],['clock','reminders','/remind 300 '],['search','search','/search ']]:
		var button=_button('',suggestions,func():
			editor.text=spec[2]
			editor.grab_focus()
			editor.set_caret_column(editor.text.length()))
		button.icon=load('res://assets/ui/'+spec[0]+'.svg')
		button.expand_icon=true
		button.add_theme_constant_override('icon_max_width',14)
		button.add_theme_font_size_override('font_size',12)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.clip_text=true
		chips.append({'button':button,'key':spec[1]})
	editor=TextEdit.new()
	editor.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	editor.custom_minimum_size.y=58
	editor.scroll_fit_content_height=false
	editor.caret_blink=true
	editor.mouse_default_cursor_shape=Control.CURSOR_IBEAM
	editor.text_changed.connect(func():
		if is_instance_valid(app.desktop_companion) and is_instance_valid(app.desktop_companion.art) and app.state.current=="idle" and not app.paused and not app.desktop_companion.reduced_motion:
			app.desktop_companion.art.play("listen",1.2))
	editor.gui_input.connect(_editor_input)
	layout.add_child(editor)
	var actions=HBoxContainer.new()
	actions.add_theme_constant_override('separation',6)
	layout.add_child(actions)
	footer_hint=Label.new()
	footer_hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer_hint.add_theme_font_size_override('font_size',10)
	footer_hint.add_theme_color_override('font_color',VisualTheme.MUTED)
	footer_hint.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	actions.add_child(footer_hint)
	setup_button=_button('AI',actions,_setup_ai)
	setup_button.custom_minimum_size.x=144
	setup_button.add_theme_font_size_override('font_size',11)
	setup_button.clip_text=true
	VisualTheme.quiet(setup_button)
	stop_button=_button('■',actions,func():app.cancel())
	VisualTheme.quiet(stop_button)
	send_button=_button('',actions,submit_current)
	send_button.icon=load('res://assets/ui/send.svg')
	send_button.expand_icon=true
	send_button.add_theme_constant_override('icon_max_width',18)
	send_button.custom_minimum_size=Vector2(46,34)
	VisualTheme.primary(send_button)
	app.message_added.connect(_on_message)
	app.history_cleared.connect(_render_history)
	app.changed.connect(refresh)
	_render_history()
	resized.connect(refresh)
	refresh()
func _button(text,parent,callback):
	var button=Button.new()
	button.text=text
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
func _icon(name,parent,callback):
	var button=_button('',parent,callback)
	button.icon=load('res://assets/ui/'+name+'.svg')
	button.expand_icon=true
	button.add_theme_constant_override('icon_max_width',17)
	button.custom_minimum_size=Vector2(32,32)
	VisualTheme.quiet(button)
	return button
func _editor_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER] and not event.shift_pressed:
		get_viewport().set_input_as_handled()
		submit_current()
func submit_current():
	var text=editor.text.strip_edges()
	if text.is_empty():return
	if text.length()>2048:
		status_label.text=app.t('input_too_long')
		return
	if app.paused or app.state.current!='idle' or not app.queued_chat_text.is_empty():
		status_label.text=app.t('paused_message' if app.paused else 'busy_message')
		return
	editor.clear()
	app.submit(text)
	editor.grab_focus()
func _setup_ai():
	if app.local_runtime.installed():app.start_local_ai()
	else:app.install_local_ai()
	refresh()
func _on_message(_speaker,_text):
	_render_history()
func _render_history():
	history.clear()
	for item in app.messages:
		history.push_font_size(11)
		history.push_color(VisualTheme.MUTED if item.speaker=='user' else VisualTheme.RED)
		history.add_text((app.t('chat_you').to_upper() if item.speaker=='user' else 'LEEMON')+'\n')
		history.pop()
		history.pop()
		history.push_color(Color('#c8ccbc') if item.speaker=='user' else VisualTheme.TEXT)
		history.add_text(item.text+'\n\n')
		history.pop()
func refresh():
	if not is_instance_valid(status_label):return
	if last_locale!=app.l10n.locale:
		last_locale=app.l10n.locale
		editor.placeholder_text=app.t('chat_placeholder')
		editor.tooltip_text=app.t('chat_write_hint')
		send_button.tooltip_text=app.t('send')
		stop_button.tooltip_text=app.t('stop')
		setup_button.tooltip_text=app.t('ai_start_short')
		settings_button.tooltip_text=app.t('settings')
		close_button.tooltip_text=app.t('hide_panel')
		footer_hint.text=app.t('composer_keys')
		for chip in chips:chip.button.text=app.t(chip.key)
		_render_history()
	var busy=app.state.current!='idle' or not app.queued_chat_text.is_empty()
	status_label.text=app.t('state_paused') if app.paused else (app.t('state_'+app.state.current) if busy else app.t(app.local_runtime.status))
	status_dot.modulate=VisualTheme.RED if busy else VisualTheme.MUTED
	send_button.disabled=app.paused or busy
	stop_button.disabled=not busy
	var installed=app.local_runtime.installed()
	setup_hint.visible=size.y>=380 and not installed and not app.local_runtime.downloading
	setup_hint.text=app.t('chat_setup_hint')
	setup_button.visible=not installed and not app.local_runtime.downloading
	setup_button.text=app.t('chat_install')
	setup_button.disabled=app.paused or app.local_runtime.downloading or app.local_runtime.hash_thread!=null

func _draw():
	if not embedded:super._draw()
