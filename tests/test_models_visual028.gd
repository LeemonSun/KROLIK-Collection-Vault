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
func run():
	var app=root.get_node("App");app.set_locale("ru")
	var boot=load("res://scenes/bootstrap.tscn").instantiate();root.add_child(boot)
	await create_timer(.8).timeout
	boot.main_view.open_panel("assistant_tools");await frame()
	var panel
	for child in boot.main_view.content.get_children():
		if child.get_script()==preload("res://src/ui/model_panel.gd"):panel=child
	check(is_instance_valid(panel),"Model selection is part of purposeful settings, not another floating window")
	check(panel.picker.item_count==13,"All13 candidates visible in one dropdown")
	check(not boot.panel_window.always_on_top,"Model settings do not obscure other applications persistently")
	panel.picker.select(5);panel.picker.item_selected.emit(5);await frame()
	check(app.model_library.selected=="gemma4_e2b" and panel.import_button.visible,"Selecting Gemma4 exposes actual file import")
	check(not app.local_runtime.installed() and not panel.state.text.is_empty(),"Uninstalled candidate is represented truthfully")
	check(app.t("models_vision_off") in panel.info.text,"Foreign projector is visibly disabled")
	panel.test_toggle.button_pressed=true;await frame()
	check(app.model_test_mode and app.session_turns.is_empty(),"Comparison toggle resets context")
	check(boot.main_view.page_scroll.get_combined_minimum_size().x<=boot.panel_window.size.x,"Settings remain within ordinary window width")
	var output=OS.get_environment("COMPANION_VISUAL_OUTPUT")
	if not output.is_empty():
		await frame();boot.panel_window.get_viewport().get_texture().get_image().save_png(output.path_join("models028.png"))
	app.select_model("qwen35_2b");app.set_model_test_mode(false);app.cancel()
	print("MODELS_VISUAL028: %d checks, %d failures; actual X11 rendering, not Windows file picker or neural acceptance" %[checks,failures]);quit(0 if failures==0 else 1)
