extends SceneTree
const Runtime = preload("res://src/runtime/local_runtime.gd")
const Adapter = preload("res://src/providers/llama_http_provider.gd")
var checks = 0
var failures = 0
var answer = ""
var worker
func _initialize():
	_run.call_deferred()
func check(value, label):
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _run():
	var engine = Runtime.new()
	engine.manifest = {"model":{"file":"test.gguf"},"runtime":{}}
	engine.port = 28763
	engine.token = "a".repeat(64)
	var args = engine.build_args({"cpu_threads":200,"context_tokens":999999},16)
	check(args[args.find("--host")+1] == "127.0.0.1", "Worker binds loopback only")
	check(args[args.find("--threads")+1] == "8", "Thread bound")
	check(args[args.find("--ctx-size")+1] == "4096", "Context bound")
	check(args[args.find("--parallel")+1] == "1", "Single inference slot")
	check(args[args.find("--n-gpu-layers")+1] == "0", "Portable CPU fallback")
	check(args[args.find("--poll")+1] == "0", "No busy polling")
	check("--api-key" in args and "--no-ui" in args, "Authenticated worker without web UI")
	check(not engine.installed(), "No fake installation receipt")
	engine.downloading = true
	engine.status = "ai_downloading_model"
	check(not engine.start() and engine.status == "ai_downloading_model", "Start cannot corrupt install status")
	engine.free()
	var adapter = Adapter.new()
	root.add_child(adapter)
	check(not adapter.configure_local(0,"a".repeat(64)), "Invalid port")
	check(not adapter.configure_local(40000,"https://foreign.example"), "Invalid auth token")
	check(adapter.configure_local(40000,"a".repeat(64)), "Dynamic authenticated local endpoint")
	check(adapter.endpoint == "http://127.0.0.1:40000/v1/chat/completions", "No arbitrary endpoint")
	adapter.queue_free()
	var path = OS.get_environment("COMPANION_RUNTIME_FIXTURE")
	if not path.is_empty():
		worker = Runtime.new()
		worker.base_path = path
		worker.manifest = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("fixture.json")))
		root.add_child(worker)
		check(worker.installed(), "Pinned real fixture recognized")
		check(worker.start({"cpu_threads":2,"context_tokens":2048}), "Owned real worker starts")
		var start = Time.get_ticks_msec()
		while worker.status == "ai_starting" and Time.get_ticks_msec()-start < 30000:
			await process_frame
		check(worker.status == "ai_ready", "Authenticated model readiness")
		var owned_pid = worker.pid
		var real = Adapter.new()
		root.add_child(real)
		real.configure_local(worker.port, worker.token)
		real.completed.connect(func(text): answer = text)
		real.failed.connect(func(key): answer = "ERROR:" + key)
		worker.generation_busy = true
		real.submit([{"role":"system","content":"Answer briefly in English."},{"role":"user","content":"Why do plants need light? One sentence."}],{"max_tokens":80})
		start = Time.get_ticks_msec()
		while answer.is_empty() and Time.get_ticks_msec()-start < 60000:
			await process_frame
		check(not answer.is_empty() and not answer.begins_with("ERROR:"), "Real response through app adapter")
		real.cancel()
		real.queue_free()
		worker.generation_busy = false
		worker.touch()
		worker.idle_seconds = 1
		await create_timer(1.5).timeout
		check(worker.pid == -1 and worker.status == "ai_sleeping", "Idle unload stops worker")
		await create_timer(0.1).timeout
		check(not FileAccess.file_exists("/proc/%s/stat" % owned_pid), "Worker process actually stopped")
		check(worker.start({"cpu_threads":2}), "Worker restarts after unload")
		owned_pid = worker.pid
		worker.stop()
		await create_timer(0.1).timeout
		check(worker.pid == -1 and not FileAccess.file_exists("/proc/%s/stat" % owned_pid), "Startup cancellation stops process")
		worker.queue_free()
	var budget=preload("res://src/runtime/local_runtime.gd").new();budget.manifest={"model":{"bytes":1280835840}}
	check(not budget.memory_headroom({}, {"available":1024*1024*1024,"physical":8*1024*1024*1024}),"Low available RAM blocks a new heavy model load")
	check(budget.memory_headroom({}, {"available":4*1024*1024*1024,"physical":8*1024*1024*1024}),"Conservative text load fits with OS reserve")
	check(not budget.memory_headroom({"vision_projector":"paired"}, {"available":3*1024*1024*1024,"physical":8*1024*1024*1024}),"Vision accounts for additional projector memory")
	budget.free()
	print("LOCAL_RUNTIME_TESTS: %s checks, %s failures; real_fixture=%s" % [checks, failures, not path.is_empty()])
	quit(0 if failures == 0 else 1)
