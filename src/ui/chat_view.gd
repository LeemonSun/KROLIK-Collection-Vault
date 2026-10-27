extends PanelContainer
## History is the only expanding region; input and actions remain within the panel.
signal close_requested
signal settings_requested
const VisualTheme = preload("res://src/ui/visual_theme.gd")
var app
var history
var editor
var send_button
var stop_button
var setup_button
var status_label
var settings_button
var close_button
var last_locale = ""
func _ready():
	app = get_tree().root.get_node("App")
	theme = VisualTheme.make()
	var box = StyleBoxFlat.new()
	box.bg_color = Color("#19151f")
	box.set_corner_radius_all(14)
	box.set_border_width_all(1)
	box.border_color = Color("#70344c")
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	add_theme_stylebox_override("panel",box)
	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation",8)
	add_child(layout)
	var header = HBoxContainer.new()
	layout.add_child(header)
	var title = Label.new()
	title.text = "Signal 01"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	settings_button = _button("",header,func(): settings_requested.emit())
	close_button = _button("×",header,func(): close_requested.emit())
	status_label = Label.new()
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_font_size_override("font_size",12)
	status_label.add_theme_color_override("font_color",Color("#c6b6c8"))
	layout.add_child(status_label)
	history = RichTextLabel.new()
	history.bbcode_enabled = false
	history.selection_enabled = true
	history.scroll_active = true
	history.scroll_following = true
	history.fit_content = false
	history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history.custom_minimum_size.y = 24
	history.add_theme_constant_override("line_separation",5)
	layout.add_child(history)
	editor = TextEdit.new()
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.custom_minimum_size.y = 68
	editor.scroll_fit_content_height = false
	editor.caret_blink = true
	editor.gui_input.connect(_editor_input)
	layout.add_child(editor)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation",8)
	layout.add_child(actions)
	send_button = _button("",actions,submit_current)
	send_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_button = _button("",actions,func(): app.cancel())
	setup_button = _button("",actions,_setup_ai)
	app.message_added.connect(_on_message)
	app.changed.connect(refresh)
	_render_history()
	refresh()
func _button(text,parent,callback):
	var button = Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
func _editor_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER] and not event.shift_pressed:
		get_viewport().set_input_as_handled()
		submit_current()
func submit_current():
	var text = editor.text.strip_edges()
	if text.is_empty():
		return
	if text.length()>2048:
		status_label.text = app.t("input_too_long")
		return
	if app.paused or app.state.current!="idle" or not app.queued_chat_text.is_empty():
		status_label.text = app.t("paused_message" if app.paused else "busy_message")
		return
	editor.clear()
	app.submit(text)
	editor.grab_focus()
func _setup_ai():
	if app.local_runtime.installed():
		app.start_local_ai()
	else:
		settings_requested.emit()
func _on_message(_speaker,_text):
	_render_history()
func _render_history():
	history.clear()
	for item in app.messages:
		history.push_color(Color("#ed91a7") if item.speaker=="user" else Color("#f4eaf2"))
		history.add_text((app.t("chat_you") if item.speaker=="user" else "Signal")+"\n")
		history.pop()
		history.add_text(item.text+"\n\n")
func refresh():
	if not is_instance_valid(status_label):
		return
	if last_locale!=app.l10n.locale:
		last_locale=app.l10n.locale
		editor.placeholder_text=app.t("chat_placeholder")
		editor.tooltip_text=app.t("chat_write_hint")
		send_button.text=app.t("send")
		stop_button.text="■"
		stop_button.tooltip_text=app.t("stop")
		setup_button.text="ИИ" if app.l10n.locale=="ru" else "AI"
		setup_button.tooltip_text=app.t("ai_start_short")
		settings_button.text=app.t("settings")
		close_button.tooltip_text=app.t("hide_panel")
		_render_history()
	status_label.text=app.t("state_paused") if app.paused else app.t(app.local_runtime.status)
	send_button.disabled=app.paused or app.state.current!="idle" or not app.queued_chat_text.is_empty()
	stop_button.disabled=app.state.current=="idle" and app.queued_chat_text.is_empty()
	setup_button.visible=not app.local_ai_enabled or not app.local_runtime.installed()
	setup_button.disabled=app.paused or app.local_runtime.downloading or app.local_runtime.hash_thread!=null
