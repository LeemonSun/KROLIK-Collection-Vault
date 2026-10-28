extends SceneTree
const ChatView=preload("res://src/ui/chat_view.gd")
var checks=0
var failures=0
func _initialize():
	_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func _run():
	var app=root.get_node("App")
	var before=app.messages.duplicate(true)
	app.application_access.adopt({"handle":"123","target_pid":234,"started":"345","title":"Synthetic selected window","app":"Test"})
	app.messages=[{"speaker":"assistant","text":"Длинный ответ / 中文 / English. ".repeat(150)}]
	for locale in ["ru","en","zh-Hans"]:
		app.l10n.set_locale(locale)
		for dimensions in [Vector2i(320,280),Vector2i(360,320),Vector2i(480,360),Vector2i(800,600)]:
			root.size=dimensions
			var view=ChatView.new()
			view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			root.add_child(view)
			await process_frame
			await process_frame
			var bounds=Rect2(Vector2.ZERO,Vector2(dimensions))
			check(bounds.encloses(view.editor.get_global_rect()),"Composer inside %s %s actual=%s panel=%s viewport=%s minimum=%s" %[locale,dimensions,view.editor.get_global_rect(),view.get_global_rect(),root.get_visible_rect(),view.get_combined_minimum_size()])
			check(bounds.encloses(view.send_button.get_global_rect()),"Send inside %s %s" %[locale,dimensions])
			check(view.history.scroll_active and view.history.get_v_scroll_bar().max_value>view.history.size.y,"Long reply scrollable")
			check(view.editor.editable,"Editable composer")
			view.editor.text="unsubmitted draft"
			app.changed.emit()
			check(view.editor.text=="unsubmitted draft","Status refresh preserves draft")
			view.editor.text="x".repeat(2049)
			view.submit_current()
			check(view.editor.text.length()==2049,"Oversized paste retained")
			app.goal_mode="proposal";app.goal_deadline_ms=Time.get_ticks_msec()+30000
			app.goal_plan={"node":{"name":"Insert"}}
			view.refresh()
			await process_frame
			check(view.confirmation_button.visible and bounds.encloses(view.confirmation_button.get_global_rect()),"Goal approval fits "+str(dimensions))
			check(bounds.encloses(view.editor.get_global_rect()),"Goal review preserves visible composer "+str(dimensions))
			view.editor.text="keep this draft";view.submit_current()
			check(view.editor.text=="keep this draft","Busy goal never consumes an unsent draft")
			app.goal_mode="";app.goal_plan={};app.goal_deadline_ms=0
			app.window_read_mode="thinking";app.window_read_deadline=Time.get_ticks_msec()+30000;app.state.transition("thinking")
			view.refresh();await process_frame
			check(view.read_button.disabled and view.inspect_button.disabled and view.plan_button.disabled,"No competing observations during read")
			check(view.status_label.text==app.t("window_read_status_thinking"),"Localized read progress")
			if view.target_row.visible:check(bounds.encloses(view.read_button.get_global_rect()),"Read toolbar stays inside pinned-window chat")
			app.window_read_mode="";app.window_read_deadline=0;app.state.reset()
			view.queue_free()
			await process_frame
	app.application_access.clear_target()
	root.size=Vector2i(800,600)
	var view=ChatView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)
	await process_frame
	app.messages.clear()
	view.editor.text="hello from visible composer"
	view.submit_current()
	check(view.editor.text.is_empty(),"Accepted message clears composer")
	check(app.messages.size()>=2 and app.messages[0].text=="hello from visible composer","Chat actually submits to app")
	view.queue_free()
	await process_frame
	app.messages=before
	print("CHAT_LAYOUT_TESTS: %s checks, %s failures; 3 locales x 4 sizes" %[checks,failures])
	quit(0 if failures==0 else 1)
