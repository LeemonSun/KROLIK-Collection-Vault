extends SceneTree
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func frame():
	await process_frame;await process_frame
	RenderingServer.force_draw.call_deferred();await RenderingServer.frame_post_draw
func shot(window,name):
	var picture=window.get_texture().get_image()
	check(picture!=null and not picture.is_empty(),'Rendered '+name)
	if picture:picture.save_png(OS.get_environment('COMPANION_VISUAL_OUTPUT').path_join(name+'.png'))
func run():
	var path=OS.get_environment('LEEMON_NATIVE_XLSX')
	if not FileAccess.file_exists(path):push_error('Independent XLSX fixture required');quit(1);return
	var app=root.get_node('App');app.set_locale('ru')
	var boot=load('res://scenes/bootstrap.tscn').instantiate();root.add_child(boot)
	await create_timer(0.4).timeout
	app.open_settings('settings');await frame()
	var mode=boot.main_view.find_child('ResourceMode',true,false)
	check(mode!=null and mode.selected==0,'Native settings expose default economy mode')
	mode.item_selected.emit(1);check(app.resource_mode=='standard','Native mode picker changes runtime budget')
	mode.item_selected.emit(0);check(app.runtime_options().cpu_threads==1,'Native picker restores economy')
	shot(boot.panel_window,'economy-settings-013');boot.panel_window.hide()
	var editor=load('res://src/ui/file_edit_window.gd').new();root.add_child(editor)
	for locale in ['ru','en','zh-Hans']:
		app.set_locale(locale);editor.dismiss();editor.queue_free();await frame()
		editor=load('res://src/ui/file_edit_window.gd').new();root.add_child(editor);editor.open_path(path)
		check(editor.value_kind.visible and editor.value_kind.item_count==3,'Explicit XLSX type choices '+locale)
		for dimensions in [Vector2i(400,420),Vector2i(640,500)]:
			editor.size=dimensions;await frame()
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(editor.apply_button.get_global_rect()),'Approval remains visible '+locale+str(dimensions))
			check(editor.range_row.visible,'Range controls available '+locale)
	app.set_locale('ru');editor.dismiss();editor.queue_free();await frame()
	editor=load('res://src/ui/file_edit_window.gd').new();root.add_child(editor);editor.open_path(path)
	editor.table_row.value=2;editor.table_column.value=2
	check(editor.range_end_row.value>=2 and editor.range_end_column.value>=2,'Range endpoint follows chosen start instead of defaulting to invalid range')
	editor.read_cell();check(editor.find_edit.text=='42','Native read loads existing numeric value')
	editor.value_kind.select(1);editor.value_kind.item_selected.emit(1);editor.replace_edit.text='12.5';editor.review();await frame()
	check(not editor.apply_button.disabled and '[number]' in editor.preview.text,'Numeric write is explicitly labeled in preview')
	shot(editor,'typed-xlsx-review-013')
	editor.summarize_range();await frame()
	check(editor.apply_button.disabled and editor.engine.pending.is_empty() and '42' in editor.preview.text,'Read-only summary revokes previous write authority')
	shot(editor,'range-summary-013')
	editor.review();editor.apply()
	check(editor.engine.prepare_sheet_cell(path,1,2,2,'','',true).value=='12.5','Native numeric apply changes real fixture')
	editor.restore();await frame();check(not editor.apply_button.disabled,'Restore requires its own preview')
	editor.apply();check(editor.engine.prepare_sheet_cell(path,1,2,2,'','',true).value=='42','Native reviewed undo restores original bytes')
	editor.dismiss();app.cancel()
	print('TECHNICAL_VISUAL013_TESTS: %d checks, %d failures; X11 windows and synthetic independent XLSX fixture, not Windows' %[checks,failures])
	quit(0 if failures==0 else 1)
