extends RefCounted
## A narrow backstop. Actual effects and their success messages come from the executor.
func claims_action(text, query):
	var q=query.to_lower()
	for marker in ["переведи", "translate", "翻译", "напиши рассказ", "write a story", "цитат"]:
		if marker in q:return false
	var rx=RegEx.new()
	rx.compile("(?:я\\s+(?:(?:уже|сейчас)\\s+)?(?:откры[лв]а?|запустил[а]?|создал[а]?|изменил[а]?|вставил[а]?|удалил[а]?|отправил[а]?|нажал[а]?|сохранил[а]?|скачал[а]?))|(?:i(?:'ve| have)?\\s+(?:just\\s+)?(?:opened|created|modified|inserted|launched|deleted|sent|clicked|saved|downloaded))|(?:(?:проводник|браузер)\\s+(?:уже\\s+)?(?:открыт|запущен))|(?:我(?:已经|已)?(?:打开|启动|删除|发送|保存)了)")
	if rx.search(text.to_lower())!=null:return true
	rx.compile("(?:我(?:已经|已|为你|给你|帮你)?(?:创建|建立|制作))|(?:由我.{0,5}(?:创建|建立|制作))")
	if rx.search(text)!=null:return true
	rx.compile("(?:(?:файл|документ|вкладк[аиу]|папк[аиу]|сообщени[ея]|приглашени[ея]|письм[оа]|окно|текст)[^.!?\\n]{0,60}(?:создан|сохранен|удален|отправлен|открыт|вставлен|добавлен))|(?:(?:создан|сохранен|удален|отправлен|открыт|вставлен|добавлен)[^.!?\\n]{0,60}(?:файл|документ|вкладк|папк|сообщени|приглашени|письм|окно|текст))|(?:(?:file|document|tab|message|invitation|invite|email|folder) (?:has been |was |is )?(?:created|saved|deleted|sent|opened))|(?:(?:created|saved|deleted|sent|opened) (?:a |the |new )*(?:file|document|tab|message|invitation|invite|email|folder))|(?:(?:文件|文档|消息|邀请|邮件).{0,12}(?:已创建|已保存|已发送))")
	return rx.search(text.to_lower().replace('ё','е'))!=null
