extends SceneTree
var checks=0
var failures=0
class WakeRuntime extends Node:
	var status="ai_installed"
	var manifest={}
	var calls=0
	var pid=-1
	var generation_busy=false
	var starting=false
	func installed():return true
	func start(_options):calls+=1;status="ai_starting";return true
	func touch():pass
	func stop():pass
class QuietProvider extends Node:
	var calls=0
	func submit(_messages,_options):calls+=1;return true
	func cancel():pass
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _run():
	var app=root.get_node("App")
	var router=preload("res://src/core/router.gd").new()
	for phrase in ["создай в блакноте новый файл","создай файл в блокноте","create a new file in notepad","在记事本中新建文件"]:
		check(router.route(phrase).get("tool")=="documents.create","Actual new document routing: "+phrase)
	check(router.route("создай файл в блокноте: Привет, 世界!\nВторая строка.").args.text=="Привет, 世界!\nВторая строка.","Exact Unicode, case, punctuation and newlines survive command parsing")
	for phrase in ["не создавай файл в блокноте","как создать файл в блокноте?","напиши рассказ про лимон","write a story about a document"]:
		check(router.route(phrase).kind=="chat","Discussion or prose is not a desktop effect: "+phrase)
	for phrase in ["вставь текст в блокнот","удали этот файл","type this in notepad"]:
		check(router.route(phrase).get("key")=="desktop_edit_unavailable","Unimplemented external editing bypasses model: "+phrase)
	var guard=preload("res://src/core/response_guard.gd").new()
	for phrase in ["Создан новый файл в блокноте.","Файл сохранён.","Создана новая вкладка.","Created a new file in Notepad.","The file has been saved.","文件已保存。"]:
		check(guard.claims_action(phrase,"создай новый файл"),"Passive action claim blocked: "+phrase)
	var writer=preload("res://src/tools/text_documents.gd").new()
	writer.directory=ProjectSettings.globalize_path("user://document-test")
	var first=writer.create_text("Привет 世界\n$(not executable) ; & \" quoted")
	var second=writer.create_text("")
	check(first.ok and second.ok and first.path!=second.path,"Two actual files, unique names")
	check(FileAccess.get_file_as_string(first.path)=="Привет 世界\n$(not executable) ; & \" quoted","Exact document bytes; no execution")
	check(FileAccess.get_sha256(first.path)==first.sha256,"Receipt hash verifies actual file")
	check(FileAccess.get_file_as_string(second.path).is_empty(),"Empty new file exists")
	check(not writer.create_text("x".repeat(8193)).ok,"Document bounded")
	var old_writer=app.documents;app.documents=writer
	app.submit("создай файл в блокноте: Реальный текст")
	await process_frame
	check(app.state.current=="idle" and app.messages[-1].text.contains("сохранён"),"App reports real local creation on non-Windows; no false Notepad launch")
	app.documents=old_writer
	var runtime=app.local_runtime
	var provider=app.provider
	var provider_name=app.provider_name
	var enabled=app.local_ai_enabled
	var settings=app.store.data.settings.duplicate(true)
	var wake=WakeRuntime.new();app.add_child(wake)
	app.local_runtime=wake
	var quiet=QuietProvider.new();app.add_child(quiet);app.provider=quiet;app.provider_name="unconfigured";app.local_ai_enabled=false
	app.submit("Объясни радугу")
	check(wake.calls==1 and app.local_ai_enabled and app.queued_chat_text=="Объясни радугу","Installed local AI wakes from chat without settings")
	app.cancel()
	app.local_runtime=runtime;app.provider=provider;app.provider_name=provider_name;app.local_ai_enabled=enabled
	app.store.data.settings=settings;app.store.save_state()
	wake.queue_free();quiet.queue_free()
	var quality=preload("res://src/core/response_quality.gd").new()
	var transcript=[{"role":"user","content":"норм у тебя каку"},{"role":"assistant","content":"Нормально. Как у тебя?"}]
	check(quality.repeated("да тоже нормально а у тебя?","Нормально. Как у тебя?",transcript),"Reported small-talk loop detected")
	check(not quality.repeated("повтори ответ","Нормально. Как у тебя?",transcript),"Explicit repeat allowed")
	check(not quality.repeated("норм у тебя каку","Нормально. Как у тебя?",transcript),"Repeated question may retain answer")
	var turns=app.session_turns.duplicate(true)
	app.session_turns=transcript.duplicate(true)
	var retry_provider=QuietProvider.new();app.add_child(retry_provider)
	app.provider=retry_provider;app.provider_name="local_worker";app.local_ai_enabled=false
	app.submit("да тоже нормально а у тебя?")
	app._on_answer("Нормально. Как у тебя?")
	check(retry_provider.calls==2 and app.response_retries==1 and app.state.current=="thinking","One bounded retry")
	app._on_answer("Нормально. Как у тебя?")
	check(retry_provider.calls==2 and app.state.current=="idle" and app.messages[-1].text==app.t("model_repeated"),"Repeated retry stops honestly")
	check(app.session_turns==transcript,"Rejected drafts absent from context")
	app.cancel();app.provider=provider;app.provider_name=provider_name;app.local_ai_enabled=enabled
	app.session_turns=turns;retry_provider.queue_free()
	var verifier=preload("res://src/runtime/local_runtime.gd").new()
	verifier.base_path="user://bad-runtime-test"
	verifier.manifest={"platform":OS.get_name(),"model":{"file":"fixture.gguf","bytes":4,"sha256":"a".repeat(64)},"runtime":{"executable":"fixture","sha256":"b".repeat(64),"files":{"fixture":"0".repeat(64)}}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(verifier.runtime_path()))
	var file=FileAccess.open(verifier.model_path(),FileAccess.WRITE);file.store_string("TEST");file.close()
	file=FileAccess.open(verifier.runtime_path().path_join("fixture"),FileAccess.WRITE);file.store_string("bad runtime");file.close()
	file=FileAccess.open(verifier.base_path.path_join("installed.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"model_sha256":"a".repeat(64),"runtime_sha256":"b".repeat(64),"model_mtime":FileAccess.get_modified_time(verifier.model_path())}));file.close()
	app.add_child(verifier)
	check(verifier.start() and verifier.start_verifier!=null and verifier.pid<0,"First runtime integrity check starts as a background thread, before process launch")
	var deadline=Time.get_ticks_msec()+3000
	while verifier.start_verifier!=null and Time.get_ticks_msec()<deadline:await process_frame
	check(verifier.status=="ai_hash_failed" and verifier.pid<0,"Corrupt runtime fails closed without freezing UI or launching a worker")
	verifier.queue_free()
	for path in DirAccess.get_files_at(writer.directory):DirAccess.remove_absolute(writer.directory.path_join(path))
	print("DESKTOP060_TESTS: %s checks, %s failures; real files, wake routing, background verification; Windows UI pending" % [checks,failures])
	quit(0 if failures==0 else 1)
