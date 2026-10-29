extends SceneTree
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func frame():
	await process_frame;await process_frame
	RenderingServer.force_draw.call_deferred();await RenderingServer.frame_post_draw
func run():
	var app=root.get_node('App');app.set_locale('ru')
	var boot=load('res://scenes/bootstrap.tscn').instantiate();root.add_child(boot)
	await create_timer(1.1).timeout
	app.desktop_companion._cancel_travel()
	check(not root.always_on_top,'Mascot is not forced above every application')
	check(not app.desktop_companion.auto_move,'Old roaming setting migrates to quiet desktop by default')
	app.show_chat();await create_timer(.25).timeout
	check(not app.chat_window.always_on_top,'Chat is an ordinary focusable window')
	boot.main_view.open_panel('settings');await frame()
	check(not boot.panel_window.always_on_top,'Settings do not pin themselves above other applications')
	boot.panel_window.hide()
	var target={'handle':'123','target_pid':234,'started':'345','title':'Synthetic app','app':'Client'}
	app.application_access.target=target;app.goal_origin_target=target
	app.goal_mode='proposal';app.goal_deadline_ms=Time.get_ticks_msec()+30000
	app.goal_plan={'ok':true,'action':'select','node':{'id':'1,2','name':'General'},'target':target,'text':'','append':false}
	app.changed.emit();await frame()
	check(not app.task_window.visible and app.chat_window.view.confirmation_button.visible,'One approval surface while chat is open')
	var desktop=app.desktop_companion;desktop.position=Vector2i(200,200);desktop.home_position=Vector2i(900,500);desktop.auto_move=true
	app.chat_window.close_soft();await create_timer(.25).timeout;await frame()
	check(desktop.position==Vector2i(200,200) and desktop.effect_kind!='walk','Closing chat does not force a return to bottom/home')
	check(app.task_window.visible,'Closed chat exposes the separate pending action card')
	app.cancel();await frame()
	var path=ProjectSettings.globalize_path('user://literal-review027.ini')
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_string('[Video]\nFPS=60\n');file.close()
	app.submit('в файле "'+path+'" замени "FPS=60" на "FPS=90"');await frame()
	check(is_instance_valid(app.file_editor) and app.file_editor.visible,'Literal request opens a real file review without a picker')
	check(FileAccess.get_file_as_string(path).contains('FPS=60') and not app.file_editor.apply_button.disabled,'Review alone does not edit the existing file')
	app.file_editor.apply();check(FileAccess.get_file_as_string(path).contains('FPS=90'),'Approved literal request actually edits the file')
	app.file_editor.dismiss()
	var handle=preload('res://src/ui/window_handle.gd').new();root.add_child(handle);handle.held=true
	root.focus_exited.emit();check(not handle.held,'Lost window focus releases header drag')
	handle.held=true;handle._gui_input(InputEventMouseMotion.new());check(not handle.held,'Mouse release outside header cannot leave a permanent drag')
	handle.queue_free();app.cancel()
	print('REPAIR_VISUAL027: %d checks, %d failures; actual X11 and real file edit, not Windows/microphone acceptance' %[checks,failures]);quit(0 if failures==0 else 1)
