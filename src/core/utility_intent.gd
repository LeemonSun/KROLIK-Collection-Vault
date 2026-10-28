extends RefCounted
static func route(raw):
	var text=raw.strip_edges();var rx=RegEx.new()
	rx.compile('(?i)^(?:/read|прочитай страницу|read page|读取网页)\\s+(\\S+)$')
	var web=rx.search(text)
	if web:return {"kind":"tool","tool":"web.read","args":{"url":web.get_string(1)}}
	rx.compile('(?i)^/(?:calc|счёт|计算)\\s+(.+)$')
	var hit=rx.search(text)
	if hit:return {"kind":"tool","tool":"math.calculate","args":{"expression":hit.get_string(1)}}
	rx.compile('(?i)^(?:посчитай|вычисли|реши|чему равно|сколько будет|calculate|what is|计算|算一下)\\s*[:：]?\\s+(.+?)[?？]?$')
	hit=rx.search(text)
	if hit:
		var expression=hit.get_string(1);var stripped=expression.to_lower()
		for word in ['log10','sqrt','abs','sin','cos','ln','pi','e']:stripped=stripped.replace(word,'')
		var candidate=RegEx.new();candidate.compile('^[0-9.()+*/^%×÷−π\\-\\s]+$')
		if candidate.search(stripped):return {"kind":"tool","tool":"math.calculate","args":{"expression":expression}}
	rx.compile('(?i)^(?:/convert|convert|переведи|换算)\\s+([+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:e[+-]?[0-9]{1,3})?)\\s*([^\\s]+)\\s+(?:to|в|到)\\s+([^\\s]+)$')
	hit=rx.search(text)
	if hit:return {"kind":"tool","tool":"math.convert","args":{"number":hit.get_string(1),"from":hit.get_string(2),"to":hit.get_string(3)}}
	rx.compile('(?i)^(?:/settings|открой настройки|open settings|打开设置)\\s+([^\\n]+)$')
	hit=rx.search(text)
	if hit:
		var page=preload("res://src/tools/windows_settings.gd").resolve(hit.get_string(1))
		if page.ok:return {"kind":"tool","tool":"settings.open","args":{"page":page.id}}
	return {}
