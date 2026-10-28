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
func run():
	var app=root.get_node('App');var boot=load('res://scenes/bootstrap.tscn').instantiate();root.add_child(boot)
	await create_timer(.4).timeout;app.show_chat();await frame()
	var view=app.chat_window.view
	var target={'handle':'12','target_pid':34,'started':'56','title':'Synthetic editor','app':'editor'}
	var nodes=[{'id':'1','name':'Body','type':'ControlType.Edit','enabled':true,'write':true}]
	var text='A reviewed draft with Unicode 中文.\n'.repeat(9)+'END OF DRAFT'
	for locale in ['ru','en','zh-Hans']:
		app.set_locale(locale);app.cancel();app.application_access.target=target.duplicate(true)
		app.agent.begin('Compose a short greeting',target,Time.get_ticks_msec())
		app.goal_context=app.agent.prepare(target,nodes,Time.get_ticks_msec(),Time.get_ticks_msec(),locale);app.goal_mode='thinking'
		app._goal_answer(JSON.stringify({'choice':'write:e0','text':text,'append':false}));await frame()
		check(app.goal_mode=='proposal' and app.messages[-1].text.ends_with('END OF DRAFT'),'Complete draft displayed before effect '+locale)
		for dimensions in [Vector2i(320,280),Vector2i(460,560)]:
			app.chat_window.size=dimensions;await frame()
			check(view.confirmation_button.is_visible_in_tree(),'Draft confirmation visible '+locale+str(dimensions))
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(view.confirmation_button.get_global_rect()),'Confirmation fits '+locale+str(dimensions))
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(view.editor.get_global_rect()),'Composer fits '+locale+str(dimensions)+' '+str(view.editor.get_global_rect())+' min='+str(view.get_combined_minimum_size()))
			check('END OF DRAFT' in view.history.get_parsed_text(),'Draft body retained in scrollable transcript '+locale)
		check(app.application_access.pid<0,'Preview cannot execute native process '+locale)
		app.cancel();await frame();check(not view.confirmation_button.visible,'Cancel removes draft approval '+locale)
	app.set_locale('ru');app.chat_window.get_texture().get_image().save_png(OS.get_environment('COMPANION_VISUAL_OUTPUT').path_join('draft016.png'))
	print('DRAFT_VISUAL016_TESTS: %d checks, %d failures; synthetic draft, actual X11 rendering, no Windows effect' %[checks,failures])
	quit(0 if failures==0 else 1)
