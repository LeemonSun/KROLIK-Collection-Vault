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
func shot(win,name):
	var image=win.get_texture().get_image();check(image!=null and not image.is_empty(),"Native rendered "+name)
	if image:image.save_png(OS.get_environment("COMPANION_VISUAL_OUTPUT").path_join(name+".png"))
func run():
	var app=root.get_node("App");app.set_locale("ru")
	var boot=load("res://scenes/bootstrap.tscn").instantiate();root.add_child(boot)
	await create_timer(1.3).timeout
	app.desktop_companion.auto_move=false;app.desktop_companion._cancel_travel()
	var menu=app.desktop_companion.quick_menu
	menu.open_at(Vector2i(1100,400));await create_timer(0.25).timeout;await frame()
	check(menu.visible and menu.canvas.modulate.a==1,"Orbit remains visible after entrance")
	check(menu.buttons.filter(func(b):return b.visible).size()==4,"Exactly four main quick actions")
	shot(menu,"orbit-controls");menu.hide()
	app.show_chat();await create_timer(0.3).timeout
	app.messages=[{"speaker":"user","text":"Найди вкладку с музыкой"},{"speaker":"assistant","text":"Могу поискать среди открытых вкладок. Скажи название сайта или трека."}];app.chat_window.view._render_history();await frame()
	shot(app.chat_window,"orbit-conversation")
	for locale in ["ru","en","zh-Hans"]:
		app.set_locale(locale);boot.main_view.open_panel("assistant_tools");await create_timer(0.25).timeout;await frame()
		check(boot.main_view.content.get_child_count()==6,"Three real installer cards, heading, hint, system voice note "+locale)
		check(boot.main_view._pages().size()==3,"Only three ordinary settings sections "+locale)
		if locale=="ru":shot(boot.panel_window,"orbit-components")
	app.set_locale("ru");boot.panel_window.hide();app.chat_window.hide();app.cancel()
	var target={"handle":"123","target_pid":234,"started":"345","title":"Тестовое приложение","app":"Synthetic"}
	app.goal_origin_target=target;app.application_access.target=target
	app.goal_mode="proposal";app.goal_deadline_ms=Time.get_ticks_msec()+30000
	app.goal_plan={"ok":true,"target":target,"action":"write","node":{"name":"Текст","id":"1,2"},"text":"Демонстрационный текст для проверки карточки. Ничего не отправляется.","append":false,"generated":true}
	app.changed.emit();await create_timer(0.25).timeout;await frame()
	var task=app.task_window
	check(task.visible and task.detail.text.contains(app.goal_plan.text),"Independent native review includes full proposed text")
	check(task.primary.visible and not task.primary.disabled,"Fresh review is actionable")
	check(task.transient and not task.always_on_top,"Transient task window avoids incompatible on-top flag")
	shot(task,"orbit-action-review")
	var old=task.snapshot.token;app.goal_plan.text="Изменённый черновик"
	task.accept_current();check(app.goal_mode=="proposal","Stale card cannot confirm changed draft")
	await frame();check(task.snapshot.token!=old,"Changed draft refreshes review")
	app.cancel();await frame();check(not task.visible,"Cancel clears card without showing old proposal as a result")
	for dimensions in [Vector2i(320,240),Vector2i(400,290)]:
		app.goal_mode="observing";app.goal_origin_target=target;app.goal_deadline_ms=Time.get_ticks_msec()+30000;app.changed.emit();await frame()
		check(task.visible,"New task reopens after previous cancellation")
		task.size=dimensions;await frame()
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(task.cancel_button.get_global_rect()),"Cancel reachable at "+str(dimensions)+" actual="+str(task.size)+" rect="+str(task.cancel_button.get_global_rect())+" surface="+str(task.surface.size))
		task.dismiss();app.goal_mode="verifying";app.changed.emit();await frame()
		check(not task.visible,"Closed task card stays closed on another stage")
		app.cancel();await frame()
	app.goal_mode="observing";app.goal_origin_target=target;app.goal_deadline_ms=Time.get_ticks_msec()+30000;app.changed.emit();await frame()
	app.goal_mode="";app.goal_origin_target={};app.add_message("assistant","Переключатель включён. Подключение сети ещё не проверено.",true);app.changed.emit();await frame()
	check(task.visible and task.snapshot.kind=="result" and task.detail.text.contains("ещё не проверено"),"Result preserves actual limited evidence")
	check(task.ttl.is_stopped(),"Completed card has no repeating countdown")
	shot(task,"orbit-result");task.dismiss()
	for name in ["adjust_glasses","peek","offer","listen_confirm"]:
		app.desktop_companion.set_process(false);app.desktop_companion.art.play(name,2.0);await create_timer(0.5).timeout;await frame()
		check(app.desktop_companion.art.clip==name,"New procedural gesture renders "+name)
		shot(root,"orbit-"+name)
	app.desktop_companion.set_process(true);app.cancel()
	print("ORBIT_VISUAL026: %d checks, %d failures; actual X11/synthetic state, not Windows or model quality" %[checks,failures]);quit(0 if failures==0 else 1)
