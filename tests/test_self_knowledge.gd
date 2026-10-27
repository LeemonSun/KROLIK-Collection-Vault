extends SceneTree
const Knowledge=preload('res://src/core/self_knowledge.gd')
var checks=0
var failures=0
class FakeProvider extends Node:
	var calls=0
	func submit(_messages,_options):calls+=1;return true
	func cancel():pass
func check(ok,description):
	checks+=1
	if not ok:failures+=1;push_error(description)
func _initialize():_run.call_deferred()
func _run():
	var app=root.get_node('App')
	var knowledge=Knowledge.new()
	var examples={
	 'скажи что либо':'greeting','скажи что-либо':'greeting','как дела?':'greeting',
	 'какая модель у тебя внутри':'runtime_model','что ты за модель ии':'model','what model are you':'model','你是什么模型':'model',
	 'тобишь тебя написал чат гпт и уже переписал?':'origin',
	 'ты как то быстро отвечаешь ты сейчас работаетшь от интеренете или локально?:':'offline',
	 'тобишь если у меня не будет подключения ты будешь молчать?':'offline',
	 'как думаешь сильную ли ты сейчас нагрузку окзаываешь на пк?':'load',
	 'как сильно ты влияешь на пк':'load','how much ram do you use?':'load',
	 'наш чат куда то сохроняется или обнулиться как только я закрою тебя?':'memory',
	 'я уже успел тебе добавить память?':'memory','память я тебе добавил?':'memory','авто память заметки я уже поставил?':'memory',
	 'ты уже научилась сама перемещаться по пк?':'motion','скажи что ты умеешь':'capabilities',
	 'как думаешь наш план с чатом гпт есть патанциал? что он уже тебе добавил':'capabilities',
	 'какая погода сейчас в Москве?':'weather','weather today in London':'weather','今天天气如何':'weather',
	 'йоу здарова лимон':'greeting','Hi Leemon!':'greeting','так я лимон или ты лимон?':'identity','за счёт чего ты работаешь?':'power','你好':'greeting'}
	for code in ['ru','en','zh-Hans']:
		app.l10n.set_locale(code)
		for text in examples:
			var result=knowledge.answer(text,app)
			check(result.get('intent')==examples[text],code+' classified '+text)
			check(not result.get('text','').is_empty() and not result.get('text','').begins_with('self_'),code+' localized trusted answer')
		var memory=knowledge.answer('наш чат',app).text
		check('{' not in memory,'No unfilled placeholders')
		check('18' not in knowledge.answer('как дела',app).text,'No fake live temperature')
	for text in ['на какой мы планете?','что за модель атома Резерфорда','расскажи об истории OpenAI','как работает интернет','как снизить нагрузку в игре','объясни перемещение ферзя','скажи что-нибудь про Марс']:
		check(knowledge.answer(text,app).is_empty(),'General question stays with LLM: '+text)
	var source=app.profiles.config('lite')
	check(knowledge.response_budget('привет',source).max_tokens==source.max_tokens,'Small talk retains light budget')
	check(knowledge.response_budget('Объясни подробно',source).max_tokens==192,'Explicit detailed answer has bounded larger output')
	check(source.max_tokens==96,'Profile unchanged')
	check(knowledge.system_text('ru').to_utf8_buffer().size()<1200,'Persona fits the small context budget')
	var original=app.provider
	var fake=FakeProvider.new()
	app.add_child(fake)
	app.provider=fake
	var old_name=app.provider_name
	app.provider_name='local_worker'
	app.l10n.set_locale('ru')
	app.submit('какая модель у тебя внутри')
	check(fake.calls==0,'Own-model fact needs no inference')
	check(app.messages[-1].text.contains('Qwen3') and not app.messages[-1].text.contains('OpenAI'),'Owned runtime identity is grounded')
	app.submit('наш чат куда то сохроняется?')
	check(fake.calls==0,'Memory fact needs no inference')
	check(app.messages[-1].text.contains('настройках') and app.messages[-1].text.contains('Автоматического'),'Memory limits are honest')
	app.local_ai_enabled=false
	app.submit('на какой мы планете?')
	check(fake.calls==1,'Ordinary question still uses conversation model')
	app.cancel()
	app.provider=original
	app.provider_name='llama_loopback'
	check(knowledge.answer('are you offline',app).text.contains('не проверяю'),'Unknown developer backend is not promised offline')
	app.provider_name=old_name
	fake.queue_free()
	print('SELF_KNOWLEDGE_TESTS: %s checks, %s failures; transcript regressions, 3 languages, runtime facts, free conversation' %[checks,failures])
	quit(0 if failures==0 else 1)
