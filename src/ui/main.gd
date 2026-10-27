extends Control
const Companion = preload("res://src/ui/companion.gd")
var page = "talk"
var content
var chat_log
var input
var locale_picker
var profile_picker
var developer_toggle
var state_label
var timer_label
var pause_button
var confirm
var booted = false

func _ready():
	_apply_theme()
	App.changed.connect(_refresh)
	App.message_added.connect(_on_message)
	_build()
	if App.messages.is_empty():
		App.add_message("assistant", App.t("welcome"))
	booted = true
	# A UI-only self-test can traverse every page without a display.
	if "--ui-smoke" in OS.get_cmdline_user_args():
		_ui_smoke.call_deferred()

func _apply_theme():
	var theme = Theme.new()
	theme.default_font_size = 16
	for type in ["Label", "Button", "CheckButton", "OptionButton", "LineEdit", "RichTextLabel"]:
		theme.set_color("font_color", type, Color("#e9e6df"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("#26333c") if state in ["hover","pressed"] else Color("#1b222c")
		style.set_corner_radius_all(10)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 11
		style.content_margin_bottom = 11
		if state == "focus":
			style.set_border_width_all(1)
			style.border_color = Color("#89c9c0")
		theme.set_stylebox(state, "Button", style)
		theme.set_stylebox(state, "OptionButton", style)
	var field = StyleBoxFlat.new()
	field.bg_color = Color("#202b36")
	field.set_corner_radius_all(10)
	field.content_margin_left = 14
	field.content_margin_right = 14
	field.content_margin_top = 12
	field.content_margin_bottom = 12
	theme.set_stylebox("normal", "LineEdit", field)
	self.theme = theme

func _label(text, parent, font_size = 16, dim = false):
	var node = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	if dim:
		node.add_theme_color_override("font_color", Color("#93a1ad"))
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(node)
	return node

func _button(text, parent, callback):
	var node = Button.new()
	node.text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func _build():
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var shell = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 22)
	margin.add_child(shell)
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	shell.add_child(header)
	var title = _label(App.t("app_title"), header, 29)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(App.t("foundation"), header, 14, true)
	_label("● " + App.t("offline"), header, 14, true)
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 26)
	shell.add_child(body)
	var nav = VBoxContainer.new()
	nav.custom_minimum_size.x = 165
	nav.add_theme_constant_override("separation", 10)
	body.add_child(nav)
	for id in ["talk", "notes", "character", "search", "modules", "settings"]:
		_button(App.t(id), nav, func(): page = id; _build())
	var space = Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(space)
	pause_button = _button(App.t("resume" if App.paused else "pause"), nav, func(): App.set_paused(not App.paused))
	_button(App.t("stop"), nav, func(): App.cancel())
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	var side = VBoxContainer.new()
	side.custom_minimum_size.x = 240
	side.add_theme_constant_override("separation", 16)
	body.add_child(side)
	if page != "character":
		var character = Companion.new()
		side.add_child(character)
	state_label = _label(_state_text(), side, 22)
	_label(App.t("character_hint"), side, 14, true)
	timer_label = _label(App.t("active_timers", {"count": App.timers.size()}), side, 14, true)
	_label(App.t("selected_profile", {"name": App.t(App.profile_name)}), side, 14, true)
	_label(App.t("privacy_hint"), side, 13, true)
	if not App.persistence_ready:
		_label(App.t("storage_warning"), shell, 13)
	_label(App.t("foundation_notice"), shell, 13, true)
	chat_log = null
	if page == "talk":
		_build_talk()
	elif page == "notes":
		_build_notes()
	elif page == "modules":
		_build_modules()
	elif page == "character":
		_build_character()
	elif page == "search":
		_build_search()
	else:
		_build_settings()

func _build_character():
	_label(App.t("character_reference"), content, 22)
	_label(App.t("character_stage_hint"), content, 14, true)
	var art = Image.new()
	var result = art.load("res://characters/signal_01/art/master_v1.png")
	if result == OK:
		var preview = TextureRect.new()
		preview.texture = ImageTexture.create_from_image(art)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview.custom_minimum_size = Vector2(320, 200)
		content.add_child(preview)
	else:
		_label(App.t("character_art_missing"), content, 14, true)
	var stats = App.motion.summary()
	_label(App.t("character_clip_status", {"planned": stats.planned_events, "ready": stats.installed_clips}), content, 14, true)
	_label(App.t("character_motion_hint"), content, 13, true)

func _build_search():
	_label(App.t("search"), content, 22)
	_label(App.t("search_hint"), content, 15, true)
	var field = LineEdit.new()
	field.max_length = 512
	field.placeholder_text = App.t("search_placeholder")
	content.add_child(field)
	var run = func():
		App.submit("/search " + field.text)
		page = "talk"
		_build()
	field.text_submitted.connect(func(_value): run.call())
	_button(App.t("search_open"), content, run)
	_label(App.t("search_intelligence_status"), content, 14, true)

func _build_talk():
	_label(App.t("talk"), content, 22)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = false
	chat_log.scroll_following = true
	chat_log.selection_enabled = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.add_theme_constant_override("line_separation", 8)
	content.add_child(chat_log)
	_render_messages()
	var row = HBoxContainer.new()
	content.add_child(row)
	input = LineEdit.new()
	input.placeholder_text = App.t("input_hint")
	input.max_length = 2048
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(_send)
	row.add_child(input)
	_button(App.t("send"), row, func(): _send(input.text))
	_button(App.t("clear_chat"), content, func():
		App.cancel()
		App.messages.clear()
		App.session_turns.clear()
		App.add_message("assistant", App.t("empty_chat"))
		_render_messages())
	_label(App.t("session_hint"), content, 12, true)

func _build_notes():
	_label(App.t("title_notes"), content, 22)
	_label(App.t("notes_heading"), content, 14, true)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18)
	scroll.add_child(list)
	if App.store.data.notes.is_empty():
		_label(App.t("notes_empty"), list, 16, true)
	for note in App.store.data.notes:
		_label("• " + note.text, list)
	var button = _button(App.t("clear_notes"), content, _confirm_clear)
	button.disabled = App.store.data.notes.is_empty() or not App.persistence_ready

func _build_modules():
	_label(App.t("modules"), content, 22)
	_label(App.t("page_modules_hint"), content, 14, true)
	for id in ["notes","timers","llm","asr","tts","screen","ocr","automation","steam"]:
		var row = HBoxContainer.new()
		content.add_child(row)
		var name_label = _label(App.t("module_" + id), row, 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(App.t("module_ready" if id in ["notes","timers"] else "module_pending"), row, 13, true)

func _build_settings():
	_label(App.t("settings"), content, 22)
	_label(App.t("language"), content)
	locale_picker = OptionButton.new()
	for name in ["Русский", "English", "简体中文"]:
		locale_picker.add_item(name)
	locale_picker.select(["ru","en","zh-Hans"].find(App.l10n.locale))
	content.add_child(locale_picker)
	locale_picker.item_selected.connect(func(index): App.set_locale(["ru","en","zh-Hans"][index]); _build())
	_label(App.t("profile"), content)
	profile_picker = OptionButton.new()
	var names = ["auto","lite","balanced","quality"]
	for name in names:
		profile_picker.add_item(App.t(name))
	profile_picker.select(names.find(App.profile_request))
	content.add_child(profile_picker)
	profile_picker.item_selected.connect(func(index): App.set_profile(names[index]); _build())
	_label(App.t("settings_hint"), content, 13, true)
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 24
	content.add_child(spacer)
	developer_toggle = CheckButton.new()
	developer_toggle.text = App.t("dev_mode")
	developer_toggle.button_pressed = App.provider_name == "llama_loopback"
	developer_toggle.toggled.connect(func(enabled): App.enable_developer_llama(enabled))
	content.add_child(developer_toggle)
	_label(App.t("dev_hint"), content, 13, true)

func _send(text):
	if text.strip_edges().is_empty():
		return
	input.clear()
	App.submit(text)

func _render_messages():
	if not is_instance_valid(chat_log):
		return
	chat_log.clear()
	for item in App.messages:
		chat_log.add_text(("› " if item.speaker == "user" else "● ") + item.text + "\n\n")

func _on_message(_speaker, _text):
	_render_messages()
	if booted and page == "notes":
		_build()

func _state_text():
	return App.t("state_paused" if App.paused else "state_" + App.state.current)

func _refresh():
	if is_instance_valid(state_label):
		state_label.text = _state_text()
	if is_instance_valid(timer_label):
		timer_label.text = App.t("active_timers", {"count": App.timers.size()})
	if is_instance_valid(pause_button):
		pause_button.text = App.t("resume" if App.paused else "pause")

func _confirm_clear():
	confirm = ConfirmationDialog.new()
	confirm.title = App.t("clear_notes")
	confirm.dialog_text = App.t("confirm_clear", {"count": App.store.data.notes.size()})
	confirm.ok_button_text = App.t("delete")
	confirm.cancel_button_text = App.t("cancel")
	add_child(confirm)
	confirm.confirmed.connect(func():
		App.clear_notes_confirmed()
		_build())
	confirm.popup_centered(Vector2i(440,180))

func _ui_smoke():
	for language in ["ru","en","zh-Hans"]:
		App.l10n.set_locale(language)
		for id in ["talk","notes","character","search","modules","settings"]:
			page = id
			_build()
			await get_tree().process_frame
	print("UI_SMOKE_OK: 3 locales, 6 pages")
	get_tree().quit()

