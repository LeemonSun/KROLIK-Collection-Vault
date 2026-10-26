extends SceneTree
const Provider = preload("res://src/providers/llama_http_provider.gd")
var provider
var events = []
var failures = []
var checks = 0

func _initialize():
	_run.call_deferred()

func check(ok, message):
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func wait_event():
	var deadline = Time.get_ticks_msec() + 5000
	while events.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	return not events.is_empty()

func _run():
	provider = Provider.new()
	root.add_child(provider)
	provider.completed.connect(func(text): events.append(["ok", text]))
	provider.failed.connect(func(key): events.append(["error", key]))
	await process_frame
	for scenario in ["success","invalid_json","bad_shape","tool_only","http_error","redirect"]:
		events.clear()
		var accepted = provider.submit([{"role":"user","content":scenario}], {"max_tokens":99999})
		check(accepted, "Request accepted " + scenario)
		check(await wait_event(), "Request terminates " + scenario)
		if not events.is_empty():
			check(events[0][0] == ("ok" if scenario == "success" else "error"), "Response handled " + scenario)
		check(not provider.busy, "Busy flag cleared " + scenario)
	events.clear()
	provider.submit([{"role":"user","content":"slow"}])
	check(not provider.submit([]), "Concurrent request rejected")
	provider.cancel()
	await create_timer(0.5).timeout
	check(events.is_empty(), "Canceled answer not delivered")
	check(not provider.busy, "Cancel clears busy")
	print("HTTP_TESTS: %s checks, %s failures" % [checks, failures.size()])
	provider.queue_free()
	quit(0 if failures.is_empty() else 1)

