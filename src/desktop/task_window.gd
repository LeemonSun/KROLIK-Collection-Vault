extends Window
## Independent event-driven task/review card. No inference, screenshots or helper polling.
const V=preload("res://src/ui/visual_theme.gd")
const Presenter=preload("res://src/core/orbit_presentation.gd")
var app
var surface
var heading
var detail
var source
var primary
var cancel_button
var choices
var meter
var snapshot={}
var cancel_serial=0
var active_last=false
var suppressed=false
var dismissed_token=""
var refresh_pending=false
var transition
var fingerprint=""
var ttl
func _init():
	visible=false;borderless=true;disable_3d=true;always_on_top=false;transient=true;transparent=true;transparent_bg=true
	size=Vector2i(400,290);min_size=Vector2i(300,240)
func _ready():
	app=get_tree().root.get_node("App");title="Leemon"
	surface=preload("res://src/ui/leemon_surface.gd").new();surface.inset=12;surface.theme=V.make();surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(surface)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",8);surface.add_child(column)
	var header=preload("res://src/ui/window_handle.gd").new();column.add_child(header)
	var glyph=Label.new();glyph.text="◉";glyph.modulate=V.RED;header.add_child(glyph)
	heading=Label.new();heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;heading.add_theme_font_size_override("font_size",17);header.add_child(heading)
	var close=Button.new();close.text="×";V.quiet(close);close.pressed.connect(dismiss);header.add_child(close)
	source=Label.new();source.add_theme_font_size_override("font_size",11);source.modulate=V.MUTED;source.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;column.add_child(source)
	var scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	detail=RichTextLabel.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.bbcode_enabled=false;detail.selection_enabled=true;detail.fit_content=true;detail.scroll_active=false;detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;detail.add_theme_font_size_override("normal_font_size",15);detail.add_theme_constant_override("line_separation",5);scroll.add_child(detail)
	choices=OptionButton.new();choices.fit_to_longest_item=false;choices.clip_text=true;choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_child(choices)
	meter=Label.new();meter.modulate=V.MUTED;meter.add_theme_font_size_override("font_size",11);column.add_child(meter)
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",10);column.add_child(row)
	primary=Button.new();primary.size_flags_horizontal=Control.SIZE_EXPAND_FILL;primary.custom_minimum_size.y=36;primary.pressed.connect(accept_current);V.primary(primary);row.add_child(primary)
	cancel_button=Button.new();cancel_button.custom_minimum_size.y=36;cancel_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cancel_button.pressed.connect(func():
		if snapshot.get("kind")!="result":app.cancel()
		dismiss());row.add_child(cancel_button)
	app.changed.connect(schedule_refresh);app.message_added.connect(func(_speaker,_text):schedule_refresh())
	close_requested.connect(dismiss)
	ttl=Timer.new();ttl.wait_time=0.5;ttl.timeout.connect(_tick);add_child(ttl)
	window_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:dismiss())
func schedule_refresh():
	if refresh_pending:return
	refresh_pending=true;refresh.call_deferred()
func refresh():
	refresh_pending=false
	if is_instance_valid(app.chat_window) and app.chat_window.visible:
		hide();ttl.stop();active_last=false;fingerprint="";return
	var next=Presenter.snapshot(app)
	if next.is_empty():
		dismissed_token="";fingerprint=""
		if suppressed:suppressed=false;active_last=false;return
		if active_last:
			if cancel_serial!=app.cancel_serial:active_last=false;dismiss(false);snapshot={};return
			active_last=false
			if app.paused:dismiss();return
			var last=app.messages[-1] if not app.messages.is_empty() else {}
			if last.get("speaker")=="assistant":
				snapshot={"kind":"result","detail":str(last.text),"heading":app.t("orbit_task_result"),"identity":"","token":"","choices":[]};_render(false)
			else:dismiss()
		return
	if suppressed:return
	if not active_last:cancel_serial=app.cancel_serial
	active_last=true
	var key=JSON.stringify(next)
	if key==dismissed_token:return
	var opening=not visible
	snapshot=next
	if key!=fingerprint:fingerprint=key;_render(opening)
func _render(opening):
	heading.text=snapshot.heading;detail.text=snapshot.detail;source.text=snapshot.identity;source.visible=not source.text.is_empty()
	choices.visible=snapshot.kind=="choice";choices.clear()
	for item in snapshot.choices:
		choices.add_item(str(item.get("name",item.get("node",{}).get("name",""))).left(140))
	primary.visible=snapshot.kind in ["review","choice","result"]
	primary.text=app.t("orbit_approve" if snapshot.kind=="review" else ("orbit_go" if snapshot.kind=="choice" else "talk"))
	cancel_button.text=app.t("orbit_close" if snapshot.kind=="result" else "cancel")
	_tick()
	if opening:
		var anchor=Rect2i(app.desktop_companion.position,app.desktop_companion.size) if is_instance_valid(app.desktop_companion) else Rect2i(Vector2i(20,20),Vector2i(100,100))
		var screen=DisplayServer.get_screen_from_rect(anchor);var bounds=DisplayServer.screen_get_usable_rect(screen if screen>=0 else DisplayServer.get_primary_screen())
		size=Vector2i(mini(400,bounds.size.x),mini(290,bounds.size.y));position=preload("res://src/desktop/companion_behavior.gd").bubble_position(anchor,bounds,size)
		surface.modulate.a=1;show();DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,get_window_id());app.mark_active()
		if not app.motion.reduced_motion and not app.paused:
			if transition:transition.kill()
			surface.modulate.a=0.25;transition=create_tween();transition.tween_property(surface,"modulate:a",1.0,0.18)
		if is_instance_valid(app.desktop_companion):app.desktop_companion.perform_gesture("offer",1.2,2)
	if snapshot.kind=="review":ttl.start()
	else:ttl.stop()
func _tick():
	meter.visible=snapshot.get("kind")=="review"
	if meter.visible:meter.text=app.t("approval_remaining",{"seconds":maxi(0,ceili((app.goal_deadline_ms-Time.get_ticks_msec())/1000.0))})
	primary.disabled=not Presenter.review_live(app,snapshot.token) if meter.visible else false
func accept_current():
	var kind=snapshot.get("kind","")
	if kind=="review":
		if Presenter.review_live(app,snapshot.token):app.confirm_window_goal()
		else:schedule_refresh()
	elif kind=="choice":
		if not Presenter.choice_live(app,snapshot.token):schedule_refresh();return
		if not app.discovery_candidates.is_empty():app.choose_discovered_app(choices.selected)
		else:app.choose_browser_tab(choices.selected)
	elif kind=="result":app.show_chat();dismiss()
func dismiss(suppress=true):
	if suppress and snapshot.get("kind") not in ["result",null]:suppressed=true
	dismissed_token=JSON.stringify(snapshot) if snapshot.get("kind")!="result" else ""
	if transition:transition.kill()
	if is_instance_valid(ttl):ttl.stop()
	hide()
