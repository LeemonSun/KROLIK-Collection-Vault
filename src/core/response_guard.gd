extends RefCounted
## A narrow backstop. Actual effects and their success messages come from the executor.
func claims_action(text, query):
	var q=query.to_lower()
	for marker in ["переведи", "translate", "翻译", "напиши рассказ", "write a story", "цитат"]:
		if marker in q:return false
	var rx=RegEx.new()
	rx.compile("(?:я\\s+(?:(?:уже|сейчас)\\s+)?(?:откры[лв]а?|запустил[а]?|удалил[а]?|отправил[а]?|нажал[а]?|сохранил[а]?|скачал[а]?))|(?:i(?:'ve| have)?\\s+(?:just\\s+)?(?:opened|launched|deleted|sent|clicked|saved|downloaded))|(?:(?:проводник|браузер)\\s+(?:уже\\s+)?(?:открыт|запущен))|(?:我(?:已经|已)?(?:打开|启动|删除|发送|保存)了)")
	return rx.search(text.to_lower())!=null
