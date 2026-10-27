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
	for turn in range(turns.size()-1,-1,-1):
		if turns[turn].get("role")=="user":
			if normalize(str(turns[turn].get("content","")))==normalize(query):return false
			break
	var smalltalk=false
	for marker in ["у тебя","как дела","как ты","привет","how are","and you","how about you","你呢","你好吗"]:
		if marker in q:smalltalk=true
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
