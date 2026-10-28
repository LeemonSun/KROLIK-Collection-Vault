extends SceneTree
var checks=0
var failures=0
var reply=""
var error=""
var provider
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func infer(context):
	reply="";error=""
	provider.submit(context.messages,{"max_tokens":256,"context_tokens":2048,"response_schema":context.schema})
	var deadline=Time.get_ticks_msec()+90000
	while provider.busy and Time.get_ticks_msec()<deadline:await process_frame
	if provider.busy:provider.cancel();error="timeout"
	print('REAL_AGENT ',JSON.stringify({'answer':reply,'error':error,'usage':provider.last_usage}))
	return reply
func run():
	provider=preload('res://src/providers/llama_http_provider.gd').new();root.add_child(provider)
	provider.completed.connect(func(text):reply=text);provider.failed.connect(func(key):error=key)
	check(provider.configure_local(int(OS.get_environment('COMPANION_TEST_PORT')),OS.get_environment('COMPANION_TEST_TOKEN')),'Owned model endpoint')
	var fixture=preload('res://tests/test_adaptive015.gd').new()
	for spec in [['ru','Покажи, где увеличить размер шрифта'],['en','Find where I can change the font size'],['zh-Hans','找到调整字体大小的位置']]:
		var agent=preload('res://src/core/adaptive_agent.gd').new();var identity=fixture.identity()
		agent.begin(spec[1],identity,Time.get_ticks_msec())
		for stage in [0,1]:
			var now=Time.get_ticks_msec();var context=agent.prepare(identity,fixture.nodes(stage),now,now,spec[0])
			var raw=await infer(context);var plan=agent.validate(raw,context,identity,Time.get_ticks_msec())
			var name='Appearance' if stage==0 else 'Fonts';var kind='select' if stage==0 else 'expand'
			var correct=plan.get('ok',false) and plan.get('action')==kind and plan.get('node',{}).get('name')==name
			check(correct,'Real model semantic next step '+spec[0]+'/'+str(stage))
			if not correct:break
			agent.record(plan,true,identity,Time.get_ticks_msec())
	fixture.free()
	print('AGENT_REAL016_TESTS: %d checks, %d failures; real pinned2B CPU, synthetic observed windows; no Windows effects' %[checks,failures])
	quit(0 if failures==0 else 1)
