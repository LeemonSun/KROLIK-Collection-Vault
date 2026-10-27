extends Node
signal settings_requested(page)
signal changed
signal message_added(speaker, text)
signal timer_finished(seconds)
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
var self_knowledge=SelfKnowledge.new()

func _ready():
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://manifests/animation_catalog.json"))
	motion.configure(catalog)
	persistence_ready = store.load_state()
	if persistence_ready:
		l10n.set_locale(str(store.data.settings.get("locale", "ru")))
		profile_request = str(store.data.settings.get("profile", "auto"))
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
		if local_ai_enabled:
			local_runtime.start.call_deferred(profiles.config(profile_name))
	if "--test-mode" not in OS.get_cmdline_user_args():
		apply_profile()

func t(key, values = {}):
	return l10n.text(key, values)

func _process(_delta):
	if not motion.active.is_empty():
		motion.tick(Time.get_ticks_msec())

func apply_profile():
	var config = profiles.config(profile_name)
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

func submit(text):
	if paused:
		add_message("assistant", t("paused_message"))
		return
	if state.current != "idle" or not queued_chat_text.is_empty():
		add_message("assistant", t("busy_message"))
		return
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
	if local_ai_enabled and local_runtime.status != "ai_ready":
		queued_chat_text = command.text
		if not local_runtime.start(profiles.config(profile_name)):
			queued_chat_text = ""
		add_message("assistant", t(local_runtime.status))
		return
	_submit_model_text(command.text)

func _submit_model_text(text):
	state.transition("thinking")
	if local_runtime:
		local_runtime.generation_busy = true
		local_runtime.touch()
	request_motion("dialogue.think_loop")
	changed.emit()
	var system_text=self_knowledge.system_text(l10n.locale)
	var options=self_knowledge.response_budget(text,profiles.config(profile_name))
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
	if command.tool == "notes.add":
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
	# Only complete user/assistant pairs enter model context.
	if not pending_user_text.is_empty():
		session_turns.append({"role": "user", "content": pending_user_text})
		session_turns.append({"role": "assistant", "content": text})
		while session_turns.size() > 8:
			session_turns.pop_front()
	pending_user_text = ""
	add_message("assistant", text)
	voice.speak(text, l10n.locale)
	if local_runtime:
		local_runtime.generation_busy = false
		local_runtime.touch()
	request_motion("dialogue.explain_small")
	state.transition("idle")
	changed.emit()

func _on_failure(key):
	if local_runtime:
		local_runtime.generation_busy = false
		local_runtime.touch()
	pending_user_text = ""
	state.reset()
	add_message("assistant", t(key))
	request_motion("work.model_missing" if key == "model_missing" else "work.error_recover")
	changed.emit()

func cancel():
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
	last_motion_result = motion.request(event_id, Time.get_ticks_msec())
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
	changed.emit()
	if not queued_chat_text.is_empty():
		var text = queued_chat_text
		queued_chat_text = ""
		_submit_model_text(text)

func _runtime_changed():
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
