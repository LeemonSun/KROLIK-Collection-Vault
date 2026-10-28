extends Window
const V=preload("res://src/ui/visual_theme.gd")
var app
var engine=preload("res://src/tools/text_patch.gd").new()
var path=""
var token=""
var find_edit
var replace_edit
var preview
var apply_button
var undo_button
var caption
func _init():
	visible=false;borderless=true;size=Vector2i(640,500);min_size=Vector2i(400,420);disable_3d=true
func _ready():
	app=get_tree().root.get_node("App");title="Leemon — file"
	var panel=preload("res://src/ui/signal_surface.gd").new();panel.theme=V.make();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(panel)
	var layout=VBoxContainer.new();layout.add_theme_constant_override("separation",10);panel.add_child(layout)
	var header=preload("res://src/ui/window_handle.gd").new();layout.add_child(header)
	var heading=Label.new();heading.text=app.t("file_patch_title");heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(heading)
	var close=Button.new();close.text="×";close.pressed.connect(dismiss);header.add_child(close)
	caption=Label.new();caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;caption.add_theme_color_override("font_color",V.RED);layout.add_child(caption)
	var row=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(row)
	for i in range(2):
		var column=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(column)
		var label=Label.new();label.text=app.t("file_patch_find" if i==0 else "file_patch_replace");column.add_child(label)
		var edit=TextEdit.new();edit.custom_minimum_size=Vector2(120,70);edit.size_flags_vertical=Control.SIZE_EXPAND_FILL;edit.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;column.add_child(edit)
		edit.text_changed.connect(func():token="";engine.cancel();apply_button.disabled=true)
		if i==0:find_edit=edit
		else:replace_edit=edit
	preview=TextEdit.new();preview.editable=false;preview.add_theme_color_override("font_readonly_color",V.TEXT);preview.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;preview.custom_minimum_size.y=112;preview.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(preview)
	var footer=HBoxContainer.new();layout.add_child(footer)
	for i in range(3):
		var button=Button.new();button.text=app.t(["file_patch_review","file_patch_apply","file_patch_undo"][i]);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.clip_text=true;footer.add_child(button)
		button.pressed.connect([review,apply,restore][i])
		if i==1:apply_button=button;V.primary(button);button.disabled=true
		if i==2:undo_button=button;button.disabled=true
	close_requested.connect(dismiss)
func open_path(selected):
	engine.cancel();token="";path=selected;engine.load_backup(path);caption.text=selected.get_file();caption.tooltip_text=selected
	find_edit.clear();replace_edit.clear();preview.text=app.t("file_patch_hint");apply_button.disabled=true;undo_button.disabled=engine.last_backup.is_empty() or engine.last_backup.get("path")!=path
	var bounds=DisplayServer.screen_get_usable_rect()
	size=Vector2i(mini(640,bounds.size.x),mini(500,bounds.size.y));position=bounds.position+(bounds.size-size)/2
	show();grab_focus()
func revoke():
	engine.cancel();token=""
	if is_instance_valid(apply_button):apply_button.disabled=true
func review():
	if app.paused:revoke();return
	var result=engine.prepare(path,find_edit.text,replace_edit.text)
	_show_plan(result)
func _show_plan(result):
	apply_button.disabled=not result.get("ok",false);token=result.get("token","")
	if not result.get("ok",false):preview.text=app.t("file_patch_error",{"reason":app.t("file_status_"+str(result.get("status","failed")))});return
	preview.text=app.t("file_patch_preview",{"line":result.line})+"\n\n− "+result.before+"\n\n+ "+result.after
func apply():
	if app.paused:revoke();return
	var result=engine.commit(token);token="";apply_button.disabled=true
	preview.text=app.t("file_patch_written") if result.get("ok",false) else app.t("file_patch_error",{"reason":app.t("file_status_"+str(result.get("status","failed")))})
	undo_button.disabled=engine.last_backup.is_empty() or engine.last_backup.get("path")!=path
	if result.get("ok",false):app.add_message("assistant",app.t("file_patch_receipt",{"name":path.get_file()}),true);app.request_motion("work.note_saved")
func restore():
	if app.paused:revoke();return
	if engine.last_backup.get("path")!=path:return
	_show_plan(engine.prepare_restore())
func dismiss():
	engine.cancel();token="";find_edit.clear();replace_edit.clear();preview.clear();hide()
