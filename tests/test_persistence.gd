extends SceneTree
func _initialize():_run.call_deferred()
func _run():
	var app=root.get_node("App")
	var stage=OS.get_environment("COMPANION_PERSIST_STAGE")
	if stage=="write":
		app.set_history_enabled(true)
		app.add_message("user","Synthetic restart test / 重启 / перезапуск")
		app.add_message("assistant","Saved synthetic answer")
		if not app.memory.save_history(app.messages):push_error("Write failed");quit(1);return
		print("PERSISTENCE_WRITE_OK")
	elif stage=="read":
		if not app.history_enabled() or not app.messages.any(func(m):return m.text=="Synthetic restart test / 重启 / перезапуск") or app.session_turns.size()<2:
			push_error("Actual second process did not restore history");quit(1);return
		if not app.clear_history_confirmed() or FileAccess.file_exists(app.memory.path) or not app.messages.is_empty():
			push_error("Erase failed");quit(1);return
		app.set_history_enabled(false)
		print("PERSISTENCE_RESTART_AND_ERASE_OK")
	else:push_error("Test stage required");quit(1);return
	quit()
