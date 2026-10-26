extends Node
signal completed(text)
signal failed(key)
var busy = false

func submit(_messages, _options = {}):
	failed.emit("module_unavailable")
	return false

func cancel():
	busy = false

func capabilities():
	return {"available": false, "network": "none", "streaming": false, "tools": false}

