extends RefCounted
const DesktopIntent=preload("res://src/core/desktop_intent.gd")
## Deterministic multilingual commands bypass the language model.
func route(raw):
	var text = preload("res://src/core/intent_spelling.gd").normalize(raw)
	if text.is_empty():
		return {"kind": "invalid", "key": "empty_input"}
	if text.length() > 2048:
		return {"kind": "invalid", "key": "input_too_long"}
	var utility=preload("res://src/core/utility_intent.gd").route(text)
	if not utility.is_empty():return utility
	var space = text.find(" ")
	var command = (text if space < 0 else text.substr(0, space)).to_lower()
	var argument = "" if space < 0 else text.substr(space + 1).strip_edges()
	if command in ["/help", "/помощь", "/帮助"]:
		return {"kind": "help"}
	if command in ["/timer", "/таймер", "/计时"]:
		if argument.length() > 6 or not argument.is_valid_int():
			return {"kind": "invalid", "key": "timer_invalid"}
		var seconds = argument.to_int()
		if seconds < 1 or seconds > 86400:
			return {"kind": "invalid", "key": "timer_invalid"}
		return {"kind": "tool", "tool": "timer.start", "args": {"seconds": seconds}}
	if command in ["/note", "/заметка", "/笔记"]:
		if argument.is_empty():
			return {"kind": "invalid", "key": "note_invalid"}
		return {"kind": "tool", "tool": "notes.add", "args": {"text": argument}}
	if command in ["/notes", "/заметки", "/笔记列表"]:
		return {"kind": "tool", "tool": "notes.list", "args": {}}
	if command in ["/search", "/поиск", "/搜索"]:
		if argument.is_empty() or argument.length() > 512:
			return {"kind": "invalid", "key": "search_invalid"}
		return {"kind": "tool", "tool": "browser.search", "args": {"query": argument}}
	var natural=DesktopIntent.new().route(text)
	if not natural.is_empty():return natural
	# Unknown slash commands are not forwarded as tool instructions.
	if text.begins_with("/"):
		return {"kind": "invalid", "key": "unknown_command"}
	return {"kind": "chat", "text": text}

