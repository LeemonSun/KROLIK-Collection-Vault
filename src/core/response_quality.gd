extends RefCounted
## Cheap repetition detection, not a factual-accuracy score.
func normalize(text):
	var rx=RegEx.new();rx.compile("[^\\p{L}\\p{N}]+")
	return rx.sub(text.to_lower(),"",true).left(800)
func repeated(query,answer,turns):
	var q=query.to_lower()
	for allowed in ["повтори","повторить","repeat","again exactly","переведи","translate","翻译","重复"]:
		if allowed in q:return false
	var current=normalize(answer)
	if current.length()<6:return false
	var smalltalk=false
	for marker in ["у тебя","как дела","как ты","привет","how are","and you","how about you","你呢","你好吗"]:
		if marker in q:smalltalk=true
	if not smalltalk:
		for index in range(turns.size()-1,-1,-1):
			if turns[index].get("role")=="user":
				if normalize(str(turns[index].get("content","")))==normalize(query):return false
				break
	var count=0
	for index in range(turns.size()-1,-1,-1):
		if turns[index].get("role")!="assistant":continue
		count+=1
		var previous=normalize(str(turns[index].get("content","")))
		if previous==current and (smalltalk or current.length()>=28):return true
		if count>=2:break
	return false
func correction(locale):
	return {
		"ru":"Предыдущий черновик повторил твой прошлый ответ. Пользователь уже ответил, как у него дела. Ответь по смыслу на его последнюю реплику, одним-двумя короткими предложениями. Не спрашивай снова то же самое и не добавляй шаблонное предложение помощи.",
		"en":"Your previous draft repeated your last reply. The user already answered how they are. Respond to their latest message in one or two short sentences; do not ask the same question or add a generic offer to help.",
		"zh-Hans":"上一份草稿重复了你之前的回复。用户已经回答了近况。请用一两句简短的话回应用户最后的信息，不要再问同样的问题，也不要添加模板化的帮助提议。"
	}.get(locale,"")

func context_hint(query,turns):
	if turns.is_empty():return ""
	if query.length()<100:
		var hint="Use the recent messages to resolve short follow-ups. Answer directly without restarting the greeting or asking a question already answered."
		var q=query.to_lower()
		for marker in ["у тебя","как дела","как ты","how are","and you","你呢","你好吗"]:
			if marker in q:return hint+" You have no human day or completed work to report. Respond to the user's news in character, without inventing a personal diary or completed tasks."
		return hint
	return ""
func gesture(text):
	var lower=text.to_lower()
	for marker in ["не уверен","не знаю","not sure","don't know","不确定","不知道"]:
		if marker in lower:return "shrug"
	if text.strip_edges().ends_with("?") or text.strip_edges().ends_with("？"):return "curious"
	return "present" if text.length()>220 else "talk"

func clean(text,query):
	var q=query.to_lower()
	for marker in ["переведи","translate","翻译","цитат","quote","повтори","repeat","рассказ","story","код","code","скрипт","script","json","代码"]:
		if marker in q:return text
	if "```" in text:return text
	var breaks=RegEx.new();breaks.compile("(?<=[.!?])\\s+|(?<=[。！？])")
	var starts=[0]
	for hit in breaks.search_all(text):
		if hit.get_end()<text.length():starts.append(hit.get_end())
	var end=text.length()
	while starts.size()>1:
		var start=int(starts[-1]);var tail=text.substr(start,end-start).strip_edges().to_lower();var filler=false
		if tail.begins_with("если ") and ("помо" in tail or "обсудить" in tail) and ("скажи" in tail or "скажите" in tail or "хоч" in tail):filler=true
		if tail.begins_with("if you ") and ("help" in tail or "anything else" in tail or "discuss" in tail):filler=true
		if tail.begins_with("let me know") or tail.begins_with("feel free to"):filler=true
		if tail.begins_with("如果") and ("帮助" in tail or "随时" in tail):filler=true
		if not filler:break
		end=start;starts.pop_back()
	return text.left(end).strip_edges() if end<text.length() else text

func casual_fallback(query,locale,turns):
	var lower=query.to_lower();var casual=false
	for marker in ["у тебя","как дела","как ты","how are","and you","你呢","你好吗"]:
		if marker in lower:casual=true
	if not casual:return ""
	var completed=false
	for marker in ["закончил","все дела","all done","finished","做完","完成"]:
		if marker in lower:completed=true
	var options={
		"ru":["Я на связи. Хорошо, что удалось закончить дела.","Значит, дела закрыты. Самое время сменить темп.","Тогда можно выдохнуть. Я здесь."] if completed else ["Я на связи, слушаю тебя.","Здесь, в рабочем настроении.","Всё спокойно. Я рядом."],
		"en":["I'm here. Sounds like you've earned a break.","All done, then. Time for a change of pace.","Good to have the tasks behind you. I'm here."] if completed else ["I'm here and listening.","Here, ready for our next conversation.","All quiet on my side. I'm here."],
		"zh-Hans":["我在。事情做完了，可以放松一下。","既然都完成了，可以换个节奏。","事情告一段落了。我在这里。"] if completed else ["我在，听你说。","我在这里。","这边很安静，我在。"]
	}.get(locale,[])
	for option in options:
		if not repeated(query,option,turns):return option
	return ""
