extends SceneTree
const Agent=preload('res://src/core/adaptive_agent.gd')
class Capture extends Node:
 var calls=[]
 func submit(messages,options):calls.append({'messages':messages.duplicate(true),'options':options.duplicate(true)});return true
 func cancel():pass
class Runtime extends Node:
 var status='ai_ready'
 var generation_busy=false
 var manifest={}
 func installed():return true
 func touch():pass
 func stop():pass
func _initialize():run.call_deferred()
func run():
 var app=root.get_node('App');app.cancel();app.profile_name='lite';app.resource_mode='standard'
 var original=[app.provider,app.local_runtime,app.provider_name,app.local_ai_enabled]
 var capture=Capture.new();var runtime=Runtime.new();app.add_child(capture);app.add_child(runtime)
 app.provider=capture;app.local_runtime=runtime;app.provider_name='local_worker';app.local_ai_enabled=true
 var seed=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/quality017-cases.json'))
 var rows=[]
 for spec in seed.cases:
  app.cancel();app.session_turns=[];app.set_locale(spec.locale);capture.calls=[]
  var route=app.router.route(spec.input)
  var before=app.messages.size();app.submit(spec.input)
  var row=spec.duplicate(true);row['route']=route;row['scope']='synthetic acceptance case'
  if not capture.calls.is_empty():
   row.merge(capture.calls[-1],true);row['execution']='model'
  else:
   row['execution']='deterministic';row['answer']=app.messages[-1].text if app.messages.size()>before else ''
  rows.append(row)
 var goals={
 'ru':['Выбери Options в разделе Editor','Раскрой Fonts в разделе Appearance','Впиши hello в поле Search'],
 'en':['Select Options in the Editor section','Expand Fonts in Appearance','Write hello into the Search field'],
 'zh-Hans':['选择Editor区域的Options标签','展开Appearance区域的Fonts','在Search输入框中输入hello']}
 var identity={'handle':'123','target_pid':234,'started':'345','title':'Synthetic editor','app':'Unknown'}
 var nodes=[{'id':'1,1','name':'Options','type':'ControlType.TabItem','automation_id':'options','ancestors':[{'name':'Player','type':'ControlType.Pane','automation_id':'player'}],'enabled':true,'select':true,'selected':false},{'id':'1,2','name':'Options','type':'ControlType.TabItem','automation_id':'options','ancestors':[{'name':'Editor','type':'ControlType.Pane','automation_id':'editor'}],'enabled':true,'select':true,'selected':false},{'id':'1,3','name':'Fonts','type':'ControlType.TreeItem','automation_id':'fonts','ancestors':[{'name':'Appearance','type':'ControlType.Pane','automation_id':'appearance'}],'enabled':true,'expand':true,'expansion':0},{'id':'1,4','name':'Search','type':'ControlType.Edit','automation_id':'search','ancestors':[{'name':'Editor','type':'ControlType.Pane','automation_id':'editor'}],'enabled':true,'write':true}]
 for locale in goals:
  for index in range(3):
   var goal=goals[locale][index];var agent=Agent.new();var now=Time.get_ticks_msec();agent.begin(goal,identity,now)
   var ctx=agent.prepare(identity,nodes,now,now,locale,{'partial':true})
   var expected_id=['1,2','1,3','1,4'][index];var expected_action=['select','expand','write'][index];var choice=''
   for alias in ctx.map:
    if ctx.map[alias].id==expected_id:choice=expected_action+':'+alias
   rows.append({'id':locale+'_uia_'+str(index),'locale':locale,'category':'uia','execution':'model','input':goal,'messages':ctx.messages,'options':{'max_tokens':256,'context_tokens':2048,'response_schema':ctx.schema},'expected_choice':choice,'expected_text':'hello' if index==2 else '', 'manual_rubric':'Exactly the observed scoped target/action; literal input hello only for write; no execution.'})
 app.cancel();app.provider=original[0];app.local_runtime=original[1];app.provider_name=original[2];app.local_ai_enabled=original[3]
 var file=FileAccess.open(OS.get_environment('LEEMON_BENCH_FIXTURE'),FileAccess.WRITE);file.store_string(JSON.stringify(rows,'  '));file.close()
 print('QUALITY020_EXPORT: ',rows.size(),' cases; actual App routes/prompts, synthetic goals, no model inference')
 quit()
