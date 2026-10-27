extends SceneTree
var checks=0
var failures=0
var app
func _initialize():_run.call_deferred()
func check(ok,text):
	checks+=1
	if not ok:failures+=1;push_error(text)
func wait_answer():
	var deadline=Time.get_ticks_msec()+60000
	while app.state.current!="idle" and Time.get_ticks_msec()<deadline:await process_frame
	check(app.state.current=="idle","Inference reaches terminal state")
func _run():
	app=root.get_node("App")
	app.local_ai_enabled=false
	app._set_provider("local_worker")
	app.provider.configure_local(int(OS.get_environment("COMPANION_TEST_PORT")),OS.get_environment("COMPANION_TEST_TOKEN"))
	app.local_runtime.status="ai_ready"
	for test in [
		["ru","Почему небо кажется голубым? Ответь одним предложением.",["свет","рассе","атмосфер"]],
		["en","Name the planet humans live on. One word.",["earth"]],
		["zh-Hans","人类生活在哪个星球？只用一个词回答。",["地球"]]]:
		app.l10n.set_locale(test[0]);app.session_turns=[]
		app.submit(test[1]);await wait_answer()
		var answer=str(app.messages[-1].text).to_lower()
		var relevant=false
		for word in test[2]:if word in answer:relevant=true
		check(relevant and "openai" not in answer,"Relevant answer in "+test[0])
		if test[0]=="ru":check("браузер" not in answer,"Science answer does not invent a browser task")
		print("REAL_DIALOGUE ",JSON.stringify({"locale":test[0],"input":test[1],"answer":app.messages[-1].text,"usage":app.provider.last_usage}))
	var translator=preload("res://src/tools/clipboard_translation.gd").new()
	for test in [["ru","The sun is bright.","солнц"],["en","今天是星期一。","monday"],["zh-Hans","The moon is bright.","月"]]:
		app.l10n.set_locale(test[0]);app.session_turns=[]
		var prepared=translator.prepare(test[1],test[0])
		app._submit_translation(prepared.messages)
		await wait_answer()
		check(test[2] in str(app.messages[-1].text).to_lower(),"Actual local translation "+test[0])
		check(app.session_turns.is_empty() and app.pending_user_text.is_empty(),"Clipboard source not retained in conversation context")
		print("REAL_TRANSLATION ",JSON.stringify({"locale":test[0],"input":test[1],"answer":app.messages[-1].text,"usage":app.provider.last_usage}))
	check(app.desktop_actions.pid<0 and app.desktop_actions.last_result.is_empty(),"Generated text causes no desktop effects")
	print("REAL_LEEMON_TESTS: %s checks, %s failures; unchanged Qwen3-1.7B Q8_0, CPU 2 threads" % [checks,failures])
	quit(0 if failures==0 else 1)
