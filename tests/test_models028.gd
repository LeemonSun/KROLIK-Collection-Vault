extends SceneTree
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func string_value(f,text):
	var bytes=text.to_utf8_buffer();f.store_64(bytes.size());f.store_buffer(bytes)
func fixture(path,architecture,parts=1):
	var f=FileAccess.open(path,FileAccess.WRITE);f.store_buffer("GGUF".to_ascii_buffer());f.store_32(3);f.store_64(1);f.store_64(3)
	string_value(f,"general.architecture");f.store_32(8);string_value(f,architecture)
	string_value(f,"general.name");f.store_32(8);string_value(f,"Synthetic metadata fixture, NOT usable neural weights")
	string_value(f,"split.count");f.store_32(2);f.store_16(parts);f.close()
func wait_import(library):
	var deadline=Time.get_ticks_msec()+5000
	while library.thread!=null and Time.get_ticks_msec()<deadline:await process_frame
func run():
	var app=root.get_node("App")
	var Inspector=preload("res://src/runtime/gguf_inspector.gd")
	var Library=preload("res://src/runtime/model_library.gd")
	var file="user://synthetic-model028.gguf"
	fixture(file,"qwen3")
	check(Inspector.new().inspect(file).get("general.architecture")=="qwen3","Reads GGUF metadata without executing/loading neural tensors")
	fixture(file,"qwen3",2)
	check(Inspector.new().inspect(file).is_empty(),"Rejects split-part models")
	var bad=FileAccess.open("user://bad028.gguf",FileAccess.WRITE);bad.store_string("not a model");bad.close()
	check(Inspector.new().inspect("user://bad028.gguf").is_empty(),"Rejects invalid/short GGUF")
	fixture(file,"qwen3")
	var library=Library.new();library.path="user://model-test028.json";root.add_child(library)
	check(library.catalog.size()==13,"All13 reviewed candidate profiles available")
	check(library.import_file("qwen3_4b",file),"Starts background metadata/hash import")
	await wait_import(library)
	check(library.status=="models_imported" and library.available("qwen3_4b"),"Imports user-picked file without a duplicate or a fake upstream hash")
	check(library.import_file("gemma4_e2b",file),"Can inspect candidate under selected profile")
	await wait_import(library)
	check(library.status=="models_invalid" and library.record("gemma4_e2b").is_empty(),"Rejects wrong architecture rather than starting wrong family")
	check(library.choose("qwen3_4b"),"Saves selection")
	var restored=Library.new();restored.path=library.path;root.add_child(restored)
	check(restored.selected=="qwen3_4b" and restored.available("qwen3_4b"),"Reloads JSON numeric receipt sizes/mtime and selected profile")
	var runtime=preload("res://src/runtime/local_runtime.gd").new();root.add_child(runtime)
	var original=runtime.model_path()
	check(runtime.select_external(library.record("qwen3_4b")) and runtime.model_path()==file,"External model path replaces only selected weights")
	check(not runtime.installed(),"Imported header cannot impersonate installed runtime")
	var part=FileAccess.open(file+".part",FileAccess.WRITE);part.store_string("user-owned");part.close()
	runtime.cancel_install()
	check(FileAccess.file_exists(file+".part"),"Cancel installer never deletes user-adjacent external files")
	runtime.pid=99999999
	check(not runtime.select_external({}),"Runtime cannot change paths while owned worker is still active")
	runtime.pid=-1
	check(runtime.select_external({}) and runtime.model_path()==original,"Baseline restores its own model and configuration")
	var before=app.model_library.selected
	app.session_turns=[{"role":"user","content":"old model secret"}]
	check(app.select_model("qwen3_4b") and app.session_turns.is_empty() and app.provider_name=="unconfigured","App switch resets context/provider before next candidate")
	check(not app.local_runtime.installed() and not app.local_runtime.custom_model.is_empty(),"Unimported candidate cannot silently fall back to baseline")
	check(app.select_model(before),"Can return to previous model")
	app.set_model_test_mode(true)
	check(app.runtime_options().context_tokens==4096 and app.runtime_options().cpu_threads==2,"Comparison mode has matched resource settings")
	var transcript=preload("res://src/core/chat_transcript.gd").format([{"speaker":"assistant","text":"answer","model_name":"Test Model","response_ms":1200}],"YOU")
	check(transcript.ok and "Test Model" in transcript.text and "1.20 s" in transcript.text,"Copied comparison retains model and latency")
	var memory=preload("res://src/core/conversation_memory.gd").new();memory.path="user://context-boundary028.json"
	check(memory.save_history([{"speaker":"user","text":"old"},{"speaker":"assistant","text":"old answer","context_reset":true},{"speaker":"user","text":"new"},{"speaker":"assistant","text":"new answer"}]),"Saves visible transcript with context boundary")
	check(memory.load_history() and memory.messages.size()==4 and memory.turns.size()==2 and memory.turns[0].content=="new","After restart old model conversation stays visible but cannot leak into new context")
	runtime.model_change_busy=true
	check(not runtime.start(),"Cannot start inference during model import")
	runtime.model_change_busy=false
	app.set_model_test_mode(false)
	if OS.get_name()=="Linux":
		var heartbeat=ProjectSettings.globalize_path("user://switch028-heartbeat-"+str(Time.get_ticks_usec())+".txt")
		var code="import sys,time\nfor i in range(600):\n with open(sys.argv[1],'a') as f:f.write('x')\n time.sleep(.05)"
		var child=OS.create_process("/usr/bin/python3",["-c",code,heartbeat],false)
		app.local_runtime.pid=child
		var deadline=Time.get_ticks_msec()+5000
		while not FileAccess.file_exists(heartbeat) and Time.get_ticks_msec()<deadline:await process_frame
		check(FileAccess.file_exists(heartbeat),"Actual owned synthetic helper running before switch")
		app.select_model("qwen3_4b");await create_timer(.2).timeout
		var count=FileAccess.get_file_as_bytes(heartbeat).size();await create_timer(.2).timeout
		check(count>0 and FileAccess.get_file_as_bytes(heartbeat).size()==count and app.local_runtime.pid==-1,"Switch kills actual old compute; no second worker remains")
		app.select_model(before)
	for node in [library,restored,runtime]:node.queue_free()
	print("MODELS028: %d checks, %d failures; synthetic metadata/real owned helper, NOT model quality or Windows acceptance" %[checks,failures])
	quit(0 if failures==0 else 1)
