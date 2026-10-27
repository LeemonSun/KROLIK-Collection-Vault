extends SceneTree
const Screen=preload("res://src/tools/screen_context.gd")
const Runtime=preload("res://src/runtime/local_runtime.gd")
const Adapter=preload("res://src/providers/llama_http_provider.gd")
var checks=0
var failures=0
var result=""
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _run():
	check(Screen.encode(null).is_empty(),"No invented image on capture failure")
	var image=Image.create(2000,1000,false,Image.FORMAT_RGB8);image.fill(Color.WHITE)
	var frame=Screen.encode(image)
	check(frame.get("width")==640 and frame.get("height")==320,"Image is bounded with aspect preserved")
	check(frame.url.begins_with("data:image/jpeg;base64,"),"Image stays an in-memory JPEG data URL")
	check(Screen.fresh(frame,Time.get_ticks_msec()),"Fresh frame accepted")
	check(not Screen.fresh(frame,int(frame.captured_ms)+30001),"No stale screen is described as current")
	check(not Screen.fresh(frame,int(frame.captured_ms)-1),"Invalid time rejected")
	var messages=Screen.messages(frame,"x".repeat(900),"zh-Hans")
	check(messages.size()==2 and messages[1].content[0].text.length()==600,"No chat history in image request; bounded question")
	check("Simplified Chinese" in messages[0].content and "untrusted" in messages[0].content,"Screen text is data and requested locale honored")
	var app=root.get_node("App")
	app.screen_mode=true;app.vision_frame=frame;app.vision_question="private"
	app.cancel()
	check(app.vision_frame.is_empty() and app.vision_question.is_empty() and not app.screen_mode,"Cancellation clears all retained screen data")
	var engine=Runtime.new();engine.manifest={"model":{"file":"t"},"runtime":{}}
	var args=engine.build_args({"vision_projector":"/test/owned.gguf","cpu_threads":2},16)
	check("--mmproj" in args and args[args.find("--image-max-tokens")+1]=="256","Bounded shared text/vision runtime arguments")
	check("--log-disable" in args and "--no-mmproj-offload" in args,"No screenshot/prompt server logs and CPU projector")
	engine.free()
	var path=OS.get_environment("COMPANION_VISION_FIXTURE")
	if not path.is_empty():
		engine=Runtime.new();engine.base_path=path
		engine.manifest=JSON.parse_string(FileAccess.get_file_as_string(path.path_join("fixture.json")))
		root.add_child(engine)
		check(engine.installed(),"Pinned actual 2B fixture installed")
		check(engine.start({"cpu_threads":2,"context_tokens":2048,"vision_projector":path.path_join("mmproj.gguf")}),"Actual model+projector starts")
		var start=Time.get_ticks_msec()
		while engine.status=="ai_starting" and Time.get_ticks_msec()-start<45000:await process_frame
		check(engine.status=="ai_ready","Authenticated vision readiness")
		var adapter=Adapter.new();root.add_child(adapter)
		adapter.configure_local(engine.port,engine.token)
		adapter.completed.connect(func(text):result=text)
		adapter.failed.connect(func(key):result="ERROR:"+key)
		var fixture=Image.load_from_file(OS.get_environment("COMPANION_VISION_IMAGE"))
		frame=Screen.encode(fixture)
		for spec in [["ru","Какое слово на кнопке справа внизу? Только слово.","SAVE"],["en","How many red squares? One number.","3"],["zh-Hans","Total的数值？只回答数字。","42"]]:
			result="";engine.generation_busy=true
			adapter.submit(Screen.messages(frame,spec[1],spec[0]),{"multimodal":true,"max_tokens":32})
			start=Time.get_ticks_msec()
			while result.is_empty() and Time.get_ticks_msec()-start<60000:await process_frame
			check((spec[2] in result if spec[2]!="3" else ("3" in result or "three" in result.to_lower())),"Actual Godot → JPEG → HTTP → VLM "+spec[0]+" result="+result)
			check(adapter.request_messages.is_empty(),"No retained image in adapter after response")
		engine.stop();adapter.queue_free();engine.queue_free()
	print("VISION_TESTS: %s checks, %s failures; real_fixture=%s" %[checks,failures,not path.is_empty()])
	quit(0 if failures==0 else 1)
