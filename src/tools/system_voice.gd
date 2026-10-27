extends RefCounted
## Uses installed OS voices; does not ship or clone a character voice.
var enabled = false
func speak(text, locale):
	if not enabled or DisplayServer.get_name() == "headless":
		return false
	var lang = {"ru":"ru", "en":"en", "zh-Hans":"zh"}.get(locale, "en")
	var voices = DisplayServer.tts_get_voices_for_language(lang)
	if voices.is_empty():
		return false
	# Prevent model output being interpreted as SSML tags by system speech engines.
	var plain = text.replace("&", " and ").replace("<", " ").replace(">", " ").substr(0, 4000)
	DisplayServer.tts_speak(plain, voices[0], 65, 1.0, 1.0, 0, true)
	return true
func stop():
	if DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()
