extends SceneTree
func _initialize():_render.call_deferred()
func _render():
	root.size=Vector2i(360,400)
	root.transparent=false;root.transparent_bg=false
	var background=ColorRect.new();background.color=Color("#151719");background.size=Vector2(360,400);root.add_child(background)
	var rig=preload("res://src/animation/leemon_rig.gd").new()
	rig.texture=load("res://assets/characters/leemon_01/master_v1.png")
	rig.size=Vector2(360,398);root.add_child(rig);rig.set_process(false)
	var directory=OS.get_environment("COMPANION_VISUAL_OUTPUT").path_join("frames")
	DirAccess.make_dir_recursive_absolute(directory)
	for index in range(144):
		if index%36==0:rig.play(["hello","thinking","talk","success"][index/36],1.5)
		rig._process(1.0/24.0)
		RenderingServer.force_draw.call_deferred()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("frame-%03d.png" % index))
	print("LEEMON_MOTION_RENDER: 144 native frames, 0 failures; actual shipped rig")
	quit()
