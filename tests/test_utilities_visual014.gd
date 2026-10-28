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
	var app=root.get_node('App');app.set_locale('ru')
	var boot=load('res://scenes/bootstrap.tscn').instantiate();root.add_child(boot)
	await create_timer(0.4).timeout;app.show_chat();await frame()
	var view=app.chat_window.view
	for locale in ['ru','en','zh-Hans']:
		app.set_locale(locale)
		view.editor.text='/calc sqrt(81) + 2^3';view.submit_current();await frame()
		check('17' in view.history.get_parsed_text() and app.state.current=='idle','Native calculator reply '+locale)
		for dimensions in [Vector2i(320,280),Vector2i(460,560)]:
			app.chat_window.size=dimensions;await frame()
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(view.editor.get_global_rect()),'Input visible with utility result '+locale+str(dimensions))
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(view.send_button.get_global_rect()),'Send visible '+locale+str(dimensions))
	app.set_locale('ru');app.chat_window.size=Vector2i(460,560)
	view.editor.text='переведи 10 MB в MiB';view.submit_current();await frame();await frame()
	check('MiB' in view.history.get_parsed_text() and app.local_runtime.pid==-1,'Conversion from native composer without AI')
	var last=view.history.rows.get_child(view.history.rows.get_child_count()-1)
	check(Rect2(view.history.global_position,view.history.size).intersects(last.get_global_rect()),'Latest synchronous tool answer is actually visible after submitting')
	shot(app.chat_window,'calculator-conversion-014')
	view.editor.text='открой настройки звука';view.submit_current();await frame()
	check(app.messages[-1].text==app.t('settings_page_platform'),'Linux build does not falsely claim Windows setting change')
	app.public_page.set_process(false);app.public_page.busy=true;app.public_page.stage='reading';app.state.transition('executing');app.changed.emit();await frame()
	check(view.status_label.text==app.t('web_stage_reading'),'Native chat displays real reader stage')
	check(not app.begin_dictation(view.editor),'Other heavy interaction cannot start during page tool')
	app.cancel();app.public_page.set_process(true);await frame()
	check(not app.public_page.busy and app.state.current=='idle','Native stop clears page task')
	app._public_page_ready({'url':'https://example.com/guide','retrieved_utc':'2026-10-28T00:00:00','blocks':['Synthetic source excerpt: settings are unchanged.','[b]Text is data[/b] — no action was executed.']})
	await frame()
	check(app.messages[-1].get('ephemeral',false) and 'https://example.com/guide' in view.history.get_parsed_text(),'Source result is visible and ephemeral')
	check('[b]Text is data[/b]' in view.history.get_parsed_text(),'Source markup remains inert text')
	shot(app.chat_window,'source-excerpts-014')
	print('UTILITIES_VISUAL014_TESTS: %d checks, %d failures; actual X11 chat, synthetic page data, not live Windows or public web' %[checks,failures])
	quit(0 if failures==0 else 1)
