extends PanelContainer
const V=preload("res://src/ui/visual_theme.gd")
var app
var picker
var info
var state
var import_button
var setup_button
var reset_button
var test_toggle
var dialog
func _ready():
	app=get_tree().root.get_node("App")
	add_theme_stylebox_override("panel",V.box(V.PANEL,18,16))
	var col=VBoxContainer.new();col.add_theme_constant_override("separation",12);add_child(col)
	var title=Label.new();title.text=app.t("models_title");title.add_theme_font_size_override("font_size",21);col.add_child(title)
	var hint=Label.new();hint.text=app.t("models_hint");hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.modulate=V.MUTED;hint.add_theme_font_size_override("font_size",13);col.add_child(hint)
	picker=OptionButton.new();picker.fit_to_longest_item=false;picker.custom_minimum_size.y=42;picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for spec in app.model_library.catalog:picker.add_item(spec.name)
	picker.item_selected.connect(func(index):
		if not app.select_model(app.model_library.catalog[index].id):state.text=app.t("models_wait")
		refresh())
	col.add_child(picker)
	state=Label.new();state.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;state.modulate=V.RED;state.add_theme_font_size_override("font_size",14);col.add_child(state)
	info=Label.new();info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.add_theme_font_size_override("font_size",12);info.modulate=V.MUTED;col.add_child(info)
	var actions=HFlowContainer.new();actions.add_theme_constant_override("h_separation",8);col.add_child(actions)
	var source=Button.new();source.text=app.t("models_source");source.pressed.connect(func():OS.shell_open(app.model_library.spec(app.model_library.selected).source));actions.add_child(source)
	import_button=Button.new();import_button.text=app.t("models_import");V.primary(import_button);import_button.pressed.connect(_pick);actions.add_child(import_button)
	setup_button=Button.new();setup_button.pressed.connect(func():app.install_local_ai();refresh());actions.add_child(setup_button)
	var download_hint=Label.new();download_hint.text=app.t("models_download_hint");download_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;download_hint.modulate=V.MUTED;download_hint.add_theme_font_size_override("font_size",12);col.add_child(download_hint)
	reset_button=Button.new();reset_button.text=app.t("models_reset");reset_button.pressed.connect(func():app.reset_model_context();refresh());col.add_child(reset_button)
	test_toggle=CheckButton.new();test_toggle.text=app.t("models_test_mode");test_toggle.button_pressed=app.model_test_mode;test_toggle.toggled.connect(app.set_model_test_mode);col.add_child(test_toggle)
	var footer=Label.new();footer.text=app.t("models_fair_hint");footer.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;footer.modulate=V.MUTED;footer.add_theme_font_size_override("font_size",12);col.add_child(footer)
	app.changed.connect(refresh);refresh()
func refresh():
	if not is_instance_valid(state):return
	var library=app.model_library;var runtime=app.local_runtime
	var active=library.spec(library.selected)
	for i in range(library.catalog.size()):
		if library.catalog[i].id==library.selected:picker.select(i)
	var busy=library.thread!=null or runtime.hash_thread!=null or runtime.downloading or runtime.start_verifier!=null
	picker.disabled=busy
	import_button.visible=library.selected!="qwen35_2b";import_button.disabled=busy
	reset_button.disabled=busy
	setup_button.disabled=busy or runtime.bundle_managed
	setup_button.visible=not runtime.runtime_available() or (library.selected=="qwen35_2b" and not runtime.installed())
	setup_button.text=app.t("models_setup_base" if library.selected=="qwen35_2b" else "models_setup_runtime")
	state.text=app.t(library.status) if not library.status.is_empty() else app.t(runtime.status)
	var entry=library.record(library.selected)
	var detail=app.t("models_kind_"+active.kind)+" · "+str(active.license)
	if not entry.is_empty():detail+="\n"+str(entry.file).get_file()+" · %.2f GB" %(float(entry.bytes)/1000000000.0)
	detail+="\n"+app.t("models_vision_base" if library.selected=="qwen35_2b" else "models_vision_off")
	if not app.last_model_result.is_empty():detail+="\n"+app.t("models_last_reply",{"model":app.last_model_result.model,"seconds":"%.2f" %(float(app.last_model_result.elapsed_ms)/1000.0)})
	info.text=detail
func _pick():
	if is_instance_valid(dialog):dialog.queue_free()
	dialog=FileDialog.new();dialog.title=app.t("models_import");dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.access=FileDialog.ACCESS_FILESYSTEM
	dialog.filters=PackedStringArray(["*.gguf ; GGUF"]);dialog.use_native_dialog=true
	var chosen=app.model_library.selected
	dialog.file_selected.connect(func(path):
		if not app.import_model(chosen,path):state.text=app.t("models_wait"))
	add_child(dialog);dialog.popup_centered_ratio(.75)
