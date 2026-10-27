extends Control
const ChatView = preload("res://src/ui/chat_view.gd")
const Handle = preload("res://src/ui/window_handle.gd")
const Surface = preload("res://src/ui/signal_surface.gd")
const VisualTheme = preload("res://src/ui/visual_theme.gd")
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
var ai_status_label
var ai_progress_label
var install_button
var start_ai_button
var stop_ai_button
var cancel_install_button
var screen_preview_window
var embedded_chat
var page_scroll
var page_picker
var wide_layout=false
var responsive_pending=false
var diagnostics_label

func _ready():
	App.control_panel=self
	_apply_theme()
	get_window().size_changed.connect(_window_resized)
	App.settings_requested.connect(open_panel)
	App.changed.connect(_refresh)
	App.message_added.connect(_on_message)
	_build()
	if App.messages.is_empty():
		App.add_message("assistant", App.t("welcome"))
	booted = true
	var refresh_timer = Timer.new()
	refresh_timer.wait_time = 0.5
	refresh_timer.autostart = true
	refresh_timer.timeout.connect(_refresh)
	App.add_child(refresh_timer)
	if DisplayServer.get_name() != "headless" and "--ui-smoke" not in OS.get_cmdline_user_args():
		get_tree().auto_accept_quit = false
		get_window().close_requested.connect(_hide_panel)
		get_window().exclude_from_capture = false
		get_window().hide()
		App.show_desktop.call_deferred()
	# A UI-only self-test can traverse every page without a display.
	if "--ui-smoke" in OS.get_cmdline_user_args():
		_ui_smoke.call_deferred()

func _apply_theme():
	theme = VisualTheme.make()

func _label(text, parent, font_size = 16, dim = false):
	var node = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	if dim:
		node.add_theme_color_override("font_color", VisualTheme.MUTED)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _button(text, parent, callback):
	var node = Button.new()
	node.text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func open_panel(target_page = "assistant_tools"):
	page = target_page
	_build()
	var win = get_window()
	if DisplayServer.get_name() != "headless":
		var bounds = DisplayServer.screen_get_usable_rect(win.current_screen)
		win.size = Vector2i(mini(800,bounds.size.x-24),mini(620,bounds.size.y-48))
		win.position = bounds.position+(bounds.size-win.size)/2
		win.always_on_top = true
	win.show()
	win.grab_focus()
	if not App.motion.reduced_motion and not App.paused:
		modulate.a=0
		create_tween().tween_property(self,"modulate:a",1.0,0.16)

func _hide_panel():
	get_window().hide()
	App.show_desktop()

func _window_resized():
	if not is_inside_tree() or get_window()==null:return
	if (get_window().size.x>=700 and get_window().size.y>=540)!=wide_layout and not responsive_pending:
		responsive_pending=true
		_reflow.call_deferred()

func _reflow():
	if not is_inside_tree() or get_window()==null:return
	responsive_pending=false
	_build()

func _build():
	var saved_draft=embedded_chat.editor.text if is_instance_valid(embedded_chat) else ""
	wide_layout=get_window().size.x>=700 and get_window().size.y>=540
	ai_status_label = null
	ai_progress_label = null
	install_button = null
	start_ai_button = null
	stop_ai_button = null
	cancel_install_button = null
	chat_log = null
	embedded_chat = null
	page_scroll = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var background=Surface.new()
	background.inset=0
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+edge,18)
	add_child(margin)
	var workspace=HBoxContainer.new()
	workspace.add_theme_constant_override("separation",24)
	margin.add_child(workspace)
	if wide_layout:
		_build_sidebar(workspace)
	var shell = VBoxContainer.new()
	shell.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("separation",10)
	workspace.add_child(shell)
	var header = Handle.new()
	header.add_theme_constant_override("separation",8)
	shell.add_child(header)
	if not wide_layout:
		var mark=TextureRect.new()
		mark.texture=load("res://assets/ui/mark.svg")
		mark.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size=Vector2(26,26)
		mark.modulate=VisualTheme.RED
		mark.mouse_filter=Control.MOUSE_FILTER_IGNORE
		header.add_child(mark)
	page_picker = OptionButton.new()
	page_picker.fit_to_longest_item = false
	page_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var pages = ["talk","assistant_tools","settings","character","search","notes","modules","diagnostics","reminders"]
	for id in pages:
		page_picker.add_item(App.t(id))
	page_picker.select(maxi(0,pages.find(page)))
	page_picker.item_selected.connect(func(index): page = pages[index]; _build())
	header.add_child(page_picker)
	page_picker.visible=not wide_layout
	if wide_layout:
		var section=_label(App.t(page),header,13,true)
		section.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button("×",header,_hide_panel).tooltip_text = App.t("hide_panel")
	if page == "talk":
		embedded_chat = ChatView.new()
		embedded_chat.embedded=true
		embedded_chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
		embedded_chat.close_requested.connect(_hide_panel)
		embedded_chat.settings_requested.connect(func(): open_panel("assistant_tools"))
		shell.add_child(embedded_chat)
		embedded_chat.editor.text=saved_draft
		return
	page_scroll = ScrollContainer.new()
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(page_scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.add_child(content)
	if page=="reminders":
		_build_reminders()
	elif page=="diagnostics":
		_label(App.t("diagnostics"),content,22)
		_label(App.t("diagnostics_hint"),content,13,true)
		diagnostics_label=_label(App.diagnostics.report(),content,15)
		_button(App.t("copy"),content,func():DisplayServer.clipboard_set(App.diagnostics.report()))
	elif page == "notes":
		_build_notes()
	elif page == "modules":
		_build_modules()
	elif page == "assistant_tools":
		_build_assistant_tools()
	elif page == "character":
		_build_character()
	elif page == "search":
		_build_search()
	else:
		_build_settings()

func _build_sidebar(parent):
	var sidebar=VBoxContainer.new()
	sidebar.custom_minimum_size.x=192
	sidebar.add_theme_constant_override("separation",6)
	parent.add_child(sidebar)
	var identity=HBoxContainer.new()
	identity.custom_minimum_size.y=54
	sidebar.add_child(identity)
	var glyph=TextureRect.new()
	glyph.texture=load("res://assets/ui/mark.svg")
	glyph.custom_minimum_size=Vector2(32,32)
	glyph.modulate=VisualTheme.RED
	glyph.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity.add_child(glyph)
	var brand=_label("LEEMON",identity,21)
	brand.autowrap_mode=TextServer.AUTOWRAP_OFF
	brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for id in ["talk","assistant_tools","character","notes","search","settings","modules","diagnostics","reminders"]:
		var target=id
		var button=_button(App.t(id),sidebar,func():page=target;_build())
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text=true
		button.custom_minimum_size.y=40
		button.icon=load("res://assets/ui/"+{"talk":"chat","assistant_tools":"cpu","character":"character","notes":"note","search":"search","settings":"settings","modules":"cpu","diagnostics":"cpu","reminders":"clock"}[id]+".svg")
		button.expand_icon=true
		button.add_theme_constant_override("icon_max_width",17)
		if page==id:VisualTheme.primary(button)
		else:VisualTheme.quiet(button)
	var space=Control.new()
	space.size_flags_vertical=Control.SIZE_EXPAND_FILL
	sidebar.add_child(space)
	_label(App.t("signal_tagline"),sidebar,12,true)
	_label(App.t("offline"),sidebar,11,true)

func _build_character():
	_label("Leemon",content,26)
	_label(App.t("signal_tagline"),content,14,true)
	var art=load("res://assets/characters/leemon_01/master_v1.png")
	if art is Texture2D:
		var preview=TextureRect.new()
		preview.texture=art
		preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		preview.size_flags_vertical=Control.SIZE_EXPAND_FILL
		preview.custom_minimum_size=Vector2(240,320)
		content.add_child(preview)
	else:
		_label(App.t("character_art_missing"),content,14,true)
	var row=HBoxContainer.new()
	content.add_child(row)
	var show_button=_button(App.t("show_desktop"),row,func():App.show_desktop())
	show_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	VisualTheme.primary(show_button)
	var dash_button=_button(App.t("menu_dash"),row,func():
		if App.show_desktop():App.desktop_companion.walk_random())
	dash_button.icon=load("res://assets/ui/dash.svg")
	dash_button.expand_icon=true
	dash_button.add_theme_constant_override("icon_max_width",16)
	_label(App.t("character_controls_short"),content,12,true)

func _build_assistant_tools():
	_label(App.t("assistant_tools"), content, 22)
	ai_status_label = _label(App.t(App.local_runtime.status), content, 17)
	ai_progress_label = _label("", content, 14, true)
	_label(App.t("ai_install_hint"), content, 14, true)
	_label(App.t("clipboard_hint"),content,13,true)
	install_button = _button(App.t("ai_install"), content, func(): App.install_local_ai(); _refresh())
	VisualTheme.primary(install_button)
	start_ai_button = _button(App.t("ai_start"), content, func(): App.start_local_ai(); _refresh())
	stop_ai_button = _button(App.t("ai_stop"), content, func(): App.stop_local_ai(); _refresh())
	cancel_install_button = _button(App.t("ai_cancel_download"), content, func(): App.local_runtime.cancel_install(); _refresh())
	_label(App.t("ai_scope_hint"), content, 13, true)
	var voice_toggle = CheckButton.new()
	voice_toggle.text = App.t("system_voice")
	voice_toggle.button_pressed = App.voice.enabled
	voice_toggle.toggled.connect(func(value): App.voice.enabled = value; App.voice.stop())
	content.add_child(voice_toggle)
	_label(App.t("system_voice_hint"), content, 13, true)
	_button(App.t("capture_once"), content, _capture_once)
	_label(App.t("capture_hint"), content, 13, true)
	var move_toggle = CheckButton.new()
	move_toggle.text = App.t("auto_move")
	move_toggle.button_pressed = is_instance_valid(App.desktop_companion) and App.desktop_companion.auto_move
	move_toggle.toggled.connect(func(value):
		if App.show_desktop():
			App.desktop_companion.auto_move = value)
	content.add_child(move_toggle)
	var reduced_toggle = CheckButton.new()
	reduced_toggle.text = App.t("reduced_motion")
	reduced_toggle.button_pressed=App.motion.reduced_motion
	reduced_toggle.toggled.connect(func(value):
		App.motion.set_reduced_motion(value)
		if App.show_desktop():
			App.desktop_companion.set_reduced(value))
	content.add_child(reduced_toggle)
	_label(App.t("desktop_controls"), content, 13, true)
	_refresh()

func _capture_once():
	if App.paused or DisplayServer.get_name() == "headless":
		return
	var image = DisplayServer.screen_get_image(get_window().current_screen)
	if image == null or image.is_empty():
		App.add_message("assistant", App.t("capture_failed"))
		return
	if is_instance_valid(screen_preview_window):
		screen_preview_window.queue_free()
	screen_preview_window = Window.new()
	screen_preview_window.title = App.t("capture_once")
	screen_preview_window.size = Vector2i(900, 600)
	screen_preview_window.exclude_from_capture = true
	add_child(screen_preview_window)
	var layout = VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_preview_window.add_child(layout)
	var view = TextureRect.new()
	view.texture = ImageTexture.create_from_image(image)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(view)
	_label(App.t("capture_hint"), layout, 14, true)
	var owned_preview = screen_preview_window
	owned_preview.close_requested.connect(func(): owned_preview.queue_free())
	screen_preview_window.popup_centered()

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


func _build_notes():
	_label(App.t("title_notes"), content, 22)
	_label(App.t("notes_heading"), content, 14, true)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18)
	content.add_child(list)
	if App.store.data.notes.is_empty():
		_label(App.t("notes_empty"), list, 16, true)
	for index in range(App.store.data.notes.size()):
		var row=HBoxContainer.new()
		list.add_child(row)
		var label=_label("• "+App.store.data.notes[index].text,row)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_button(App.t("delete_note"),row,func(): App.store.remove_note(index); _build())
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
		_label(App.t("module_ready" if id in ["notes","timers"] or (id == "llm" and App.local_runtime.status == "ai_ready") else "module_pending"), row, 13, true)

func _build_settings():
	_label(App.t("settings"), content, 22)
	_label(App.t("language"), content)
	locale_picker = OptionButton.new()
	for name in ["Русский", "English", "简体中文"]:
		locale_picker.add_item(name)
	locale_picker.select(["ru","en","zh-Hans"].find(App.l10n.locale))
	content.add_child(locale_picker)
	locale_picker.item_selected.connect(func(index): App.set_locale(["ru","en","zh-Hans"][index]); _build())
	_label(App.t("browser_choice"),content)
	var browser_picker = OptionButton.new()
	for label in [App.t("browser_system"),"Opera","Opera GX"]:
		browser_picker.add_item(label)
	var browser_ids = ["system","opera","opera_gx"]
	browser_picker.select(browser_ids.find(App.browser_search.browser_id))
	browser_picker.item_selected.connect(func(index): App.set_browser(browser_ids[index]))
	content.add_child(browser_picker)
	_label(App.t("browser_hint"),content,13,true)
	_label(App.t("profile"), content)
	profile_picker = OptionButton.new()
	var names = ["auto","lite","balanced","quality"]
	for name in names:
		profile_picker.add_item(App.t(name))
	profile_picker.select(names.find(App.profile_request))
	content.add_child(profile_picker)
	profile_picker.item_selected.connect(func(index): App.set_profile(names[index]); _build())
	_label(App.t("settings_hint"), content, 13, true)
	var history=CheckButton.new()
	history.text=App.t("save_chat")
	history.button_pressed=App.history_enabled()
	history.toggled.connect(App.set_history_enabled)
	content.add_child(history)
	_label(App.t("history_hint"),content,13,true)
	_button(App.t("clear_chat"),content,_confirm_clear_chat)
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
	if booted and page in ["notes","reminders"]:
		_build()

func _state_text():
	return App.t("state_paused" if App.paused else "state_" + App.state.current)

func _refresh():
	if page=="diagnostics" and is_instance_valid(diagnostics_label):diagnostics_label.text=App.diagnostics.report()
	if is_instance_valid(ai_status_label):
		ai_status_label.text = App.t(App.local_runtime.status)
		var progress = App.local_runtime.progress()
		ai_progress_label.text = ("%d%%" % int(progress * 100)) if progress >= 0 else ""
		var active = App.local_runtime.downloading or App.local_runtime.hash_thread != null or App.local_runtime.starting or App.local_runtime.pid > 0
		install_button.disabled = active or App.paused
		start_ai_button.disabled = active or App.paused or not App.local_runtime.installed()
		stop_ai_button.disabled = App.local_runtime.pid <= 0 and not App.local_runtime.starting
		cancel_install_button.disabled = not App.local_runtime.downloading or App.local_runtime.hash_thread != null
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
		for id in ["talk","notes","character","assistant_tools","search","modules","settings","diagnostics","reminders"]:
			page = id
			_build()
			await get_tree().process_frame
	print("UI_SMOKE_OK: 3 locales, 9 pages")
	get_tree().quit()


func _confirm_clear_chat():
	var dialog=ConfirmationDialog.new()
	dialog.title=App.t("clear_chat")
	dialog.dialog_text=App.t("confirm_clear_chat")
	add_child(dialog)
	dialog.confirmed.connect(func():App.clear_history_confirmed();dialog.queue_free();_build())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(360,150))

func _build_reminders():
	_label(App.t("reminders"),content,22)
	_label(App.t("reminders_hint"),content,13,true)
	var items=App.store.data.get("reminders",[]).duplicate(true)
	items.sort_custom(func(a,b):return a.deadline<b.deadline)
	if items.is_empty():_label(App.t("reminders_empty"),content,15,true)
	for item in items:
		var row=HBoxContainer.new();content.add_child(row)
		var text=App.t("reminder_row",{"text":item.text,"seconds":maxi(0,int(item.deadline)-int(Time.get_unix_time_from_system()))})
		var label=_label(text,row,15);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_button(App.t("reminder_cancel"),row,func():App.cancel_reminder(item.id);_build())
