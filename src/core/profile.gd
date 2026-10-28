extends RefCounted
const NAMES = ["lite", "balanced", "quality"]
var profiles = {}

func _init():
	var f = FileAccess.open("res://config/profiles.json", FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			profiles = data.get("profiles", {})

func select(requested, ram_bytes):
	if requested in NAMES:
		return requested
	# Unknown hardware is treated conservatively. RAM is total physical memory.
	if ram_bytes >= 28 * 1024 * 1024 * 1024:
		return "quality"
	if ram_bytes >= 14 * 1024 * 1024 * 1024:
		return "balanced"
	return "lite"

func config(name):
	return profiles.get(name, profiles.get("lite", {})).duplicate(true)

func effective(name, resource_mode="quiet"):
	var result=config(name)
	if resource_mode=="quiet":
		result["cpu_threads"]=1
		result["batch_tokens"]=32
		result["idle_unload_seconds"]=30
	else:
		result["batch_tokens"]=128
	return result

