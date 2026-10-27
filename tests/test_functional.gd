extends SceneTree
const Router=preload("res://src/core/router.gd")
const Memory=preload("res://src/core/conversation_memory.gd")
const Guard=preload("res://src/core/response_guard.gd")
var failures=0
var checks=0
class FakeProvider extends Node:
	var calls=0
	var received=[]
	func submit(messages,_options):calls+=1;received=messages;return true
	func cancel():pass
func _initialize():_run.call_deferred()
func check(ok,description):
	checks+=1
	if not ok:failures+=1;push_error(description)
func _run():
	var app=root.get_node("App")
	var router=Router.new()
	for text in ["Открой мне проводник","открой блокнот","Можешь открыть Steam?","Open calculator","Could you open Downloads please","打开记事本"]:
		var result=router.route(text)
		check(result.get("tool")=="apps.open","Natural open: "+text)
	check(router.route("open https://example.org/CaseSensitive?q=AbC").args.target=="https://example.org/CaseSensitive?q=AbC","URL case is preserved")
	for text in ["Как открыть проводник?","Не открывай браузер","I opened calculator yesterday","Что значит команда open?","Что ты умеешь?"]:
		check(router.route(text).kind=="chat","No unintended action: "+text)
	check(router.route("запомни: мой любимый цвет — красный").args.text=="мой любимый цвет — красный","Natural memory preserves wording")
	check(router.route("set timer for 2 minutes").args.seconds==120,"Natural timer units")
	check(router.route("поставь таймер на 0 минут").kind=="invalid","Timer bound")
	var memory=Memory.new()
	memory.path="user://test-conversation.json"
	memory.erase()
	var messages=[{"speaker":"user","text":"你好"},{"speaker":"assistant","text":"Привет"}]
	check(memory.save_history(messages),"Conversation written")
	var reopened=Memory.new();reopened.path=memory.path
	check(reopened.load_history() and reopened.messages==messages and reopened.turns.size()==2,"New instance restores messages and complete model turns")
	var file=FileAccess.open(memory.path,FileAccess.WRITE);file.store_string("{broken");file.close()
	var corrupt=Memory.new();corrupt.path=memory.path
	check(not corrupt.load_history() and not corrupt.save_history(messages),"Corrupt history is not overwritten")
	check(FileAccess.get_file_as_string(memory.path)=="{broken","Corrupt bytes preserved")
	check(corrupt.erase() and not FileAccess.file_exists(memory.path),"Explicit erase permits recovery")
	var notes=[{"text":"мой любимый цвет красный"},{"text":"My favorite editor is Godot"},{"text":"我最喜欢的颜色是黄色"}]
	for text in ["какой мой любимый цвет?","What is my favorite editor?","我喜欢什么颜色？"]:
		check(not memory.retrieve(text,notes).is_empty(),"Relevant notes retrieved: "+text)
	check(memory.retrieve("объясни солнечное затмение",notes).is_empty(),"Unrelated notes not injected")
	var guard=Guard.new()
	for text in ["Я открыла проводник.","Я уже запустил браузер.","I have opened calculator.","Проводник открыт.","我已经打开了记事本。"]:
		check(guard.claims_action(text,"ну так открой"),"Reject unverified completed action: "+text)
	check(not guard.claims_action("Земля вращается вокруг Солнца.","Расскажи о Земле"),"Ordinary fact allowed")
	check(not guard.claims_action("I opened the door.","translate this sentence"),"Translation is not a desktop action")
	check(not app.history_enabled(),"History private by default")
	var original=app.provider
	var fake=FakeProvider.new();app.add_child(fake);app.provider=fake
	app.l10n.set_locale("ru")
	app.local_ai_enabled=false
	app.submit("Объясни радугу")
	check(fake.calls==1 and app.state.current=="thinking","Conversation reaches inference provider")
	app._on_answer("Я открыла браузер.")
	check(app.state.current=="idle" and not app.messages[-1].text.contains("Я открыла"),"Unverified action never reaches the chat as success")
	app.submit("открой блокнот")
	await process_frame
	check(fake.calls==1,"Native launch bypasses LLM")
	if OS.get_name()!="Windows":
		await process_frame
		check(app.state.current=="idle" and app.messages[-1].text.contains("Windows"),"Unsupported host reports honestly")
	app.cancel();app.provider=original;fake.queue_free()
	app.diagnostics.active=true
	app.diagnostics.elapsed=5
	app.diagnostics._process(0.01)
	if OS.get_name()=="Linux":check(app.diagnostics.values.get("process_bytes",0)>0,"Actual Linux process RSS measured")
	app.diagnostics.active=false
	print("FUNCTIONAL_TESTS: %s checks, %s failures" % [checks,failures])
	quit(0 if failures==0 else 1)
