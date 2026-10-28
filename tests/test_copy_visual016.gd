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
	var app=root.get_node('App')
	var boot=load('res://scenes/bootstrap.tscn').instantiate();root.add_child(boot)
	await create_timer(0.4).timeout;app.show_chat();await frame()
	var view=app.chat_window.view
	app.messages=[]
	for i in range(60):app.messages.append({'speaker':'user' if i%2==0 else 'assistant','text':'Message '+str(i)+' Привет 中文\nsecond line Ответ LEEMON '+('long body '.repeat(30))})
	app.messages_truncated=false;app.changed.emit()
	for locale in ['ru','en','zh-Hans']:
		app.set_locale(locale)
		for dimensions in [Vector2i(320,280),Vector2i(460,560)]:
			app.chat_window.size=dimensions;await frame()
			check(view.copy_chat_button.is_visible_in_tree(),'Copy visible '+locale+str(dimensions))
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(view.copy_chat_button.get_global_rect()),'Copy fits '+locale+str(dimensions))
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(view.editor.get_global_rect()),'Input fits '+locale+str(dimensions))
			view.copy_chat_button.pressed.emit();await frame()
			var copied=DisplayServer.clipboard_get()
			check('Message 0 ' in copied and 'Message 30 ' in copied and 'Message 59 ' in copied and copied==preload('res://src/core/chat_transcript.gd').format(app.messages,app.t('chat_you').to_upper()).text,'Actual clipboard includes entire retained chat '+locale)
			check(view.status_label.text==app.t('chat_copy_done',{'count':60}),'Clipboard success status '+locale)
	check(app.messages.size()==60,'Copy status creates no extra conversation message')
	app.set_locale('ru');app.chat_window.size=Vector2i(460,560);await frame()
	app.chat_window.get_texture().get_image().save_png(OS.get_environment('COMPANION_VISUAL_OUTPUT').path_join('copy-chat-015.png'))
	print('COPY_VISUAL016_TESTS: %d checks, %d failures; 60message real X11 clipboard and layout, not Windows' %[checks,failures])
	quit(0 if failures==0 else 1)
