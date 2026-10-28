extends SceneTree
var checks=0
var failures=0
var app
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func ask(text,worker):
	worker.generation_busy=true;worker.touch();app.submit(text)
	var deadline=Time.get_ticks_msec()+60000
	while app.state.current!="idle" and Time.get_ticks_msec()<deadline:await process_frame
	check(app.state.current=="idle","Conversation reaches a terminal state")
	worker.generation_busy=false;worker.touch()
	var reply=str(app.messages[-1].text)
	print("REAL_CONVERSATION ",JSON.stringify({"locale":app.l10n.locale,"question":text,"answer":reply,"usage":app.provider.last_usage}))
	return reply.to_lower()
func _run():
	app=root.get_node("App")
	var path=OS.get_environment("COMPANION_CONVERSATION_FIXTURE")
	if path.is_empty():push_error("An actual model fixture is required");quit(1);return
	var worker=preload("res://src/runtime/local_runtime.gd").new();worker.base_path=path;worker.manifest=JSON.parse_string(FileAccess.get_file_as_string(path.path_join("fixture.json")));root.add_child(worker)
	check(worker.start({"cpu_threads":2,"context_tokens":2048}),"Owned compact model starts")
	var deadline=Time.get_ticks_msec()+90000
	while worker.status=="ai_starting" and Time.get_ticks_msec()<deadline:await process_frame
	check(worker.status=="ai_ready","Owned local worker authenticated")
	app._set_provider("local_worker");app.provider.configure_local(worker.port,worker.token);app.local_ai_enabled=true;app.local_runtime.status="ai_ready"
	var specs=[
		["ru","В нашем примере проект называется Сосна. Ответь кратко.","Как называется наш проект?","сосна","А по-английски это что за дерево?","pine"],
		["en","Our example project is called Birch. Answer briefly.","What is its name?","birch","Is that a tree or an animal?","tree"],
		["zh-Hans","我们这个对话中的示例项目叫松树。简短回答。","这个项目叫什么？","松树","它属于植物还是动物？","植物"]]
	if OS.get_environment("COMPANION_SMALLTALK_ONLY")=="1":specs=[]
	for spec in specs:
		app.l10n.set_locale(spec[0]);app.session_turns=[]
		var acknowledgement=await ask(spec[1],worker)
		if spec[0]=="en":check("desktop companion" not in acknowledgement and "linux" not in acknowledgement,"User project is not filled with invented app-persona details")
		var reply=await ask(spec[2],worker)
		check(spec[3] in reply,"Recent named subject retained "+spec[0])
		reply=await ask(spec[4],worker)
		check(spec[5] in reply,"Short follow-up resolves the previous subject "+spec[0])
		if spec[0]=="zh-Hans":check("没有生命活动" not in reply,"Correct category does not carry the observed false biological claim")
		check(app.provider.request_messages.is_empty(),"Adapter releases conversation request")
	app.l10n.set_locale("ru");app.session_turns=[]
	var first=await ask("У меня день прошёл нормально, все дела закончил. А у тебя?",worker)
	var second=await ask("У меня день прошёл нормально, все дела закончил. А у тебя?",worker)
	check(first!=second and second!=app.t("model_repeated").to_lower(),"Repeated small talk gets a usable non-looping answer")
	check("отчет" not in (first+second).replace("ё","е") and "подготовил" not in first+second,"Small talk does not invent the observed report-writing work")
	check(app.desktop_actions.pid<0,"Dialogue cannot create desktop effects")
	worker.stop();worker.queue_free();app.cancel()
	print("CONVERSATION_REAL_TESTS: %d checks, %d failures; actual 2B model, CPU2 threads; narrow quality sample" %[checks,failures])
	quit(0 if failures==0 else 1)
