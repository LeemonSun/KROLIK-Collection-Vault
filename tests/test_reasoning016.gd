extends SceneTree
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func run():
	var app=root.get_node('App');var q=app.quality
	for pair in [['Я не могу ошибаться, потому что у меня нет сознания.','Можешь ошибаться?'],['I cannot make mistakes because I have no consciousness.','Can you be wrong?'],['我不会犯错，因为我没有意识。','你会出错吗？']]:
		check(q.impossible_infallibility(pair[0],pair[1]),'Narrow false infallibility premise triggers a single retry')
	check(not q.impossible_infallibility('Да, могу ошибаться. Например, неверно умножить два числа.','Можешь ошибаться?'),'Honest error admission unaffected')
	check(not q.impossible_infallibility('Я не могу ошибаться, потому что...','Повтори цитату дословно'),'Quoted text not treated as a live claim')
	check(not q.impossible_infallibility('Не помогу удалить чужие файлы.','Что ты умеешь?'),'Concrete action boundary is not censored away')
	for locale in ['ru','en','zh-Hans']:
		var system=app.self_knowledge.system_text(locale);var factual=app.self_knowledge.factual_text(locale)
		check('can make reasoning and factual mistakes' in system and '%s' not in system,'Localized reasoning premise '+locale)
		check('Answer benign thought experiments directly' in factual and '%s' not in factual,'Reasoning hint survives factual routing '+locale)
	check(app.self_knowledge.response_budget('One? Two? Three?',{'max_tokens':96}).max_tokens==384,'Multi-question response gets bounded extended output')
	check(app.self_knowledge.response_budget('Hi',{'max_tokens':96}).max_tokens==96,'Ordinary short message retains economical budget')
	var fixture=preload('res://tests/test_adaptive015.gd');var old_access=app.application_access;var old_provider=app.provider;var old_runtime=app.local_runtime;var old_name=app.provider_name
	app.cancel();var access=fixture.FakeAccess.new();app.add_child(access);access.target={'handle':'1','target_pid':2,'started':'3','title':'Synthetic editor','app':'editor'}
	var provider=fixture.FakeProvider.new();app.add_child(provider);var runtime=fixture.FakeRuntime.new();app.add_child(runtime)
	app.application_access=access;app.provider=provider;app.local_runtime=runtime;app.provider_name='local_worker'
	app.submit('Составь короткое приглашение в поле Body')
	check(app.agent.active and access.requests[-1].operation=='inspect','Pinned-window compose request uses observe-plan loop without developer prefix')
	app.cancel();app.application_access=old_access;app.provider=old_provider;app.local_runtime=old_runtime;app.provider_name=old_name
	access.queue_free();provider.queue_free();runtime.queue_free()
	check(q.needs_review('1. First 2. Second 3. Third') and not q.needs_review('Hi, how are you?'),'Selective review detects multi-part tasks without taxing ordinary chat')
	var old_provider2=app.provider;var old_name2=app.provider_name
	var fake=fixture.FakeProvider.new();app.add_child(fake);app.provider=fake;app.provider_name='local_worker';app.cancel()
	app._submit_model_text('1. Compare smart and wise. 2. Can you err? 3. Explain a paradox.')
	var prior=app.messages.size();var turns=app.session_turns.size()
	app._on_answer('A draft with a possible contradiction.')
	check(app.answer_reviewing and fake.calls.size()==2 and app.messages.size()==prior,'Complex answer draft stays private during one additional review')
	app._on_answer('A corrected final answer.')
	check(not app.answer_reviewing and fake.calls.size()==2 and app.messages[-1].text=='A corrected final answer.','Only reviewed final is displayed; no endless critic loop')
	check(app.session_turns[-1].content=='A corrected final answer.','Only final enters model history')
	app._submit_model_text('1. A 2. B 3. C');app._on_answer('Another draft.');app.cancel()
	app._on_answer('Late canceled review.')
	check(app.messages[-1].text!='Late canceled review.' and not app.answer_reviewing,'Cancellation suppresses late review')
	app.provider=old_provider2;app.provider_name=old_name2;fake.queue_free()
	print('REASONING016_TESTS: %d checks, %d failures; deterministic behavior, not model IQ measurement' %[checks,failures])
	quit(0 if failures==0 else 1)
