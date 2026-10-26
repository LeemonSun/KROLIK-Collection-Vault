extends RefCounted
## Consistent future contract for ASR, TTS, OCR, automation and Steam.
var id = ""
var status = "not_integrated"

func _init(module_id = ""):
	id = module_id

func describe():
	return {"id": id, "status": status, "available": false}

func invoke(_payload):
	return {"ok": false, "error": "not_integrated", "module": id}

func stop():
	pass

