extends SceneTree
var checks=0
var failures=0
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func _initialize():_run.call_deferred()
func frame():
	await process_frame
	await process_frame
	RenderingServer.force_draw.call_deferred()
	await RenderingServer.frame_post_draw
func shot(window,name):
	var image=window.get_texture().get_image()
	check(image!=null and not image.is_empty(),"Rendered "+name)
	if image:image.save_png(OS.get_environment("COMPANION_VISUAL_OUTPUT").path_join(name+".png"))
func _run():
	if DisplayServer.get_name()=="headless":quit(1);return
	var app=root.get_node("App")
	app.set_locale("ru")
	var boot=load("res://scenes/bootstrap.tscn").instantiate();root.add_child(boot)
	await create_timer(1.2).timeout
	var desktop=app.desktop_companion
	desktop.set_process(false);desktop.art.set_process(false)
	desktop._cancel_travel();desktop.auto_move=false
	app.cancel();app.goal_mode="";app.window_read_mode="";app.file_activity=""
	desktop.activity_elapsed=0
	desktop.perform_gesture("talk",1.2)
	check(desktop.art.clip=="talk","Idle reply has a speaking gesture")
	app.goal_mode="verifying";app.goal_deadline_ms=Time.get_ticks_msec()+60000
	desktop._process(0.2)
	check(desktop.art.clip=="scan","Real verification preempts a speaking gesture")
	desktop.perform_gesture("error",0.4,3);desktop._process(0.6)
	check(desktop.art.clip=="scan","A temporary reaction cannot strand active work in idle")
	app.goal_mode="";desktop._process(0.2)
	check(desktop.art.clip=="idle","Completed work returns to idle")
	desktop.perform_gesture("error",0.8,3)
	check(not desktop.perform_gesture("nod",1.0,0) and desktop.art.clip=="error","Idle variation cannot override an error")
	desktop._process(1.0);check(desktop.art.clip=="idle","Expired reaction releases its priority")
	var bounds=DisplayServer.screen_get_usable_rect()
	desktop.position=Vector2i(300,bounds.end.y-desktop.size.y)
	var target=desktop.position+Vector2i(260,0)
	var region_count=desktop.region_updates
	check(desktop.walk_to(target),"Real host travel starts")
	check(desktop.art.clip=="turn","Travel begins with anticipation")
	var previous=desktop.position
	for i in range(20):desktop._process(0.05);desktop.art._process(0.05)
	check(desktop.position.x>previous.x and desktop.position.x<target.x,"Host moves through intermediate positions")
	check(desktop.art.locomotion_driven and desktop.art.clip=="walk","Feet use host travel distance")
	check(not desktop.walk_to(target),"Repeated destination does not restart a route")
	var guard=0
	while desktop.effect_kind=="walk" and guard<300:
		desktop._process(0.05);desktop.art._process(0.05);guard+=1
	check(desktop.position==target and guard<300,"Host arrives exactly and finishes")
	check(not desktop.art.locomotion_driven,"Arrival releases the gait driver")
	check(desktop.region_updates==region_count,"Travel never rebuilds the native input region")
	desktop._process(1);desktop.art._process(1);await frame();shot(root,"arrival")
	check(desktop.walk_to(target-Vector2i(160,0)),"Return route starts")
	desktop._process(0.5)
	var press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
	desktop._input_event(press)
	check(desktop.dragging and not desktop.locomotion.active and desktop.effect_kind.is_empty(),"Mouse pickup immediately cancels the old route")
	desktop._release_drag()
	var stopped=desktop.position;desktop._process(0.6)
	check(desktop.position==stopped,"Releasing pickup cannot resurrect the old route")
	desktop.auto_move=true
	check(desktop.walk_to(desktop.position+Vector2i(140,0)),"Route before pause starts")
	app.store.data.settings.companion_roam=true
	app.set_paused(true)
	check(not desktop.locomotion.active and desktop.effect_kind.is_empty() and desktop.art.reduced,"Pause stops host and pose motion")
	stopped=desktop.position;desktop._process(0.8)
	check(desktop.position==stopped,"Pause cannot continue a hidden route")
	app.set_paused(false)
	check(desktop.auto_move and not desktop.reduced_motion,"Resume restores the user's movement preference")
	desktop.auto_move=false
	desktop.walk_to(desktop.position+Vector2i(120,0));desktop._process(0.4)
	desktop.set_reduced(true);stopped=desktop.position;desktop._process(2)
	check(desktop.position==stopped and not desktop.locomotion.active,"Reduced motion freezes current location, no delayed teleport")
	check(not desktop.art.is_processing(),"Reduced rig consumes no pose ticks")
	desktop.set_reduced(false)
	desktop.play_entrance()
	check(not bounds.encloses(Rect2i(desktop.position,desktop.size)),"Entrance begins beyond the edge")
	desktop.set_reduced(true)
	check(bounds.encloses(Rect2i(desktop.position,desktop.size)) and desktop.art.modulate.a==1,"Disabling motion during entrance cannot freeze an offscreen invisible character")
	desktop.set_reduced(false);desktop.art.set_process(false)
	desktop.position=Vector2i(400,bounds.end.y-desktop.size.y)
	check(app.say_companion("Тестовая реплика: готово. Полный ответ остаётся в чате."),"Companion reply opens without a chat")
	await frame()
	var old=app.speech_bubble.position
	desktop.position=desktop.bounded(desktop.position+Vector2i(140,0))
	app.speech_bubble._process(0.11);await frame()
	check(app.speech_bubble.position!=old,"Reply follows relocated mascot")
	check(bounds.encloses(Rect2i(app.speech_bubble.position,app.speech_bubble.size)),"Following reply remains inside usable monitor")
	check(not Rect2i(app.speech_bubble.position,app.speech_bubble.size).intersects(Rect2i(desktop.position,desktop.size)),"Following reply leaves mascot unobscured")
	shot(app.speech_bubble,"reply-following")
	app.show_chat();await frame()
	check(not app.speech_bubble.visible and not app.speech_bubble.is_processing(),"Opening chat disables duplicate reply tracking")
	app.chat_window.hide()
	desktop.hide()
	check(not desktop.art.is_processing() and desktop.art.suspended,"Minimize stops pose ticks")
	desktop.show()
	check(desktop.art.is_processing() and not desktop.art.suspended and desktop.art.modulate.a==1,"Restore resumes visible opaque character")
	check(desktop.effect_kind.is_empty() and not desktop.locomotion.active,"Restore never resumes a stale route")
	desktop.set_process(true)
	print("PERFORMANCE_VISUAL018: %d checks, %d failures; actual X11 windows, synthetic tasks; not Windows" %[checks,failures])
	quit(0 if failures==0 else 1)
