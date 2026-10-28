extends Window
const V=preload("res://src/ui/visual_theme.gd")
var app
var engine=preload("res://src/tools/office_patch.gd").new()
var path=""
var token=""
var find_edit
var replace_edit
var preview
var apply_button
var undo_button
var caption
var address_row
var table_row
var table_column
var sheet_row
var sheet_number
var range_row
var range_end_row
var range_end_column
var value_kind
var read_button
func _init():
	visible=false;borderless=true;size=Vector2i(640,500);min_size=Vector2i(400,420);disable_3d=true
func _ready():
	app=get_tree().root.get_node("App");title="Leemon — file"
	var panel=preload("res://src/ui/leemon_surface.gd").new();panel.theme=V.make();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(panel)
	var layout=VBoxContainer.new();layout.add_theme_constant_override("separation",10);panel.add_child(layout)
	var header=preload("res://src/ui/window_handle.gd").new();layout.add_child(header)
	var heading=Label.new();heading.text=app.t("file_patch_title");heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(heading)
	var close=Button.new();close.text="×";close.pressed.connect(dismiss);header.add_child(close)
	caption=Label.new();caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;caption.add_theme_color_override("font_color",V.RED);layout.add_child(caption)
	var shell=layout
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(scroll)
	layout=VBoxContainer.new();layout.size_flags_horizontal=Control.SIZE_EXPAND_FILL;layout.add_theme_constant_override("separation",8);scroll.add_child(layout)
	sheet_row=HBoxContainer.new();layout.add_child(sheet_row)
	var sheet_label=Label.new();sheet_label.text=app.t("table_sheet");sheet_row.add_child(sheet_label)
	sheet_number=SpinBox.new();sheet_number.min_value=1;sheet_number.max_value=256;sheet_number.value=1;sheet_row.add_child(sheet_number);sheet_number.value_changed.connect(func(_value):revoke())
	value_kind=OptionButton.new()
	for key in ["office_type_text","office_type_number","office_type_boolean"]:value_kind.add_item(app.t(key))
	value_kind.item_selected.connect(func(_index):revoke())
	sheet_row.add_child(value_kind)
	address_row=HBoxContainer.new();layout.add_child(address_row)
	for i in range(2):
		var label=Label.new();label.text=app.t("table_row" if i==0 else "table_column");address_row.add_child(label)
		var number=SpinBox.new();number.min_value=1;number.max_value=10000 if i==0 else 256;number.value=1;number.size_flags_horizontal=Control.SIZE_EXPAND_FILL;address_row.add_child(number)
		number.value_changed.connect(func(_value):revoke();_sync_range())
		if i==0:table_row=number
		else:table_column=number
	range_row=VBoxContainer.new();layout.add_child(range_row)
	var range_fields=HBoxContainer.new();range_row.add_child(range_fields)
	for i in range(2):
		var label=Label.new();label.text=app.t("range_last_row" if i==0 else "range_last_column");range_fields.add_child(label)
		var number=SpinBox.new();number.min_value=1;number.max_value=10000 if i==0 else 256;number.value=1;number.size_flags_horizontal=Control.SIZE_EXPAND_FILL;range_fields.add_child(number)
		number.value_changed.connect(func(_value):revoke())
		if i==0:range_end_row=number
		else:range_end_column=number
	var stats=Button.new();stats.text=app.t("range_summary");range_row.add_child(stats);stats.pressed.connect(summarize_range)
	read_button=Button.new();read_button.text=app.t("table_read_cell");read_button.clip_text=true;layout.add_child(read_button);read_button.pressed.connect(read_cell)
	var row=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(row)
	for i in range(2):
		var column=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(column)
		var label=Label.new();label.text=app.t("file_patch_find" if i==0 else "file_patch_replace");column.add_child(label)
		var edit=TextEdit.new();edit.custom_minimum_size=Vector2(120,70);edit.size_flags_vertical=Control.SIZE_EXPAND_FILL;edit.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;column.add_child(edit)
		edit.text_changed.connect(func():token="";engine.cancel();apply_button.disabled=true)
		if i==0:find_edit=edit
		else:replace_edit=edit
	preview=TextEdit.new();preview.editable=false;preview.add_theme_color_override("font_readonly_color",V.TEXT);preview.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;preview.custom_minimum_size.y=112;preview.size_flags_vertical=Control.SIZE_EXPAND_FILL;shell.add_child(preview)
	var footer=HBoxContainer.new();shell.add_child(footer)
	for i in range(3):
		var button=Button.new();button.text=app.t(["file_patch_review","file_patch_apply","file_patch_undo"][i]);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.clip_text=true;footer.add_child(button)
		button.pressed.connect([review,apply,restore][i])
		if i==1:apply_button=button;V.primary(button);button.disabled=true
		if i==2:undo_button=button;button.disabled=true
	close_requested.connect(dismiss)
func open_path(selected):
	engine.cancel();token="";path=selected;engine.load_backup(path);caption.text=selected.get_file();caption.tooltip_text=selected
	address_row.visible=path.get_extension().to_lower() in ["csv","tsv","xlsx"]
	read_button.visible=address_row.visible;range_row.visible=address_row.visible
	sheet_row.visible=path.get_extension().to_lower()=="xlsx"
	sheet_number.value=1;value_kind.select(0)
	table_row.value=1;table_column.value=1;range_end_row.value=1;range_end_column.value=1
	find_edit.clear();replace_edit.clear();preview.text=app.t("office_hint" if path.get_extension().to_lower() in ["docx","xlsx"] else ("table_hint" if address_row.visible else "file_patch_hint"));apply_button.disabled=true;undo_button.disabled=engine.last_backup.is_empty() or engine.last_backup.get("path")!=path
	var bounds=DisplayServer.screen_get_usable_rect()
	size=Vector2i(mini(640,bounds.size.x),mini(500,bounds.size.y));position=bounds.position+(bounds.size-size)/2
	show();grab_focus()
	app.file_activity="read";app.changed.emit()
func revoke():
	engine.cancel();token=""
	if is_instance_valid(apply_button):apply_button.disabled=true
func _sync_range():
	if is_instance_valid(range_end_row):range_end_row.min_value=table_row.value
	if is_instance_valid(range_end_column):range_end_column.min_value=table_column.value
func review():
	if app.paused:revoke();return
	var result
	if sheet_row.visible:result=engine.prepare_sheet_cell(path,int(sheet_number.value),int(table_row.value),int(table_column.value),find_edit.text,replace_edit.text,false,["text","number","boolean"][value_kind.selected])
	elif address_row.visible:result=engine.prepare_cell(path,int(table_row.value),int(table_column.value),find_edit.text,replace_edit.text)
	else:result=engine.prepare(path,find_edit.text,replace_edit.text)
	_show_plan(result)
func read_cell():
	if app.paused:revoke();return
	revoke()
	var result=engine.prepare_sheet_cell(path,int(sheet_number.value),int(table_row.value),int(table_column.value),"","",true) if sheet_row.visible else engine.inspect_cell(path,int(table_row.value),int(table_column.value))
	if not result.get("ok",false):_show_plan(result);return
	find_edit.text=result.value;preview.text=app.t("table_value_loaded");app.file_activity="read";app.changed.emit()
func summarize_range():
	if app.paused:revoke();return
	revoke()
	var result=engine.inspect_range(path,int(sheet_number.value),int(table_row.value),int(table_column.value),int(range_end_row.value),int(range_end_column.value))
	if not result.ok:_show_plan(result);return
	var values={}
	for key in ["count","blank","other","sum","mean","min","max"]:values[key]=str(result[key]) if result[key]!=null else "—"
	preview.text=app.t("range_result",values)+"\n"+app.t("range_hint")
	app.file_activity="present";app.changed.emit()
func _show_plan(result):
	apply_button.disabled=not result.get("ok",false);token=result.get("token","")
	if not result.get("ok",false):preview.text=app.t("file_patch_error",{"reason":app.t("file_status_"+str(result.get("status","failed")))});return
	preview.text=app.t("file_patch_preview",{"line":result.line})+"\n− "+result.before+"\n+ "+result.after
	app.file_activity="wait";app.report_task("file_review")
func apply():
	if app.paused:revoke();return
	var result=engine.commit(token);token="";apply_button.disabled=true
	preview.text=app.t("file_patch_written") if result.get("ok",false) else app.t("file_patch_error",{"reason":app.t("file_status_"+str(result.get("status","failed")))})
	undo_button.disabled=engine.last_backup.is_empty() or engine.last_backup.get("path")!=path
	if result.get("ok",false):app.add_message("assistant",app.t("file_patch_receipt",{"name":path.get_file()}),true);app.request_motion("work.note_saved")
	app.file_activity="present" if result.get("ok",false) else "error"
	app.report_task("file_verified" if result.get("ok",false) else "file_failed")
func restore():
	if app.paused:revoke();return
	if engine.last_backup.get("path")!=path:return
	_show_plan(engine.prepare_restore())
func dismiss():
	engine.cancel();token="";find_edit.clear();replace_edit.clear();preview.clear();hide()
	app.file_activity="";app.changed.emit()
