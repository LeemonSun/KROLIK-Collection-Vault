extends RefCounted
## An explicit request to compose permits a reviewed draft, never an immediate effect.
const MAX_CHARS=512
static func requested(raw):
	if not raw is String:return false
	var text=raw.strip_edges().to_lower()
	var rx=RegEx.new()
	rx.compile('^(?:(?:пожалуйста|please)[ ,]+)?(?:напиши|составь|сочини|придумай|compose|draft)(?:[ ,:]|$)|^(?:请)?(?:写一|撰写|编写一)')
	return rx.search(text)!=null
static func valid(text):
	if not text is String or text.strip_edges().is_empty() or text.length()>MAX_CHARS:return false
	for character in text:
		if character.unicode_at(0)<32 and character not in ['\n','\t']:return false
	return true
