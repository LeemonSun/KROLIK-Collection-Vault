extends SceneTree
const Llama=preload('res://src/providers/llama_http_provider.gd')
class Seeded extends Llama:
 func _post(path,payload):
  if path=='/v1/chat/completions':payload['seed']=42
  return super._post(path,payload)
class Runtime extends Node:
 var status='ai_ready'
 var generation_busy=false
 var manifest={}
 func installed():return true
 func touch():pass
 func stop():pass
var raw=[]
func _initialize():run.call_deferred()
func run():
 var app=root.get_node('App');app.cancel();app.profile_name='lite';app.resource_mode='standard'
 var original=[app.provider,app.local_runtime,app.provider_name,app.local_ai_enabled]
 var provider=Seeded.new();var runtime=Runtime.new();app.add_child(provider);app.add_child(runtime)
 provider.configure_local(OS.get_environment('LEEMON_TEST_PORT').to_int(),OS.get_environment('LEEMON_TEST_TOKEN'))
 provider.completed.connect(func(text):raw.append({'text':text,'usage':provider.last_usage.duplicate(true),'truncated':provider.last_truncated}))
 provider.completed.connect(app._on_answer);provider.failed.connect(app._on_failure)
 app.provider=provider;app.local_runtime=runtime;app.provider_name='local_worker';app.local_ai_enabled=true
 var cases=[]
 var seed=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/quality017-cases.json'))
 for row in seed.cases:
  if row.category in ['draft_missing','draft_given']:cases.append(row)
 var holdouts=[['ru','notice','Составь короткое объявление: библиотека закрыта в пятницу.'],['ru','thanks','Напиши короткое письмо с благодарностью за помощь.'],['en','notice','Draft a short notice: the library is closed on Friday.'],['en','thanks','Write a short email thanking someone for their help.'],['zh-Hans','notice','请写简短通知：图书馆周五闭馆。'],['zh-Hans','thanks','请写一封简短的感谢邮件，感谢对方提供帮助。']]
 for row in holdouts:cases.append({'id':row[0]+'_'+row[1]+'_holdout','locale':row[0],'category':row[1],'input':row[2]})
 var report={'scope':'Actual App and owned pinned2B HTTP; synthetic standalone short drafts; seed42 fixture only; no Windows actions','cases':[]}
 for spec in cases:
  app.cancel();app.session_turns=[];app.set_locale(spec.locale);raw=[]
  var started=Time.get_ticks_msec();app.submit(spec.input)
  var deadline=Time.get_ticks_msec()+60000
  while app.state.current=='thinking' and Time.get_ticks_msec()<deadline:await process_frame
  var timed_out=app.state.current=='thinking'
  if timed_out:app.cancel()
  var row=spec.duplicate(true);row['raw_generations']=raw.duplicate(true);row['delivered']=app.messages[-1].text;row['draft_delivered']=row.delivered.begins_with(app.t('chat_draft_heading'));row['timeout']=timed_out;row['wall_ms']=Time.get_ticks_msec()-started
  report.cases.append(row)
  var file=FileAccess.open(OS.get_environment('LEEMON_REAL_REPORT'),FileAccess.WRITE);file.store_string(JSON.stringify(report,'  '));file.close()
  print('REAL_DRAFT020 '+JSON.stringify(row))
 app.cancel();app.provider=original[0];app.local_runtime=original[1];app.provider_name=original[2];app.local_ai_enabled=original[3]
 provider.queue_free();runtime.queue_free();quit()
