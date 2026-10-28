extends SceneTree
var failures=0
func _initialize():_run.call_deferred()
func _run():
	var output=OS.get_environment("COMPANION_VISUAL_OUTPUT")
	var app=root.get_node("App");app.show_desktop()
	await process_frame;await process_frame
	var desktop=app.desktop_companion
	desktop.set_process(false);desktop.set_character_scale(1.5);desktop.art.set_process(false)
	desktop.effect_kind="";desktop.effect_time=0;desktop.art.modulate.a=1
	root.size=Vector2i(316,380)
	var bg=ColorRect.new();bg.color=Color("#151a1b");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.z_index=-10;root.add_child(bg)
	var label=Label.new();label.position=Vector2(12,355);label.size=Vector2(292,20);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color",Color("#efb637"));root.add_child(label)
	var specs=[["scan","READ / VERIFY","scan"],["wait","WAIT FOR APPROVAL","wait"],["present","EXPLAIN",""],["celebrate","VERIFIED SUCCESS","success"],["curious","FOLLOW-UP",""],["salute","READY","wait"]]
	var index=0;var regions=desktop.region_updates
	for spec in specs:
		desktop.art.play(spec[0],2.0);label.text=spec[1]
		desktop.fx_kind=spec[2];desktop.fx_time=0.85 if not spec[2].is_empty() else 0.0
		for frame in range(16):
			desktop.art._process(0.1);desktop.fx_time=maxf(0,desktop.fx_time-0.1);desktop.canvas.queue_redraw()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("frame%03d.png" % index));index+=1
	if desktop.region_updates!=regions:failures+=1;push_error("Preview rebuilt the input region")
	print("MOTION_PREVIEW: %d frames, %d failures; rendered from actual procedural rig" %[index,failures])
	quit(0 if failures==0 else 1)
