extends PanelContainer
## Real existing installers; labels describe capabilities instead of runtime plumbing.
const V=preload("res://src/ui/visual_theme.gd")
var app
var kind="text"
var status
var action
var progress
var size_label
func _ready():
	app=get_tree().root.get_node("App");add_theme_stylebox_override("panel",V.box(V.PANEL,18,16))
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",9);add_child(column)
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",12);column.add_child(row)
	var icon=TextureRect.new();icon.texture=load("res://assets/ui/"+{"text":"chat","voice":"mic","vision":"screen"}[kind]+".svg");icon.custom_minimum_size=Vector2(26,26);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.modulate=V.RED;row.add_child(icon)
	var title=Label.new();title.text=app.t("orbit_component_"+kind);title.add_theme_font_size_override("font_size",19);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(title)
	var description=Label.new();description.text=app.t("orbit_component_hint_"+kind);description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;description.modulate=V.MUTED;description.add_theme_font_size_override("font_size",13);column.add_child(description)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.add_theme_font_size_override("font_size",12);column.add_child(status)
	progress=ProgressBar.new();progress.custom_minimum_size.y=4;progress.show_percentage=false;progress.max_value=1;progress.add_theme_stylebox_override("background",V.box(V.INK,2,0));progress.add_theme_stylebox_override("fill",V.box(V.RED,2,0));column.add_child(progress)
	var footer=HBoxContainer.new();column.add_child(footer)
	size_label=Label.new();size_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;size_label.add_theme_font_size_override("font_size",11);size_label.modulate=V.MUTED;footer.add_child(size_label)
	action=Button.new();action.custom_minimum_size=Vector2(112,36);action.pressed.connect(activate);V.primary(action);footer.add_child(action)
	var timer=Timer.new();timer.wait_time=0.5;timer.autostart=true;timer.timeout.connect(func():if is_visible_in_tree():refresh());add_child(timer)
	app.changed.connect(refresh);refresh()
func engine():return app.local_runtime if kind=="text" else (app.vision_asset if kind=="vision" else app.speech_input.transcriber)
func refresh():
	if not is_instance_valid(status):return
	var e=engine();var installed=e.installed();var checking=e.hash_thread!=null;var downloading=e.downloading
	var bytes=int(e.manifest.get("bytes",0))
	if kind in ["text","voice"]:bytes=int(e.manifest.get("model",{}).get("bytes",0))+int(e.manifest.get("runtime",{}).get("bytes",0))
	size_label.text=app.t("orbit_download_size",{"size":"%.0f MB" %(float(bytes)/1000000.0)}) if not installed else app.t("orbit_on_device")
	status.text=app.t("orbit_installed" if installed else ("orbit_checking" if checking else ("orbit_downloading" if downloading else "orbit_not_installed")))
	if not installed and not downloading and not checking and ("failed" in e.status or "error" in e.status):status.text=app.t("orbit_download_failed")
	progress.visible=downloading;progress.value=maxf(0,e.progress())
	action.text=app.t("cancel" if downloading and not checking else ("orbit_installed" if installed else "orbit_download"))
	action.disabled=app.paused or installed or checking or e.bundle_managed
func activate():
	var e=engine()
	if app.paused or e.hash_thread!=null or e.bundle_managed or e.installed():return
	if e.downloading:e.cancel_install()
	elif kind=="text":app.install_local_ai()
	elif kind=="voice":app.speech_input.install()
	else:app.vision_asset.install()
	refresh()
