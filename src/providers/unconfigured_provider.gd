extends "res://src/providers/provider_base.gd"
## Honest unavailable state: no fabricated AI responses.
func submit(_messages, _options = {}):
	failed.emit("model_missing")
	return false

func capabilities():
	return {"available": false, "network": "none", "streaming": false, "tools": false}

