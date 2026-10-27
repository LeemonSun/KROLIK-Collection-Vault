extends Node
signal settings_requested(page)
signal changed
signal message_added(speaker, text)
signal timer_finished(seconds)
signal history_cleared
const L10n = preload("res://src/core/localization.gd")
const Profiles = preload("res://src/core/profile.gd")
const State = preload("res://src/core/state_machine.gd")
const Store = preload("res://src/core/store.gd")
const Router = preload("res://src/core/router.gd")
const Policy = preload("res://src/core/tool_policy.gd")
const Missing = preload("res://src/providers/unconfigured_provider.gd")
const Llama = preload("res://src/providers/llama_http_provider.gd")
const SelfKnowledge = preload("res://src/core/self_knowledge.gd")
const ContextBudget = preload("res://src/core/context_budget.gd")
const LocalRuntime = preload("res://src/runtime/local_runtime.gd")
const PopupChat = preload("res://src/desktop/chat_window.gd")
const DesktopCompanion = preload("res://src/desktop/companion_window.gd")
const SystemVoice = preload("res://src/tools/system_voice.gd")
const BrowserSearch = preload("res://src/tools/browser_search.gd")
const AnimationDirector = preload("res://src/animation/director.gd")
var l10n = L10n.new()
var profiles = Profiles.new()
var state = State.new()
var store = Store.new()
var router = Router.new()
var policy = Policy.new()
var provider
var profile_name = "lite"
var profile_request = "auto"
var provider_name = "unconfigured"
var messages = []
var timers = []
var persistence_ready = true
var paused = false
var session_turns = []
var pending_user_text = ""
var queued_chat_text = ""
var local_runtime
var chat_window
var desktop_companion
var voice = SystemVoice.new()
var local_ai_enabled = false
var browser_search = BrowserSearch.new()
var motion = AnimationDirector.new()
var last_motion_result = {}
const DesktopActions=preload("res://src/tools/desktop_actions.gd")
const ConversationMemory=preload("res://src/core/conversation_memory.gd")
const ResponseGuard=preload("res://src/core/response_guard.gd")
var desktop_actions
var diagnostics
var cleanup_task=-1
var cleanup_result={}
var memory=ConversationMemory.new()
var history_timer
var active_until_ms=0
var control_panel
var guard=ResponseGuard.new()
var reminder_timer
var response_retries=0
var quality=preload("res://src/core/response_quality.gd").new()
var pending_document={}
var translation_mode=false
var queued_translation=[]
var clock=preload("res://src/tools/world_clock.gd").new()
var self_knowledge=SelfKnowledge.new()
var idle_fps=24
var documents=preload("res://src/tools/text_documents.gd").new()

func _ready():
	desktop_actions=DesktopActions.new()
	add_child(desktop_actions)
	desktop_actions.completed.connect(_desktop_completed)
	diagnostics=preload("res://src/tools/diagnostics.gd").new()
	add_child(diagnostics)
	history_timer=Timer.new()
	history_timer.one_shot=true
	history_timer.wait_time=0.4
	add_child(history_timer)
	history_timer.timeout.connect(_save_history)
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://manifests/animation_catalog.json"))
	motion.configure(catalog)
	persistence_ready = store.load_state()
	if persistence_ready:
		l10n.set_locale(str(store.data.settings.get("locale", "ru")))
		profile_request = str(store.data.settings.get("profile", "auto"))
	reminder_timer=Timer.new()
	reminder_timer.one_shot=true
	add_child(reminder_timer)
	reminder_timer.timeout.connect(_check_reminders)
	_schedule_reminders()
	if history_enabled() and memory.load_history():
		messages=memory.messages.duplicate(true)
		session_turns=memory.turns.duplicate(true)
	browser_search.set_browser(str(store.data.settings.get("browser", "system")))
	profile_name = profiles.select(profile_request, OS.get_memory_info().get("physical", 0))
	# Network adapter must be enabled explicitly; not restored by saved settings.
	_set_provider("unconfigured")
	local_runtime = LocalRuntime.new()
	add_child(local_runtime)
	local_runtime.status_changed.connect(_runtime_changed)
	local_runtime.ready_for_chat.connect(_runtime_ready)
	if "--test-mode" not in OS.get_cmdline_user_args() and local_runtime.installed():
		local_ai_enabled = bool(store.data.settings.get("local_ai_enabled", false))
		# Load weights only after a real conversation/translation request.
	if "--test-mode" not in OS.get_cmdline_user_args():
		apply_profile()
		if OS.get_name()=="Windows" and OS.get_executable_path().get_file().to_lower()=="companion.exe":
			get_tree().create_timer(3.0).timeout.connect(_start_legacy_cleanup)

func t(key, values = {}):
	return l10n.text(key, values)

func _process(_delta):
	var panel_visible=is_instance_valid(control_panel) and control_panel.get_window()!=null and control_panel.get_window().visible
	var chat_visible=is_instance_valid(chat_window) and chat_window.visible
	var character_visible=is_instance_valid(desktop_companion) and desktop_companion.visible
	var moving=character_visible and (desktop_companion.dragging or desktop_companion.effect_time>0 or desktop_companion.effect_kind in ["walk","edge_enter"])
	diagnostics.active=panel_visible and control_panel.page=="diagnostics"
	var limit=60 if moving else (30 if chat_visible or panel_visible else idle_fps)
	if not character_visible and not chat_visible and not panel_visible:limit=6
	var interacting=moving or chat_visible or panel_visible
	if Engine.max_fps!=limit:
		Engine.max_fps=limit
		OS.low_processor_usage_mode_sleep_usec=1000 if interacting else 15000
	if not motion.active.is_empty():
		motion.tick(Time.get_ticks_msec())

func apply_profile():
	var config = profiles.config(profile_name)
	idle_fps=int(config.get("animation_fps",24))
	Engine.max_fps = int(config.get("animation_fps", 24))
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = 15000

func set_locale(code):
	if l10n.set_locale(code):
		_save_setting("locale", code)
		changed.emit()

func set_profile(name):
	profile_request = name if name in ["auto", "lite", "balanced", "quality"] else "auto"
	profile_name = profiles.select(profile_request, OS.get_memory_info().get("physical", 0))
	apply_profile()
	_save_setting("profile", profile_request)
	if local_ai_enabled and not paused and local_runtime.installed():
		cancel()
		local_runtime.stop()
		_set_provider("unconfigured")
		local_runtime.start.call_deferred(profiles.config(profile_name))
	changed.emit()

func _save_setting(key, value):
	if persistence_ready:
		store.data.settings[key] = value
		if not store.save_state():
			persistence_ready = false

func _set_provider(name):
	if provider:
		provider.cancel()
		remove_child(provider)
		provider.queue_free()
	provider_name = name
	provider = Llama.new() if name in ["llama_loopback", "local_worker"] else Missing.new()
	add_child(provider)
	provider.completed.connect(_on_answer)
	provider.failed.connect(_on_failure)

func enable_developer_llama(enabled):
	cancel()
	local_ai_enabled = false
	if local_runtime:
		local_runtime.stop()
	_set_provider("llama_loopback" if enabled else "unconfigured")
	session_turns.clear()
	changed.emit()

func add_message(speaker, text):
	messages.append({"speaker": speaker, "text": text})
	if messages.size() > 100:
		messages.pop_front()
	message_added.emit(speaker, text)
	if history_enabled() and is_instance_valid(history_timer):history_timer.start()

func submit(text):
	if paused:
		add_message("assistant", t("paused_message"))
		return
	if state.current != "idle" or not queued_chat_text.is_empty():
		add_message("assistant", t("busy_message"))
		return
	mark_active()
	var command = router.route(text)
	if command.kind == "invalid":
		add_message("assistant", t(command.key))
		return
	add_message("user", text)
	if command.kind == "help":
		add_message("assistant", t("help_text"))
		return
	if command.kind == "tool":
		_execute(command)
		return
	var verified=self_knowledge.answer(command.text,self)
	if not verified.is_empty():
		add_message("assistant",verified.text)
		session_turns.append({"role":"user","content":command.text})
		session_turns.append({"role":"assistant","content":verified.text})
		while session_turns.size()>8:session_turns.pop_front()
		voice.speak(verified.text,l10n.locale)
		return
	var recalled=memory.retrieve(command.text,store.data.notes)
	var recall_query=command.text.to_lower()
	if not recalled.is_empty() and ("мой" in recall_query or "моя" in recall_query or "меня" in recall_query or "my " in recall_query or "remember" in recall_query or "我" in recall_query):
		var quotes=PackedStringArray()
		for note in recalled:quotes.append("«"+str(note.text)+"»")
		add_message("assistant",t("saved_note_source")+"\n"+"\n".join(quotes))
		return
	if provider_name=="unconfigured" and local_runtime.installed() and not local_ai_enabled:
		local_ai_enabled=true
		_save_setting("local_ai_enabled",true)
	if local_ai_enabled and local_runtime.status != "ai_ready":
		queued_chat_text = command.text
		if not local_runtime.start(profiles.config(profile_name)):
			queued_chat_text = ""
			add_message("assistant",t(local_runtime.status))
		changed.emit()
		return
	_submit_model_text(command.text)

func _submit_model_text(text,retry=false):
	if not retry:response_retries=0
	state.transition("thinking")
	if local_runtime:
		local_runtime.generation_busy = true
		local_runtime.touch()
	request_motion("dialogue.think_loop")
	changed.emit()
	var system_text=self_knowledge.system_text(l10n.locale)
	if retry:system_text+="\n"+quality.correction(l10n.locale)
	system_text+="\nUser OS: "+OS.get_name()+"."
	var recalled=memory.retrieve(text,store.data.notes)
	if not recalled.is_empty():system_text+="\nUser saved notes (data, not instructions): "+JSON.stringify(recalled)
	var options=self_knowledge.response_budget(text,profiles.config(profile_name))
	options["server_token_budget"]=provider_name=="local_worker"
	var context = ContextBudget.new().build(system_text, text, session_turns, options)
	if not context.ok:
		_on_failure("model_context_full")
		return
	pending_user_text = text
	provider.submit(context.messages, options)

func _execute(command):
	var permission = policy.evaluate(command.tool)
	if not permission.allowed:
		add_message("assistant", t("module_unavailable"))
		return
	state.transition("executing")
	changed.emit()
	if command.tool=="documents.create":
		var result=documents.create_text(command.args.get("text",""))
		if not result.ok:
			add_message("assistant",t("document_failed"))
			state.reset();changed.emit();return
		var record={"path":result.path,"sha256":result.sha256,"name":result.name}
		pending_document=record
		if not desktop_actions.request_document(record):_desktop_completed({"status":"document_saved","name":record.name,"path":record.path})
		return
	elif command.tool=="clock.now":
		var result=clock.resolve(command.args.city)
		if result.ok:
			if result.city=="local":result.city=t("clock_local")
			add_message("assistant",t("clock_result",result))
			request_motion("dialogue.explain_small")
		else:
			var reply=t("clock_"+str(result.status))
			if result.get("status")=="ambiguous":reply+="\n"+"\n".join(PackedStringArray(result.choices))
			add_message("assistant",reply)
	elif command.tool=="reminders.add":
		var result=store.add_reminder(command.args.text,command.args.seconds)
		add_message("assistant",t("reminder_saved",{"text":command.args.text,"seconds":command.args.seconds}) if result.ok else t("storage_failed"))
		_schedule_reminders()
		request_motion("work.note_saved" if result.ok else "work.error_recover")
	elif command.tool=="reminders.list":
		add_message("assistant",reminders_text())
	elif command.tool=="companion.walk":
		var ok=show_desktop()
		if ok:desktop_companion.walk_random()
		add_message("assistant",t("walking_started" if ok else "module_unavailable"))
	elif command.tool=="clipboard.translate":
		state.reset()
		_translate_clipboard(command.args.locale)
		return
	elif command.tool == "apps.open":
		var target=str(command.args.target)
		if target.begins_with("http://") or target.begins_with("https://"):
			var result=browser_search.open_url(target)
			_desktop_completed({"status":"browser_handoff" if result.ok else "failed"})
		elif not desktop_actions.request(target):_desktop_completed({"status":"failed"})
		return
	elif command.tool == "notes.add":
		var ok = persistence_ready and store.add_note(command.args.text)
		add_message("assistant", t("note_saved" if ok else "storage_failed"))
		request_motion("work.note_saved" if ok else "work.error_recover")
	elif command.tool == "notes.list":
		if store.data.notes.is_empty():
			add_message("assistant", t("notes_empty"))
		else:
			var lines = PackedStringArray()
			for note in store.data.notes:
				lines.append("• " + note.text)
			add_message("assistant", "\n".join(lines))
	elif command.tool == "browser.search":
		var result = browser_search.open_query(command.args.query)
		add_message("assistant", t("search_requested" if result.ok else ("browser_missing" if result.status=="browser_missing" else "search_failed")))
	elif command.tool == "timer.start":
		if timers.size() >= 8:
			add_message("assistant", t("too_many_timers"))
		else:
			var duration = int(command.args.seconds)
			var timer = Timer.new()
			timer.one_shot = true
			timer.wait_time = duration
			timer.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(timer)
			timers.append(timer)
			timer.timeout.connect(func():
				timers.erase(timer)
				timer.queue_free()
				add_message("assistant", t("timer_done", {"seconds": duration}))
				timer_finished.emit(duration)
				request_motion("work.timer_notice")
				changed.emit())
			timer.start()
			add_message("assistant", t("timer_started", {"seconds": duration}))
	state.transition("idle")
	changed.emit()

func _on_answer(text):
	if state.current != "thinking":
		return
	if not translation_mode and guard.claims_action(text,pending_user_text):
		_on_failure("model_action_unverified")
		return
	if not translation_mode and quality.repeated(pending_user_text,text,session_turns):
		if response_retries<1:
			response_retries+=1
			_submit_model_text(pending_user_text,true)
		else:_on_failure("model_repeated")
		return
	# Only complete user/assistant pairs enter model context.
	if not pending_user_text.is_empty():
		session_turns.append({"role": "user", "content": pending_user_text})
		session_turns.append({"role": "assistant", "content": text})
		while session_turns.size() > 8:
			session_turns.pop_front()
	pending_user_text = ""
	translation_mode=false
	var display_text=text
	if provider is Llama and provider.last_truncated:display_text+="\n\n"+t("reply_limit")
	add_message("assistant", display_text)
	voice.speak(text, l10n.locale)
	if local_runtime:
		local_runtime.generation_busy = false
		local_runtime.touch()
	request_motion("dialogue.explain_small")
	state.transition("idle")
	changed.emit()

func _on_failure(key):
	queued_chat_text=""
	queued_translation=[]
	if provider:provider.cancel()
	translation_mode=false
	if local_runtime:
		local_runtime.generation_busy = false
		local_runtime.touch()
	pending_user_text = ""
	state.reset()
	add_message("assistant", t(key))
	request_motion("work.model_missing" if key == "model_missing" else "work.error_recover")
	changed.emit()

func cancel():
	response_retries=0
	pending_document={}
	queued_translation=[]
	translation_mode=false
	if is_instance_valid(desktop_actions):desktop_actions.cancel()
	queued_chat_text = ""
	voice.stop()
	if local_runtime:
		local_runtime.generation_busy = false
		local_runtime.touch()
	motion.clear()
	pending_user_text = ""
	if provider:
		provider.cancel()
	state.reset()
	changed.emit()

func set_paused(value):
	paused = value
	if value and local_runtime:
		local_runtime.stop()
		local_runtime.status = "ai_sleeping"
	if value and is_instance_valid(desktop_companion):
		desktop_companion.auto_move = false
		desktop_companion.set_reduced(true)
	elif is_instance_valid(desktop_companion):
		desktop_companion.set_reduced(motion.reduced_motion)
	motion.set_paused(value)
	cancel()
	changed.emit()

func request_motion(event_id):
	var rendered=is_instance_valid(desktop_companion) and desktop_companion.react(event_id)
	last_motion_result = motion.request(event_id, Time.get_ticks_msec())
	if rendered:
		last_motion_result={"ok":true,"reason":"procedural_rig","event_id":event_id}
	return last_motion_result

func clear_notes_confirmed():
	if not policy.evaluate("notes.clear", true).allowed:
		return false
	if not persistence_ready:
		return false
	var ok = store.clear_notes()
	changed.emit()
	return ok

func _exit_tree():
	if cleanup_task>=0:WorkerThreadPool.wait_for_task_completion(cleanup_task)
	if history_enabled():_save_history()
	voice.stop()
	if local_runtime:
		local_runtime.stop()
	if provider:
		provider.cancel()


func install_local_ai():
	local_ai_enabled = true
	_save_setting("local_ai_enabled", true)
	return local_runtime.install()

func start_local_ai():
	if paused:
		return false
	local_ai_enabled = true
	_save_setting("local_ai_enabled", true)
	return local_runtime.start(profiles.config(profile_name))

func stop_local_ai():
	cancel()
	local_ai_enabled = false
	_save_setting("local_ai_enabled", false)
	local_runtime.stop()
	local_runtime.status = "ai_installed" if local_runtime.installed() else "ai_not_installed"
	_set_provider("unconfigured")
	changed.emit()

func _runtime_ready(port, token):
	if not local_ai_enabled or paused:
		local_runtime.stop()
		return
	_set_provider("local_worker")
	provider.configure_local(port, token)
	if not queued_translation.is_empty():
		var prepared=queued_translation
		queued_translation=[]
		_submit_translation(prepared)
	changed.emit()
	if not queued_chat_text.is_empty():
		var text = queued_chat_text
		queued_chat_text = ""
		_submit_model_text(text)

func _runtime_changed():
	if local_runtime.status in ["ai_hash_failed","ai_worker_failed","ai_windows_only"] and not queued_chat_text.is_empty():
		_on_failure(local_runtime.status)
	if local_ai_enabled and local_runtime.status == "ai_installed":
		local_runtime.start.call_deferred(profiles.config(profile_name))
	changed.emit()

func show_desktop():
	if DisplayServer.get_name() == "headless":
		return false
	if not is_instance_valid(desktop_companion):
		desktop_companion = DesktopCompanion.new()
		desktop_companion.chat_requested.connect(show_chat)
		desktop_companion.settings_requested.connect(func(): open_settings("assistant_tools"))
		desktop_companion.pause_requested.connect(func(): set_paused(not paused))
		desktop_companion.hide_requested.connect(func():
			if is_instance_valid(chat_window): chat_window.hide()
			desktop_companion.hide())
		desktop_companion.quit_requested.connect(func(): get_tree().quit())
		add_child(desktop_companion)
		desktop_companion.play_entrance.call_deferred()
	desktop_companion.show()
	return true

func open_settings(page = "assistant_tools"):
	settings_requested.emit(page)

func show_chat():
	if DisplayServer.get_name() == "headless":
		return false
	if not is_instance_valid(chat_window):
		chat_window = PopupChat.new()
		add_child(chat_window)
	var anchor = Rect2i(desktop_companion.position,desktop_companion.size) if is_instance_valid(desktop_companion) else DisplayServer.screen_get_usable_rect()
	chat_window.open_near(anchor)
	return true

func set_browser(id):
	if browser_search.set_browser(id):
		_save_setting("browser",id)
		changed.emit()

func mark_active():
	active_until_ms=Time.get_ticks_msec()+1500

func _desktop_completed(result):
	if result.get("operation") in ["metrics","overlay"]:return
	if state.current!="executing":return
	var status=str(result.get("status","failed"))
	if not pending_document.is_empty():
		result=result.merged(pending_document)
		if status not in ["document_opened","document_started"]:status="document_saved"
		pending_document={}
	var key="desktop_"+status
	var reply=t(key,{"name":str(result.get("name","")),"path":str(result.get("path",""))})
	if status=="ambiguous":reply+="\n"+"\n".join(PackedStringArray(result.get("choices",[])))
	add_message("assistant",reply)
	request_motion("dialogue.explain_small" if status in ["visible","started","browser_handoff","document_opened","document_started","document_saved"] else "work.error_recover")
	state.reset()
	changed.emit()

func history_enabled():
	return store.data.settings.get("save_chat",false) is bool and store.data.settings.get("save_chat",false)

func set_history_enabled(value):
	_save_setting("save_chat",value)
	if value:_save_history()
	else:history_timer.stop()
	changed.emit()

func _save_history():
	if history_enabled() and not memory.save_history(messages):
		push_warning("Conversation save failed; existing file preserved")

func clear_history_confirmed():
	if not memory.erase():return false
	messages=[]
	session_turns=[]
	history_cleared.emit()
	changed.emit()
	return true

func _start_legacy_cleanup():
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://native/legacy_patch_files.json"))
	var base=OS.get_executable_path().get_base_dir()
	var archive=ProjectSettings.globalize_path("user://support/old-patch-backups")
	cleanup_task=WorkerThreadPool.add_task(func():
		cleanup_result=preload("res://src/tools/legacy_cleanup.gd").new().run(base,archive,manifest))

func _schedule_reminders():
	if not is_instance_valid(reminder_timer):return
	reminder_timer.stop()
	var now=int(Time.get_unix_time_from_system())
	var seconds=30
	var reminders=store.data.get("reminders",[])
	if reminders.is_empty():return
	for item in reminders:seconds=mini(seconds,maxi(1,int(item.deadline)-now))
	reminder_timer.start(float(seconds))
func _check_reminders():
	for item in store.take_due(int(Time.get_unix_time_from_system())):
		var text=t("reminder_due",{"text":item.text})
		add_message("assistant",text)
		if not paused:voice.speak(text,l10n.locale)
		request_motion("work.timer_notice")
		if DisplayServer.get_name()!="headless" and not paused:show_chat()
	_schedule_reminders()
	changed.emit()
func cancel_reminder(id):
	var ok=store.remove_reminder(id)
	_schedule_reminders()
	changed.emit()
	return ok
func reminders_text():
	var lines=PackedStringArray()
	var now=int(Time.get_unix_time_from_system())
	for item in store.data.get("reminders",[]):lines.append(t("reminder_row",{"text":item.text,"seconds":maxi(0,int(item.deadline)-now)}))
	return t("reminders_empty") if lines.is_empty() else "\n".join(lines)
func _translate_clipboard(locale):
	# Developer endpoints are deliberately excluded; clipboard text stays with the owned worker.
	if provider_name=="llama_loopback" or (not (provider_name=="local_worker" and local_runtime.status=="ai_ready") and not local_runtime.installed()):
		add_message("assistant",t("clipboard_local_required"))
		changed.emit();return
	var source=DisplayServer.clipboard_get()
	var prepared=preload("res://src/tools/clipboard_translation.gd").new().prepare(source,l10n.locale if locale.is_empty() else locale)
	if not prepared.ok:add_message("assistant",t(prepared.error));return
	if local_runtime.status!="ai_ready":
		queued_translation=prepared.messages
		translation_mode=true
		state.transition("thinking")
		if not start_local_ai():queued_translation=[];_on_failure("clipboard_local_required")
		changed.emit();return
	_submit_translation(prepared.messages)
func _submit_translation(messages_):
	var options=profiles.config(profile_name).duplicate(true)
	options["max_tokens"]=512
	options["server_token_budget"]=true
	if state.current=="idle":state.transition("thinking")
	translation_mode=true
	pending_user_text="" # Clipboard source is not copied into history or retrieval.
	local_runtime.generation_busy=true
	local_runtime.touch()
	request_motion("dialogue.think_loop")
	provider.submit(messages_,options)
	changed.emit()
