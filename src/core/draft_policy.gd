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
	return violations(text,goal).is_empty()
static func violations(text,goal):
	# Literal witnesses for a bounded repair, not a semantic fact checker.
	var errors=[]
	for pattern in ['[\\p{N}]+(?:[.,:][\\p{N}]+)*','https?://[^\\s<>\\[\\]]+','[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}']:
		var rx=RegEx.new()
		if rx.compile(pattern)!=OK:return ['invalid_pattern']
		var allowed=[]
		for hit in rx.search_all(goal):allowed.append(hit.get_string().trim_suffix('.').trim_suffix(','))
		for hit in rx.search_all(text):
			var token=hit.get_string().trim_suffix('.').trim_suffix(',')
			if token not in allowed and errors.size()<12:errors.append(token.left(100))
	var allowed=temporal_ids(goal)
	for id in temporal_ids(text):
		if id not in allowed and errors.size()<12:errors.append(id)
	var rx=RegEx.new();rx.compile('[零〇一二两三四五六七八九十百]+(?:点|時|时|分)')
	for hit in rx.search_all(text):
		if hit.get_string() not in goal and errors.size()<12:errors.append(hit.get_string())
	return errors

static func temporal_ids(raw):
	var text=raw.to_lower().replace('ё','е');var found=[]
	var groups={
		'today':['сегодня','today','今天'], 'tomorrow':['завтра','tomorrow','明天'],
		'yesterday':['вчера','yesterday','昨天'], 'after_tomorrow':['послезавтра','后天'],
		'morning':['утром','утро','morning','早上','上午'], 'afternoon':['днем','afternoon','下午'],
		'evening':['вечером','вечер','evening','tonight','晚上'], 'night':['ночью','midnight','午夜']}
	for id in groups:
		for word in groups[id]:
			var rx=RegEx.new();var pattern=word if word.unicode_at(0)>=0x4e00 else '(*UCP)\\b'+word+'\\b'
			rx.compile(pattern)
			if rx.search(text):found.append(id);break
	return found
static func grounded_temporal(text,goal):
	var allowed=temporal_ids(goal)
	for id in temporal_ids(text):
		if id not in allowed:return false
	var rx=RegEx.new();rx.compile('[零〇一二两三四五六七八九十百]+(?:点|時|时|分)')
	for hit in rx.search_all(text):
		if hit.get_string() not in goal:return false
	return true
