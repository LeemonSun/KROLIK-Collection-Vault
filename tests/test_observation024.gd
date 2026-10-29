extends SceneTree
var checks=0
var failures=0
const Guard=preload('res://src/core/intent_constraints.gd')
const Planner=preload('res://src/core/action_proposal.gd')
class Access extends 'res://src/tools/application_access.gd':
 var requests=[]
 func _request(payload):operation=payload.operation;requests.append(payload.duplicate(true));return true
class Runtime extends Node:
 var status='ai_ready'
 var generation_busy=false
 var manifest={}
 func installed():return true
 func touch():pass
 func stop():pass
class Provider extends Node:
 var requests=[]
 func submit(messages,options):requests.append({'messages':messages,'options':options});return true
 func cancel():pass
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func target():return {'handle':'123','target_pid':234,'started':'345','title':'Third-party fixture','app':'Client'}
func controls(count=70):
 var result=[]
 for i in range(count):result.append({'id':'1,'+str(i+1),'name':'Control '+str(i).pad_zeros(3),'type':'ControlType.Button','automation_id':'control'+str(i),'ancestors':[],'enabled':true,'invoke':true})
 return result
func observe(access,nodes):access._finish({'status':'inspected','title':target().title,'nodes':nodes,'partial':false})
func run():
 var router=preload('res://src/core/router.gd').new()
 for text in ['включи впн, не закрывай окно','подключи мой впн и не закрывай приложение','enable my vpn, do not close the window',"connect my vpn and don't close this app"]:
  var parsed=Guard.analyze(text)
  check(not parsed.blocked and parsed.no_close,'Positive request + trailing no-close condition '+text)
  check(router.route(text).get('tool')=='agent.discover','Constraint survives general discovery routing '+text)
  for label in ['Close','Exit','Quit','Закрыть','×']:check(not Guard.permits_control(label,text),'No-close filters '+label)
  check(Guard.permits_control('Connect',text),'Unrelated action retained')
 for text in ['не включай впн','do not connect vpn',"don't click Delete",'включи впн, не отправляй пароль','не закрывай окно','不要连接VPN']:
  check(Guard.analyze(text).blocked,'Leading or unsupported negation stays blocked '+text)
 for text in ['открой неоновую панель','open Notepad','write Note: do not close the window','впиши Заметка: не отправляй письмо','打开设置，特别是网络']:
  check(not Guard.analyze(text).blocked,'Words/literal content are not negative authority '+text)
 var planner=Planner.new();var nodes=controls();var context=planner.prepare('Включи сеть в приложении',target(),nodes,Time.get_ticks_msec(),'ru',true)
 var flattened=[];var choices=[]
 for page in context.pages:
  check(JSON.parse_string(page.messages[1].content).controls.size()<=24,'Page control count bounded')
  var bytes=0
  for item in JSON.parse_string(page.messages[1].content).controls:bytes+=JSON.stringify(item).to_utf8_buffer().size()
  check(bytes<=2200,'Page control bytes bounded')
  for alias in page.map:flattened.append(page.map[alias].id);choices.append(alias)
 check(flattened.size()==nodes.size() and context.coverage.covered==nodes.size() and context.coverage.oversized==0,'Every eligible captured control reaches a page')
 var repeated=planner.prepare('Включи сеть в приложении',target(),nodes,Time.get_ticks_msec(),'ru',true);var again=[]
 for page in repeated.pages:
  for alias in page.map:again.append(page.map[alias].id)
 check(flattened==again and flattened[0]=='1,1' and flattened[-1]=='1,70','Equal-score order is explicitly deterministic')
 var focused=nodes.duplicate(true);focused[-1]['focused']=true
 check(planner.prepare('Включи сеть',target(),focused,Time.get_ticks_msec(),'ru',true).map.values()[0].id=='1,70','Native focus can prioritize a captured candidate')
 var limited=planner.prepare('Включи сеть, не закрывай окно',target(),[nodes[0].merged({'name':'Close'},true),nodes[1].merged({'name':'Connect'},true)],Time.get_ticks_msec(),'ru',true)
 check(not limited.map.values().any(func(n):return n.name=='Close'),'No-close condition enforced at proposal boundary')
 var scan=preload('res://src/core/ui_observation_scan.gd').new();scan.begin(context)
 check(planner.validate('{"choice":"invoke:'+choices[-1]+'"}',scan.current(),target(),Time.get_ticks_msec()).get('ok',false)==false,'Other page aliases cannot bypass schema binding')
 var previous_page={"ok":true,"action":"invoke","node":nodes[0]}
 scan.begin(context);var result=scan.accept(previous_page)
 while result=="next":result=scan.accept({"ok":true,"action":"none"})
 check(result=="winner" and scan.winners[0].plan.node.id==nodes[0].id,'Unique earlier-page proposal survives later none responses')
 var bounded=context.duplicate(true);bounded.pages=[]
 for i in range(13):bounded.pages.append(context.pages[0])
 scan.begin(bounded);result="next"
 while result=="next":result=scan.accept({"ok":true,"action":"none"})
 check(result=="budget" and scan.calls==12,'At most12read-only page requests, no unbounded scan')
 var app=root.get_node('App');app.cancel();var original=[app.application_access,app.provider,app.local_runtime,app.provider_name]
 var access=Access.new();var provider=Provider.new();var runtime=Runtime.new()
 for node in [access,provider,runtime]:app.add_child(node)
 app.application_access=access;app.provider=provider;app.local_runtime=runtime;app.provider_name='local_worker';access.target=target()
 access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed)
 app.begin_agent('Включи сетевое подключение');observe(access,nodes)
 check(provider.requests[-1].options.max_tokens==64,'Action-only selection reserves64 output tokens instead of256')
 var pages=app.goal_scan.pages.size();check(pages>1 and app.goal_mode=='thinking','Shared App loop starts a paged snapshot')
 var alias=''
 while app.goal_mode=='thinking':
  var last=app.goal_scan.index==pages-1
  if last:
   for key in app.goal_context.map:
    if app.goal_context.map[key].id==nodes[-1].id:alias=key
  app._on_answer(JSON.stringify({'choice':'invoke:'+alias if last else 'none'}))
 check(app.goal_mode=='proposal' and app.goal_plan.node.id==nodes[-1].id,'Action from final page reaches ordinary review')
 check(provider.requests.size()==pages and access.requests.size()==1,'Page reads share one snapshot; no OS effects/model parallelism')
 app.confirm_window_goal();observe(access,nodes)
 check(access.requests[-1].operation=='invoke' and access.requests[-1].element_id==nodes[-1].id,'Only approved final-page action executes after fresh preflight')
 app.cancel();access.target=target();provider.requests=[];access.requests=[]
 app.begin_agent('Включи сетевое подключение');observe(access,nodes);pages=app.goal_scan.pages.size()
 while app.goal_mode=='thinking':
  var choose=app.goal_scan.index in [0,pages-1];var first=app.goal_context.map.keys()[0]
  app._on_answer(JSON.stringify({'choice':'invoke:'+first if choose else 'none'}))
 check(app.goal_mode.is_empty() and not app.agent.active and access.requests.size()==1,'Multiple page winners stop without choosing or clicking')
 app.begin_agent('Включи сетевое подключение');observe(access,nodes);app.cancel();app._on_answer('{"choice":"none"}')
 check(not app.goal_scan.active and app.goal_scan.pages.is_empty() and app.goal_mode.is_empty(),'Stop erases pages and ignores late answer')
 app.application_access=original[0];app.provider=original[1];app.local_runtime=original[2];app.provider_name=original[3]
 for node in [access,provider,runtime]:node.queue_free()
 var rt=preload('res://src/runtime/local_runtime.gd').new();rt.token='DO_NOT_LOG_THIS';rt.manifest={'model':{'file':'test.gguf'}};var profile=preload('res://src/core/profile.gd').new();var effective=profile.effective('lite','quiet');var summary=rt._describe_launch(effective,8)
 check(summary.threads==1 and summary['batch-size']==32 and summary.idle_unload_seconds==30,'Quiet launch summary uses effective settings, not base profile')
 check(not JSON.stringify(summary).contains(rt.token) and not summary.has('model') and not summary.has('api-key'),'Diagnostics never expose token or model path')
 rt.free()
 print('OBSERVATION024: %d checks, %d failures; synthetic model/UIA, no actual Windows or neural quality benchmark' %[checks,failures]);quit(0 if failures==0 else 1)
