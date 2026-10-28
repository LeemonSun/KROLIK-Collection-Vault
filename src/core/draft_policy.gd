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

static func grounded_details(text,goal):
	# A narrow literal check, NOT semantic fact verification. Unsupported names or
	# facts without numeric/address tokens can still require user correction.
	for pattern in ['[\\p{N}]+(?:[.,:][\\p{N}]+)*','https?://[^\\s<>\\[\\]]+','[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}']:
		var rx=RegEx.new()
		if rx.compile(pattern)!=OK:return false
		var allowed=[]
		for hit in rx.search_all(goal):allowed.append(hit.get_string().trim_suffix('.').trim_suffix(','))
		for hit in rx.search_all(text):
			if hit.get_string().trim_suffix('.').trim_suffix(',') not in allowed:return false
	return true
