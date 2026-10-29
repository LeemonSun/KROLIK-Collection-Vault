extends RefCounted
## Cheap complete intents before expensive discovery. Never interprets arbitrary model output.
static func is_stop(raw):return str(raw).strip_edges().to_lower().rstrip(".!?") in ["стоп","отмена","остановись","stop","cancel","停止"]
static func builtin(raw):
	var text=str(raw).to_lower().strip_edges().rstrip('.!?')
	return {"блокнот":"notepad","блакнот":"notepad","notepad":"notepad","记事本":"notepad","калькулятор":"calculator","calculator":"calculator","calc":"calculator","计算器":"calculator","paint":"paint","пейнт":"paint"}.get(text,"")
static func route(raw):
	var text=raw.strip_edges();var rx=RegEx.new()
	if preload("res://src/core/intent_constraints.gd").analyze(text).blocked:return {}
	rx.compile('(?i)^(?:в файле|in file)\\s+"([^"\\n]+)"\\s+(?:замени|replace)\\s+"([^"\\n]+)"\\s+(?:на|with)\\s+"([^"\\n]*)"$')
	var patch=rx.search(text)
	if patch:return {"kind":"tool","tool":"files.review_literal","args":{"path":patch.get_string(1),"find":patch.get_string(2),"replacement":patch.get_string(3)}}
	# Explicit creation of a real new text file. Content and filename are distinct intents.
	rx.compile('(?i)^(?:(?:открой|запусти)\\s+(?:блокнот|блакнот)\\s+и\\s+)?создай(?:\\s+мне)?\\s+(?:в\\s+(?:блокноте|блакноте)\\s+)?(?:новый\\s+)?(?:текстовый\\s+)?файл\\s+(с\\s+(?:текстом|надписью|содержимым|названием|именем)|под\\s+названием)\\s*[:：]?\\s+([\\s\\S]+)$')
	var hit=rx.search(text)
	if hit:
		var named=hit.get_string(1).to_lower().contains("названием") or hit.get_string(1).to_lower().contains("именем")
		var value=hit.get_string(2).strip_edges().trim_prefix('«').trim_suffix('»').trim_prefix('"').trim_suffix('"')
		return {"kind":"tool","tool":"documents.create","args":{"text":"" if named else value,"name":value if named else ""}}
	rx.compile('(?i)^(?:open notepad and )?create (?:a )?(?:new )?(?:text )?file (named|with (?:the )?(?:text|content))\\s*[:：]?\\s+([\\s\\S]+)$')
	hit=rx.search(text)
	if hit:return {"kind":"tool","tool":"documents.create","args":{"text":"" if hit.get_string(1).to_lower()=="named" else hit.get_string(2),"name":hit.get_string(2) if hit.get_string(1).to_lower()=="named" else ""}}
	return {}
