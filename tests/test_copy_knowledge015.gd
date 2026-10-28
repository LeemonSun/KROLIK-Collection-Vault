extends SceneTree
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func run():
	var app=root.get_node('App');app.cancel();app.set_locale('ru')
	var captured=[]
	var original=app.messages.duplicate(true);var trimmed=app.messages_truncated
	app.messages=[{"speaker":"user","text":"Привет 中文\nline two"},{"speaker":"assistant","text":"Ответ [b]plain[/b]"},{"speaker":"assistant","text":"Visible private source","ephemeral":true}];app.messages_truncated=false
	var result=app.copy_chat(func(text):captured.append(text))
	check(result.ok and result.count==3 and captured.size()==1,'One copy captures all retained messages, not just one card')
	check('Привет 中文\nline two' in captured[0] and 'Ответ [b]plain[/b]' in captured[0] and 'Visible private source' in captured[0],'Copy preserves Unicode/newlines/plain markup and explicitly visible ephemeral text')
	check(captured[0].find('Привет')<captured[0].find('Ответ') and captured[0].find('Ответ')<captured[0].find('Visible'),'Chronological role-separated transcript')
	check(app.messages.size()==3 and not app.store.data.notes.any(func(note):return 'Visible private source' in note.text),'Copy does not add notes or alter conversation')
	app.messages_truncated=true;result=app.copy_chat(func(text):captured.append(text))
	check(result.ok and result.truncated and app.t('chat_copy_retained') in captured[-1],'Earlier truncation disclosed in copied text')
	app.messages=[];app.messages_truncated=false
	for i in range(101):app.add_message('user','message '+str(i))
	result=app.copy_chat(func(text):captured.append(text))
	check(result.count==100 and result.truncated and not '\nmessage 0\n' in captured[-1],'Bounded history copy honestly identifies unavailable older messages')
	var Format=preload('res://src/core/chat_transcript.gd')
	check(not Format.format([{"speaker":"user","text":"x".repeat(Format.MAX_BYTES+1)}],'YOU').ok,'Oversized transcript refuses rather than silently truncating')
	app.messages=original;app.messages_truncated=trimmed
	var knowledge=app.self_knowledge
	var cases={'йоу братан, чему научился за последнее время?':'updates','честно скажи научился ли ты не только открывать блокнот но и редактировать и писать туда что либо?':'desktop_edit','чего тебе не хватает, ты ии агент живущий на пк, давай список':'limits','можешь ли ты мне куда либо всю нашу переписку перенести чтобы я скопировал':'chat_export','Can you edit Notepad?':'desktop_edit','what features are missing?':'limits','你能编辑文件吗':'desktop_edit','复制聊天可以吗':'chat_export'}
	for text in cases:check(knowledge.classify(text)==cases[text],'Reported self-knowledge wording routed truthfully: '+text)
	for locale in ['ru','en','zh-Hans']:
		app.set_locale(locale)
		for text in cases:
			var answer=knowledge.answer(text,app)
			check(not answer.is_empty() and answer.text!=('self_'+cases[text]),'Localized app facts '+locale+'/'+cases[text])
	check('physical body' not in knowledge.system_text('en') and 'Do not deny' in knowledge.system_text('en'),'Conversational role knows host tools without fictitious action claims')
	check(app.router.route('корень из 1444').get('tool')=='math.calculate','Reported root query uses no-model calculator')
	check(app.router.route('скопируй весь чат').get('tool')=='chat.copy','Copy request uses an actual executor')
	var memory=preload('res://src/core/conversation_memory.gd').new();memory.path='user://copy015-history.json';memory.truncated=true
	check(memory.save_history([{"speaker":"user","text":"persisted"}]),'Truncation metadata saved with optional history')
	var loaded=preload('res://src/core/conversation_memory.gd').new();loaded.path=memory.path
	check(loaded.load_history() and loaded.truncated,'Truncation disclosure survives restart')
	check(loaded.erase() and not loaded.truncated,'Explicit clear resets truncation marker')
	print('COPY_KNOWLEDGE015_TESTS: %d checks, %d failures; real transcript formatting/history, clipboard injected' %[checks,failures])
	quit(0 if failures==0 else 1)
