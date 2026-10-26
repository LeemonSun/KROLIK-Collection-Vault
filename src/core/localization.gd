extends RefCounted
## All product strings are plain text, never executable markup.
const SUPPORTED = ["ru", "en", "zh-Hans"]
var locale = "ru"
var catalog = {}
var fallback = {}

func _init():
	fallback = read_catalog("en")
	set_locale("ru")

func read_catalog(code):
	var file = FileAccess.open("res://locales/%s.json" % code, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func set_locale(code):
	if code not in SUPPORTED:
		return false
	locale = code
	catalog = read_catalog(code)
	return not catalog.is_empty()

func text(key, values = {}):
	return str(catalog.get(key, fallback.get(key, key))).format(values)

