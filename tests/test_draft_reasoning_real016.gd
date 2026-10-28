extends SceneTree
var checks=0
var failures=0
var reply=''
var error=''
var provider
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func infer(messages,options):
	reply='';error='';provider.submit(messages,options)
	var deadline=Time.get_ticks_msec()+175000
	while provider.busy and Time.get_ticks_msec()<deadline:await process_frame
	if provider.busy:provider.cancel();error='timeout'
	print('REAL_DRAFT_REASONING ',JSON.stringify({'answer':reply,'error':error,'usage':provider.last_usage,'truncated':provider.last_truncated}))
	return reply
func run():
	provider=preload('res://src/providers/llama_http_provider.gd').new();root.add_child(provider)
	provider.completed.connect(func(text):reply=text);provider.failed.connect(func(key):error=key)
	check(provider.configure_local(int(OS.get_environment('COMPANION_TEST_PORT')),OS.get_environment('COMPANION_TEST_TOKEN')),'Owned model endpoint')
	var target={'handle':'12','target_pid':34,'started':'56','title':'Unfamiliar editor','app':'editor'}
	var nodes=[{'id':'1','name':'Body','type':'ControlType.Edit','enabled':true,'write':true}]
	for spec in [['ru','Составь в поле Body короткое приглашение на встречу завтра, одним предложением.'],['en','Compose a one-sentence invitation for a meeting tomorrow in Body.'],['zh-Hans','请写一句邀请明天参加会议的话，填入Body。']]:
		var planner=preload('res://src/core/action_proposal.gd').new();var now=Time.get_ticks_msec();var context=planner.prepare(spec[1],target,nodes,now,spec[0],true)
		var raw=await infer(context.messages,{'max_tokens':256,'context_tokens':2048,'response_schema':context.schema})
		var plan=planner.validate(raw,context,target,Time.get_ticks_msec())
		check(plan.get('ok',false) and plan.get('generated',false) and plan.get('action')=='write','Actual model composes valid reviewed draft '+spec[0])
		var text=plan.get('text','').to_lower();var relevant=false
		for word in ['встреч','встрет','meeting','会议']:if word in text:relevant=true
		check(relevant and not text in spec[1],'Draft is new content related to the goal '+spec[0])
		check(not 'я встретимся' in text and not '2 pm' in text and not 'conference room' in text,'No observed invented detail or malformed phrase '+spec[0])
	# A representative combined logic/personality request, kept inside the current input budget.
	var query='Ответь по пунктам кратко. 1. Объясни разницу между умным и мудрым. 2. Можешь ли ты ошибаться? Приведи пример возможной ошибки, не выдумывай свою биографию. 3. «Это предложение ложно» — истинно оно или нет? 4. Знать всё без возможности применить или уметь применять, зная мало — что выбрал бы в этом мысленном эксперименте и почему?'
	var knowledge=preload('res://src/core/self_knowledge.gd').new()
	await infer([{'role':'system','content':knowledge.factual_text('ru')},{'role':'user','content':query}],{'max_tokens':384,'context_tokens':2048})
	var draft=reply
	var quality=preload('res://src/core/response_quality.gd').new()
	await infer([{'role':'system','content':quality.review_system('ru')},{'role':'user','content':'USER REQUEST:\n'+query+'\nDRAFT DATA:\n'+draft}],{'max_tokens':384,'context_tokens':2048})
	var lower=reply.to_lower()
	check(not reply.is_empty() and error.is_empty(),'Actual model answers combined reasoning request')
	check(not 'я не могу ошибаться' in lower and not 'я не могу выполнить этот тест' in lower,'No false infallibility or blanket refusal')
	check(('ошиб' in lower) and ('парадокс' in lower or 'противореч' in lower) and not 'следовательно, само предложение истинно' in lower,'Reviewed answer addresses fallibility and avoids observed contradiction')
	print('DRAFT_REASONING_REAL016_TESTS: %d checks, %d failures; actual pinned2B, synthetic editor, narrow reasoning sample' %[checks,failures])
	quit(0 if failures==0 else 1)
