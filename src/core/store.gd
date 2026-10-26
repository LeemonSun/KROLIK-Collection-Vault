extends RefCounted
## Foundation storage only. SQLite adapter is a separate future integration.
var path = "user://foundation-state.json"
var data = {"schema_version": 1, "notes": [], "settings": {}}
var last_error = ""
var writable = true

func _init(storage_path = "user://foundation-state.json"):
	path = storage_path

func load_state():
	last_error = ""
	writable = true
	if not FileAccess.file_exists(path):
		return true
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "read_failed"
		writable = false
		return false
	if f.get_length() > 2 * 1024 * 1024:
		last_error = "state_too_large"
		writable = false
		return false
	var parser = JSON.new()
	if parser.parse(f.get_as_text()) != OK:
		last_error = "invalid_json"
		writable = false
		return false
	var parsed = parser.data
	if not (parsed is Dictionary) or parsed.get("schema_version") != 1:
		last_error = "invalid_schema"
		writable = false
		return false
	if not (parsed.get("notes") is Array) or not (parsed.get("settings") is Dictionary):
		last_error = "invalid_schema"
		writable = false
		return false
	# Do not silently erase or overwrite an unrecognized/corrupt store.
	for note in parsed.notes:
		if not (note is Dictionary) or not (note.get("text") is String) or note.text.length() > 2048:
			last_error = "invalid_note"
			writable = false
			return false
	data = parsed
	return true

func save_state():
	if not writable:
		return false
	var tmp = path + ".tmp"
	var f = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "write_failed"
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	f.close()
	var error = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if error != OK:
		last_error = "rename_failed"
		return false
	last_error = ""
	return true

func add_note(text):
	if text.strip_edges().is_empty() or text.length() > 2048:
		return false
	if data.notes.size() >= 100:
		last_error = "notes_full"
		return false
	var note = {"text": text, "created_utc": int(Time.get_unix_time_from_system())}
	data.notes.append(note)
	if not save_state():
		data.notes.pop_back()
		return false
	return true

func clear_notes():
	var previous = data.notes.duplicate(true)
	data.notes.clear()
	if not save_state():
		data.notes = previous
		return false
	return true

