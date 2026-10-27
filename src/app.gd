extends Node
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
var browser_search = BrowserSearch.new()
var motion = AnimationDirector.new()
var last_motion_result = {}

func _ready():
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://manifests/animation_catalog.json"))
	motion.configure(catalog)
	persistence_ready = store.load_state()
	if persistence_ready:
		l10n.set_locale(str(store.data.settings.get("locale", "ru")))
		profile_request = str(store.data.settings.get("profile", "auto"))
	profile_name = profiles.select(profile_request, OS.get_memory_info().get("physical", 0))
	# Network adapter must be enabled explicitly; not restored by saved settings.
	_set_provider("unconfigured")
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
	provider = Llama.new() if name == "llama_loopback" else Missing.new()
	add_child(provider)
	provider.completed.connect(_on_answer)
	provider.failed.connect(_on_failure)

func enable_developer_llama(enabled):
	cancel()
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
	if state.current != "idle":
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
	state.transition("thinking")
	request_motion("dialogue.think_loop")
	changed.emit()
	var language = {"ru": "Russian", "en": "English", "zh-Hans": "Simplified Chinese"}[l10n.locale]
	var request = [{"role": "system", "content": "You are a concise desktop companion. Reply in %s. Never claim to have performed actions. You have no tools in this build." % language}]
	request.append_array(session_turns.slice(maxi(0, session_turns.size() - 8)))
	request.append({"role": "user", "content": command.text})
	pending_user_text = command.text
	var options = profiles.config(profile_name)
	provider.submit(request, options)

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
		add_message("assistant", t("search_requested" if result.ok else "search_failed"))
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
	request_motion("dialogue.explain_small")
	state.transition("idle")
	changed.emit()

func _on_failure(key):
	pending_user_text = ""
	state.reset()
	add_message("assistant", t(key))
	request_motion("work.model_missing" if key == "model_missing" else "work.error_recover")
	changed.emit()

func cancel():
	motion.clear()
	pending_user_text = ""
	if provider:
		provider.cancel()
	state.reset()
	changed.emit()

func set_paused(value):
	paused = value
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
	if provider:
		provider.cancel()

