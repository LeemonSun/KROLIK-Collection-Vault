extends SceneTree
class FakeTranslationProvider extends Node:
	var received=[]
	func submit(messages,_options):received=messages;return true
	func cancel():pass
var checks=0
var failures=0
func _initialize():
	_run.call_deferred()
func check(value,label):
	checks+=1
	if not value:
		failures+=1
		push_error(label)
func frame():
	await process_frame
	await process_frame
	RenderingServer.force_draw.call_deferred()
	await RenderingServer.frame_post_draw
func shot(window,name):
	var image=window.get_texture().get_image()
	check(image!=null and not image.is_empty(),"Rendered "+name)
	if image!=null:
		image.save_png(OS.get_environment("COMPANION_VISUAL_OUTPUT").path_join(name+".png"))
func _run():
	if DisplayServer.get_name()=="headless":
		push_error("Visual review requires an isolated display")
		quit(1)
		return
	var app=root.get_node("App")
	app.set_locale("ru")
	var boot=load("res://scenes/bootstrap.tscn").instantiate()
	root.add_child(boot)
	var main=boot.main_view
	var panel=boot.panel_window
	await create_timer(0.7).timeout
	check(not panel.visible,"Control panel hidden on normal startup")
	check(is_instance_valid(app.desktop_companion) and app.desktop_companion.visible,"Character visible on startup")
	check(app.desktop_companion.host==root,"Main window is the character, not an offscreen host")
	check(root.position.x>=0 and root.position.y>=0,"Main window starts on screen")
	check(not root.mouse_passthrough and not root.unfocusable,"Taskbar window can receive input and focus")
	check(not root.exclude_from_capture,"Character is visible in ordinary screenshots")
	shot(app.desktop_companion,"hero")
	app.show_chat()
	await frame()
	check(app.chat_window.visible,"Chat opens separately")
	var view=app.chat_window.view
	await create_timer(0.3).timeout
	var chat_bounds=Rect2(Vector2.ZERO,Vector2(app.chat_window.size))
	check(view.size==Vector2(app.chat_window.size),"Native first-open view matches viewport")
	check(chat_bounds.encloses(view.editor.get_global_rect()),"Native first-open input visible")
	check(chat_bounds.encloses(view.send_button.get_global_rect()),"Native first-open send visible")
	check(not view.setup_button.visible or view.setup_button.size.x>=140,"Inline installer has a usable hit area")
	var region_updates=app.desktop_companion.region_updates
	for i in range(12):view.editor.insert_text_at_caret("x")
	await create_timer(0.2).timeout
	check(view.editor.text=="x".repeat(12),"Native typing retained")
	check(app.desktop_companion.region_updates==region_updates,"Typing does not rewrite region")
	app.chat_window.close_soft();app.show_chat()
	await create_timer(0.3).timeout
	check(app.chat_window.visible and view.modulate.a==1,"Quick reopen stays visible")
	view.editor.text="Привет! Хочу поговорить."
	await frame()
	shot(app.chat_window,"chat")
	view.submit_current()
	await frame()
	check(app.messages.any(func(x):return x.text=="Привет! Хочу поговорить."),"Visible native composer submits")
	check(not view.history.get_parsed_text().is_empty(),"Native chat displays provider feedback")
	view._voice();await frame()
	check(view.install_mode=="voice" and view.setup_button.visible,"Voice setup is inline, no settings detour")
	check(not app.speech_input.microphone.recording and app.speech_input.microphone.player==null,"Voice setup does not activate microphone")
	check(Rect2(Vector2.ZERO,Vector2(app.chat_window.size)).encloses(view.voice_button.get_global_rect()),"Mic button fits native chat")
	view.install_mode="text";view.refresh()
	app.application_access.windows=[]
	for i in range(24):app.application_access.windows.append({"app":"Test app","title":"Synthetic window "+str(i)})
	view.choose_window=true;view.refresh();await frame()
	check(view.window_picker.visible,"Application picker opens from the chat toolbar")
	check(view.window_picker.size.x<=600 and view.window_picker.size.y<=450,"Long application list is bounded on screen")
	view.window_picker.hide();app.application_access.windows=[]
	app.application_access.adopt({"handle":"123","target_pid":1234,"started":"567","title":"Synthetic editor","app":"Test"})
	app.goal_mode="proposal";app.goal_origin_target=app.application_access.target.duplicate(true);app.goal_deadline_ms=Time.get_ticks_msec()+30000
	app.goal_plan={"node":{"name":"Insert"}};view.refresh();await frame()
	check(view.confirmation_button.visible,"Proposed step approval is directly in native chat")
	shot(app.chat_window,"goal-proposal")
	for dimensions in [Vector2i(320,280),Vector2i(360,320),Vector2i(460,460)]:
		app.chat_window.size=dimensions;await frame()
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(view.editor.get_global_rect()),"Goal with pinned window preserves input "+str(dimensions))
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(view.confirmation_button.get_global_rect()),"Goal approval visible at "+str(dimensions))
	app.goal_mode="";app.goal_plan={};app.goal_origin_target={};app.goal_deadline_ms=0;app.application_access.clear_target()
	app.chat_window.size=Vector2i(460,460);view.refresh()

	for language in ["ru","en","zh-Hans"]:
		app.set_locale(language)
		main.open_panel("talk")
		panel.size=Vector2i(640,360)
		await frame()
		var bounds=Rect2(Vector2.ZERO,Vector2(panel.size))
		check(bounds.encloses(main.embedded_chat.editor.get_global_rect()),"Control panel input visible: "+language)
		check(bounds.encloses(main.embedded_chat.send_button.get_global_rect()),"Control panel send visible: "+language)
		shot(panel,"panel-"+language)
	main.open_panel("assistant_tools")
	panel.size=Vector2i(640,360)
	await frame()
	check(main.page_scroll.get_v_scroll_bar().max_value>main.page_scroll.size.y,"Long setup page has scroll range")
	shot(panel,"setup-scroll")
	main.open_panel("reminders")
	panel.size=Vector2i(800,360)
	await frame()
	check(not main.wide_layout and main.page_picker.visible,"Short wide window keeps all nine pages reachable")
	app.set_locale("ru")
	main.open_panel("character")
	panel.size=Vector2i(800,620)
	await frame()
	check(main.wide_layout,"Wide settings use side navigation")
	shot(panel,"studio-wide")
	main.open_panel("talk")
	await frame()
	main.embedded_chat.editor.text="draft survives adaptive navigation"
	panel.size=Vector2i(640,360)
	await frame()
	check(main.embedded_chat.editor.text=="draft survives adaptive navigation","Resize preserves unsent draft")
	for code in ["ru","en","zh-Hans"]:
		app.set_locale(code)
		app.desktop_companion.quick_menu.open_at(Vector2i(1360,760))
		await frame()
		var menu=app.desktop_companion.quick_menu
		check(menu.visible and menu.position.x+menu.size.x<=1366 and menu.position.y+menu.size.y<=768,"Action menu stays on screen "+code)
		if code=="ru":shot(menu,"actions")
		menu.hide()
	app.desktop_companion.quick_menu.buttons[1].pressed.emit()
	check(panel.visible and main.page=="assistant_tools","Action tile opens actual tools")
	app.set_paused(true)
	check(app.desktop_companion.reduced_motion,"Pause stops idle motion")
	app.set_paused(false)
	check(not app.desktop_companion.reduced_motion,"Resume restores motion preference")
	app.desktop_companion.set_reduced(true)
	check(app.desktop_companion.art.reduced,"Reduced motion freezes procedural deformation")
	app.desktop_companion.set_reduced(false)
	app.desktop_companion._menu_action(1)
	check(panel.visible,"Character menu opens settings")
	main._hide_panel()
	check(not panel.visible and app.desktop_companion.visible,"Closing panel keeps companion available")
	app.chat_window.hide()
	app.desktop_companion.hide()
	app.desktop_companion.position=Vector2i(-10000,-10000)
	app.desktop_companion.art.modulate.a=0
	app.desktop_companion.recover()
	await frame()
	check(app.desktop_companion.visible and root.mode==Window.MODE_WINDOWED,"Recover restores minimized main window")
	check(app.desktop_companion.position.x>=0 and app.desktop_companion.art.modulate.a==1,"Recover repairs offscreen position and zero alpha")
	shot(root,"recovered")
	var desktop=app.desktop_companion
	for bounds in [Rect2i(0,0,1366,300),Rect2i(-1280,0,1280,720),Rect2i(0,0,320,240)]:
		desktop.fit_to_bounds(bounds)
		check(bounds.encloses(Rect2i(desktop.position,desktop.size)),"Body fits changed display bounds "+str(bounds))
		check(desktop._hit_polygon.size()==desktop.normalized_outline.size(),"Click outline follows scale")
	desktop.recover()
	await frame()
	check(desktop.size==Vector2i(210,232),"Original size restored on normal monitor")
	main.open_panel("diagnostics")
	await create_timer(0.2).timeout
	await frame()
	check(app.diagnostics.values.get("process_bytes",0)>0,"Native panel displays actual process RSS")
	shot(panel,"diagnostics")
	panel.hide();app.chat_window.hide()
	desktop.set_reduced(true)
	desktop.art.rotation=0;desktop.effect_time=0
	await frame()
	var rig_image=root.get_texture().get_image()
	shot(root,"rig-rest")
	var reference=TextureRect.new()
	reference.texture=desktop.art.texture
	reference.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	reference.size=desktop.art.size
	desktop.canvas.add_child(reference)
	desktop.art.hide()
	await frame()
	var reference_image=root.get_texture().get_image()
	var reference_data=reference_image.get_data()
	var rig_data=rig_image.get_data()
	var solid=0;var missing=0
	for offset in range(3,reference_data.size(),4):
		if reference_data[offset]>200:
			solid+=1
			if rig_data[offset]<100:missing+=1
	print("RIG_COVERAGE missing=",missing," solid=",solid)
	check(solid>1000 and float(missing)/maxi(solid,1)<0.001,"Rig pieces cover at least 99.9% of original opaque silhouette")
	reference.queue_free();desktop.art.show()
	desktop.art.set_reduced(false)
	for clip in ["hello","thinking","talk","success","error","grab","walk","listen","stretch","settle"]:
		desktop.art.play(clip,1.5)
		await create_timer(0.48).timeout
		await frame()
		check(desktop.art.parts.size()==6 and desktop.art.parts.head.rotation!=0,"Articulated motion evaluates: "+clip)
		shot(root,"rig-"+clip)
	desktop.art.set_reduced(true)
	# Actual clipboard command with an injected owned provider and synthetic OS clipboard.
	var original_provider=app.provider
	var original_name=app.provider_name
	var fake=FakeTranslationProvider.new();app.add_child(fake)
	app.provider=fake;app.provider_name="local_worker";app.local_runtime.status="ai_ready"
	app.l10n.set_locale("ru")
	DisplayServer.clipboard_set("SYNTHETIC_CLIPBOARD_ONLY_731")
	app.submit("переведи буфер на английский")
	check(fake.received.size()==2 and fake.received[-1].content=="SYNTHETIC_CLIPBOARD_ONLY_731","Explicit command reads clipboard into the owned provider only")
	check(not app.messages.any(func(m):return "SYNTHETIC_CLIPBOARD_ONLY_731" in m.text),"Clipboard source absent from visible/saved messages")
	check(app.pending_user_text.is_empty(),"Clipboard source absent from conversation context")
	app.cancel()
	check(app.queued_translation.is_empty() and not app.translation_mode,"Translation cancel clears queued text and mode")
	app.provider=original_provider;app.provider_name=original_name;fake.queue_free()
	DisplayServer.clipboard_set("")
	var reminder=app.store.add_reminder("SYNTHETIC_NATIVE_REMINDER_731",1)
	app._schedule_reminders()
	var reminder_deadline=Time.get_ticks_msec()+5000
	while app.store.data.reminders.any(func(item):return item.id==reminder.item.id) and Time.get_ticks_msec()<reminder_deadline:await process_frame
	check(reminder.ok and app.messages.count({"speaker":"assistant","text":app.t("reminder_due",{"text":"SYNTHETIC_NATIVE_REMINDER_731"})})==1,"Real reminder timer notifies once")
	check(not app.store.data.reminders.any(func(item):return item.id==reminder.item.id),"Delivered reminder removed from persistent store")
	main.open_panel("reminders")
	await frame()
	app.submit("напомни через 5 минут SYNTHETIC_UI_REMINDER_731")
	await frame()
	check(main.content.find_children("*","Label",true,false).any(func(label):return "SYNTHETIC_UI_REMINDER_731" in label.text),"Open reminders page refreshes when chat creates an item")
	var cancel_buttons=main.content.find_children("*","Button",true,false)
	check(not cancel_buttons.is_empty(),"Reminder cancellation reachable")
	if not cancel_buttons.is_empty():cancel_buttons[0].pressed.emit()
	await frame()
	check(not app.store.data.reminders.any(func(item):return item.text=="SYNTHETIC_UI_REMINDER_731"),"Reminder page cancels its saved item")
	shot(panel,"reminders")
	app.desktop_companion.art.queue_free()
	app.desktop_companion.art=null
	app.desktop_companion._show_fallback()
	await frame()
	check(app.desktop_companion.canvas.has_node("RecoveryPanel"),"Missing-art fallback is visible and usable")
	shot(root,"fallback")
	print("DESKTOP_VISUAL_TESTS: %s checks, %s failures; real X11 rendering, synthetic data only; Windows not executed" %[checks,failures])
	quit(0 if failures==0 else 1)
