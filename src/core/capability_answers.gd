extends RefCounted
## Questions about supported tools use the actual host registry, not model guesswork.
static func lookup(raw,policy):
 var text=raw.to_lower().replace('ё','е').strip_edges()
 if text.length()>240 or text.count('?')+text.count('？')>1:return {}
 var question=false
 for marker in ['ты умеешь','умеешь ли','можешь ли','ты можешь','can you','are you able','你能','会不会']:
  if marker in text:question=true
 if not question:return {}
 var rows=[
  ['timer.start','timer',['таймер','timer','计时']],
  ['notes.add','notes',['заметк','note','笔记']],
  ['reminders.add','reminder',['напом','remind','提醒']],
  ['math.calculate','math',['посчитать','вычисля','calculate','计算']],
  ['screen.describe','screen',['видеть экран','посмотреть экран','see my screen','look at my screen','看屏幕']],
  ['web.read','web',['прочитать сайт','прочитать страницу','read a page','read a website','读取网页']],
  ['files.edit_selected','files',['редактировать файл','edit a file','编辑文件']],
  ['files.delete','delete',['удалять файлы','delete files','删除文件']],
  ['messages.send','send',['отправлять сообщения','send messages','发送消息']]]
 for row in rows:
  for marker in row[2]:
   if marker in text:return {'key':'cap_'+row[1] if policy.evaluate(row[0]).allowed else 'cap_unavailable','tool':row[0]}
 return {}
