extends SceneTree
var checks=0
var failures=0
class Actions extends 'res://src/tools/desktop_actions.gd':
	var calls=[]
	func request(target):calls.append(target);return true
class Catalog extends Node:
	var calls=0
	func scan():calls+=1;return true
	func cancel():pass
class Runtime extends Node:
	var pid=42
	var generation_busy=true
	var starting=false
	var status='ai_ready'
	var stops=0
	func touch():pass
	func installed():return true
	func stop():stops+=1;generation_busy=false;starting=false
class Provider extends Node:
	var cancels=0
	func cancel():cancels+=1
func _initialize():run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func audio(seconds,amplitude,stereo=false,antiphase=false,voice_seconds=-1.0):
	var wav=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate=16000;wav.stereo=stereo
	var data=PackedByteArray();var channels=2 if stereo else 1;data.resize(int(seconds*16000)*2*channels)
	for i in range(int(seconds*16000)):
		var v=int(sin(float(i)*TAU*440/16000)*amplitude) if voice_seconds<0 or i<voice_seconds*16000 else 0
		data.encode_s16(i*2*channels,v)
		if stereo:data.encode_s16(i*4+2,-v if antiphase else v)
	wav.data=data;return wav
func run():
	var router=preload('res://src/core/router.gd').new()
	for input in ['посчитай в калькуляторе 100*10','посчитай в калькутор 100*10','calculate in calculator 100*10']:
		var command=router.route(input)
		check(command.get('tool')=='math.calculate' and command.args.expression=='100*10','Arithmetic bypasses model: '+input)
	for input in ['открой блокнот и создай файл с надписью 1','создай текстовый файл с текстом 1','open notepad and create a file with text 1']:
		var command=router.route(input)
		check(command.get('tool')=='documents.create' and command.args.text=='1' and command.args.name=='','Exact content is not an app-search goal: '+input)
	var named=router.route('открой блокнот и создай файл с названием 1')
	check(named.get('tool')=='documents.create' and named.args.name=='1' and named.args.text=='','Name and content remain distinct')
	var docs=preload('res://src/tools/text_documents.gd').new();docs.directory='user://repair027-'+str(Time.get_ticks_usec())
	var saved=docs.create_text('1','sample')
	check(saved.ok and FileAccess.get_file_as_string(saved.path)=='1' and saved.name=='sample.txt','Real new UTF8 file has requested name and contents')
	check(not docs.create_text('overwritten','sample').ok and FileAccess.get_file_as_string(saved.path)=='1','Existing files never silently overwritten')
	for name in ['../escape','CON','AUX','C:/outside','..','COM1']:
		check(not docs.create_text('1',name).ok,'Invalid/reserved/traversal name rejected '+name)
	var patch=router.route('в файле "C:\\example.ini" замени "old" на "new"')
	check(patch.get('tool')=='files.review_literal' and patch.args.find=='old' and patch.args.replacement=='new','Literal existing-file request opens review, not generation')
	var endpoint=preload('res://src/tools/speech_endpoint.gd').new()
	check(not endpoint.feed(0.01,0.2) and endpoint.heard,'Speech detected from explicit recording')
	check(not endpoint.feed(0,0.4) and endpoint.feed(0,0.31),'Pause ends utterance without waiting20seconds')
	endpoint.reset();check(endpoint.feed(0,4.01),'No-signal recording is bounded')
	var prepare=preload('res://src/tools/voice_audio.gd').new()
	var quiet_clip=audio(4,90,false,false,0.4)
	var started=Time.get_ticks_usec();var short=prepare.prepare(quiet_clip);var elapsed=Time.get_ticks_usec()-started
	check(short.ok and short.seconds<1 and short.gain>1,'Quiet short phrase survives long trailing silence and is trimmed')
	var phase=prepare.prepare(audio(1,4000,true,true))
	check(phase.ok and phase.rms>0.05,'Opposite stereo channels do not erase speech')
	check(prepare.prepare(audio(1,0)).get('key')=='voice_silence','True silence still rejected')
	print('PCM027 cached processing4seconds_us=',elapsed,'; synthetic tone, not speech accuracy')
	var app=root.get_node('App');app.cancel();var original=[app.desktop_actions,app.catalog,app.local_runtime,app.provider,app.provider_name]
	var actions=Actions.new();var catalog=Catalog.new();var runtime=Runtime.new();var provider=Provider.new()
	for node in [actions,catalog,runtime,provider]:app.add_child(node)
	app.desktop_actions=actions;app.catalog=catalog;app.local_runtime=runtime;app.provider=provider;app.provider_name='local_worker'
	runtime.generation_busy=false
	app.submit('открой калькулятор')
	check(actions.calls==['calculator'] and catalog.calls==0,'Calculator opens via fixed native target, without catalog scan or inference')
	app.cancel();app.submit('открой MyThirdParty')
	check(actions.calls[-1]=='MyThirdParty' and catalog.calls==0,'All explicit named programs have a non-neural native lookup path')
	app.cancel();var stops_before=runtime.stops;runtime.generation_busy=true;app.state.transition('thinking');app.pending_user_text='request';app.cancel()
	check(runtime.stops==stops_before+1 and provider.cancels>0 and app.state.current=='idle' and app.pending_user_text.is_empty(),'Cancel stops owned compute and resets conversation immediately')
	runtime.generation_busy=false;app.state.transition('thinking');app.pending_user_text='blocked request';app.submit('стоп')
	check(app.state.current=='idle' and app.pending_user_text.is_empty(),'Natural Stop bypasses the busy guard and chat queue')
	var before=app.messages.size();app._on_answer('late invented answer');app._on_failure('model_connection_failed')
	check(app.messages.size()==before,'Late cancelled result/failure does not revive conversation')
	var resolver=preload('res://src/core/app_resolver.gd').new()
	var records=[{'id':'a'.repeat(64),'stamp':'1:1','name':'notepad','aliases':['блокнот']},{'id':'b'.repeat(64),'stamp':'1:1','name':'Opera GX'}]
	check(resolver.prepare('блокнот','',records,Time.get_ticks_msec()).direct.get('name')=='notepad','Observed Russian aliases survive application resolution')
	check(resolver.prepare('unrelated editor','',records,Time.get_ticks_msec()).matched.is_empty(),'No fabricated relation to browser')
	if OS.get_name()=="Linux":
		var real=preload("res://src/runtime/local_runtime.gd").new();app.add_child(real)
		var heartbeat=ProjectSettings.globalize_path("user://heartbeat-"+str(Time.get_ticks_usec())+".txt")
		var code="import sys,time\nfor i in range(600):\n with open(sys.argv[1],'a') as f: f.write('x')\n time.sleep(.05)"
		real.pid=OS.create_process("/usr/bin/python3",["-c",code,heartbeat],false);var child=real.pid
		real.generation_busy=true;app.local_runtime=real
		var deadline=Time.get_ticks_msec()+5000
		while not FileAccess.file_exists(heartbeat) and Time.get_ticks_msec()<deadline:await process_frame
		check(FileAccess.file_exists(heartbeat),"Actual owned helper started and produced a heartbeat")
		app.state.transition("thinking");app.cancel();await create_timer(0.1).timeout
		var stopped=FileAccess.get_file_as_bytes(heartbeat).size()
		await create_timer(0.25).timeout
		check(child>0 and stopped>0 and FileAccess.get_file_as_bytes(heartbeat).size()==stopped and real.pid==-1 and app.state.current=="idle","Cancel terminates actual owned compute: heartbeat stops and no callback revives state")
		app.local_runtime=runtime;real.queue_free()

	app.cancel();app.desktop_actions=original[0];app.catalog=original[1];app.local_runtime=original[2];app.provider=original[3];app.provider_name=original[4]
	for node in [actions,catalog,runtime,provider]:node.queue_free()
	print('REPAIR027: %d checks, %d failures; real file/PCM with synthetic transport, no Windows/microphone proof' %[checks,failures]);quit(0 if failures==0 else 1)
