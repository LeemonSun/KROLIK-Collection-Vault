extends SceneTree
## Synthetic stage, actual app renderer. No model inference or desktop actions.
var entries=[]
func _initialize():_run.call_deferred()
func _run():
	var app=root.get_node("App")
	var boot=load("res://scenes/bootstrap.tscn").instantiate();root.add_child(boot)
	await create_timer(1.2).timeout
	var desktop=app.desktop_companion
	desktop.set_process(false);desktop.art.set_process(false);desktop._cancel_travel();desktop.auto_move=false
	app.cancel();app.goal_mode="";app.file_activity=""
	desktop.position=Vector2i(240,500)
	var out=OS.get_environment("COMPANION_VISUAL_OUTPUT")
	var label="Появление и приветствие"
	for i in range(180):
		if i==0:desktop.perform_gesture("hello",1.0,2)
		if i==20:desktop.walk_to(Vector2i(530,500));label="Переход: шаги связаны с расстоянием"
		if i==88:
			app.goal_mode="thinking";app.goal_deadline_ms=Time.get_ticks_msec()+60000
			label="Рабочая поза: ожидание ответа"
		if i==112:app.goal_mode="verifying";label="Рабочая поза: проверка"
		if i==138:
			app.goal_mode="";desktop.perform_gesture("celebrate",1.0,2)
			label="Короткая реакция"
		if i==158:
			desktop.perform_gesture("talk",1.3,1)
			app.say_companion("Я здесь. Что делаем дальше?")
			label="Реплика рядом с персонажем"
		desktop._process(0.05);desktop.art._process(0.05)
		if is_instance_valid(app.speech_bubble) and app.speech_bubble.visible:app.speech_bubble._process(0.11)
		await process_frame
		RenderingServer.force_draw.call_deferred()
		await RenderingServer.frame_post_draw
		var name="frame_%03d.png"%i
		root.get_texture().get_image().save_png(out.path_join(name))
		var item={"frame":i,"file":name,"x":desktop.position.x,"y":desktop.position.y,"label":label}
		if is_instance_valid(app.speech_bubble) and app.speech_bubble.visible:
			var bubble="bubble_%03d.png"%i
			app.speech_bubble.get_texture().get_image().save_png(out.path_join(bubble))
			item["bubble"]=bubble;item["bubble_x"]=app.speech_bubble.position.x;item["bubble_y"]=app.speech_bubble.position.y
		entries.append(item)
	var f=FileAccess.open(out.path_join("frames.json"),FileAccess.WRITE);f.store_string(JSON.stringify(entries));f.close()
	print("MOTION018_CAPTURE: 180 frames, 0 failures; scripted synthetic demonstration, no model or OS actions")
	quit()
