extends RefCounted
## Foundation storage only. SQLite adapter is a separate future integration.
var path = "user://foundation-state.json"
var data = {"schema_version": 1, "notes": [], "settings": {}, "reminders":[]}
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
	var reminders=parsed.get("reminders",[])
	if not reminders is Array or reminders.size()>32:
		last_error="invalid_reminders";writable=false;return false
	var ids={}
	for item in reminders:
		if not item is Dictionary or not item.get("id") is String or not item.get("text") is String or item.text.length()>1024 or not (item.get("deadline") is int or item.get("deadline") is float):
			last_error="invalid_reminder";writable=false;return false
		if item.id.length()!=32 or not item.id.is_valid_hex_number(false) or ids.has(item.id) or not is_finite(float(item.deadline)) or item.deadline<0:
			last_error="invalid_reminder";writable=false;return false
		ids[item.id]=true
	parsed["reminders"]=reminders
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


func remove_note(index):
	if not index is int or index<0 or index>=data.notes.size():return false
	var old=data.notes.duplicate(true)
	data.notes.remove_at(index)
	if not save_state():data.notes=old;return false
	return true

func add_reminder(text,seconds,now=-1):
	if not text is String or text.strip_edges().is_empty() or text.length()>1024 or seconds<1 or seconds>2678400 or data.get("reminders",[]).size()>=32:return {"ok":false}
	if now<0:now=int(Time.get_unix_time_from_system())
	if not data.has("reminders"):data["reminders"]=[]
	var item={"id":Crypto.new().generate_random_bytes(16).hex_encode(),"text":text.strip_edges(),"deadline":now+int(seconds)}
	data.reminders.append(item)
	if not save_state():data.reminders.pop_back();return {"ok":false}
	return {"ok":true,"item":item}
func remove_reminder(id):
	var previous=data.get("reminders",[]).duplicate(true)
	data["reminders"]=previous.filter(func(item):return item.id!=id)
	if data.reminders.size()==previous.size():return false
	if not save_state():data.reminders=previous;return false
	return true
func take_due(now):
	var previous=data.get("reminders",[]).duplicate(true)
	var due=previous.filter(func(item):return int(item.deadline)<=now)
	if due.is_empty():return []
	data["reminders"]=previous.filter(func(item):return int(item.deadline)>now)
	if not save_state():data.reminders=previous;return []
	return due
