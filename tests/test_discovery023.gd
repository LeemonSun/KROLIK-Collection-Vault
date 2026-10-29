extends SceneTree
var checks=0
var failures=0
const Resolver=preload('res://src/core/app_resolver.gd')
class Catalog extends Node:
 signal completed(result)
 var scans=0
 var opened=[]
 func scan():scans+=1;return true
 func open_record(record):opened.append(record.duplicate(true));return true
 func cancel():pass
class Access extends 'res://src/tools/application_access.gd':
 var calls=0
 func inspect(_silent=false):calls+=1;return true
class Runtime extends Node:
 var status='ai_ready'
 var generation_busy=false
 var manifest={}
 var pid=-1
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
func record(name,id='a',description=''):
 return {'id':id.repeat(64),'stamp':'100:200','name':name,'product':name,'description':description,'running':false}
func target():return {'handle':'123','target_pid':234,'started':'345','title':'Third party application','app':'ThirdParty'}
func run():
 var router=preload('res://src/core/router.gd').new()
 for phrase in ['включи мой впн','включи впн Orchid','enable vpn Orchid','连接VPN Orchid','найди и включи мой впн','enable my vpn','连接我的VPN','открой кролик контрл и включи звук','打开克罗利克控制并设置声音','in Orchid configure audio','в кролик контрол настрой звук']:
  check(router.route(phrase).get('tool')=='agent.discover','General delegation '+phrase)
 for phrase in ['не включи мой впн','как подключить мой впн?','расскажи о кролик контрол','do not enable my vpn','不要连接我的VPN']:
  check(router.route(phrase).get('tool')!='agent.discover','No delegation from discussion/negative '+phrase)
 var resolver=Resolver.new();var apps=[record('Krolik Control'),record('Orchid','b','network tunnel client'),record('Word','c','document editor')]
 for query in ['кролик контрол','кролик контрл','Krolik Control']:
  var context=resolver.prepare(query,query,apps,1000)
  check(context.direct.get('id')==apps[0].id,'Generic transliteration/edit distance '+query)
 var ambiguous=resolver.prepare('Krolik Control','open app',[apps[0],record('Krolik Control','d')],1000)
 check(ambiguous.direct.is_empty(),'Equal-name ambiguity never direct opens')
 var context=resolver.prepare('','включи мой впн',apps,1000)
 check(context.direct.is_empty() and context.all_map.size()==3,'No brand/category shortcut auto-picks VPN')
 check(resolver.validate('{"app":"a1"}',context,1001).id==apps[1].id,'Bound semantic choice maps only to observed app')
 for raw in ['{"app":"C:/evil.exe"}','{"app":"a1","path":"x"}','{}','not JSON']:
  check(resolver.validate(raw,context,1001).is_empty(),'Unbound model output rejected '+raw)
 check(resolver.validate('{"app":"a1"}',context,122000).is_empty(),'Expired model choice rejected')
 var many=[]
 for i in range(96):many.append(record('Application '+str(i),str(i).sha256_text().left(1),'Different observed purpose '+str(i)+' '+ 'z'.repeat(48)))
 var paged=resolver.prepare('','enable task',many,1000)
 var total=0
 for page in paged.pages:
  total+=page.map.size();check(page.messages[1].content.to_utf8_buffer().size()<3400,'Bounded catalog page fits compact context')
 check(total==96 and paged.all_map.size()==96 and paged.pages.size()>1,'All observed candidates covered; no silent first-page truncation')
 check(resolver.validate('{"app":"a95"}',paged.pages[0],1001).is_empty(),'A page cannot select an app outside its own enum')
 var app=root.get_node('App');app.cancel()
 var old=[app.catalog,app.application_access,app.local_runtime,app.provider,app.provider_name]
 var catalog=Catalog.new();var access=Access.new();var runtime=Runtime.new();var provider=Provider.new()
 for node in [catalog,access,runtime,provider]:app.add_child(node)
 app.catalog=catalog;app.application_access=access;app.local_runtime=runtime;app.provider=provider;app.provider_name='local_worker'
 app.submit('открой кролик контрл и включи звук')
 check(catalog.scans==1 and app.discovery_mode=='scanning','User request starts observed catalog scan')
 app._discovery_completed({'status':'catalog','apps':apps})
 check(catalog.opened.size()==1 and catalog.opened[0].id==apps[0].id and app.discovery_mode=='opening','Observed fuzzy name launches via bound record, not model path')
 app._discovery_completed({'status':'stale'})
 check(app.discovery_mode=='scanning' and catalog.scans==2,'One stale executable triggers fresh catalog, no blind retry')
 app._discovery_completed({'status':'catalog','apps':apps})
 app._discovery_completed({'status':'visible','identity':target(),'name':'Krolik Control'})
 check(access.calls==1 and app.agent.active and app.goal_mode=='observing' and app.agent.goal.contains('включи звук'),'Original free-form goal continues in actual selected window')
 app.cancel();access.target={}
 app.submit('включи мой впн');app._discovery_completed({'status':'catalog','apps':apps})
 check(app.discovery_mode=='thinking' and not provider.requests.is_empty(),'Unknown-purpose app selection uses shared local model')
 app._on_answer('{"app":"a1"}')
 check(app.discovery_mode=='opening' and catalog.opened[-1].id==apps[1].id,'Model bound choice reaches existing native adapter')
 app.cancel();var count=catalog.opened.size();app._discovery_completed({'status':'visible','identity':target(),'name':'Orchid'})
 check(not app.agent.active and catalog.opened.size()==count,'Cancelled discovery cannot start a late agent')
 app.submit('включи мой впн');app._discovery_completed({'status':'catalog','apps':apps});app._on_answer('{"app":"ask"}')
 check(app.discovery_mode.is_empty() and app.discovery_candidates.size()==3 and app.state.current=='idle','Ambiguity offers actual apps without claiming execution')
 app.discovery_at=Time.get_ticks_msec()-31000;check(not app.choose_discovered_app(0) and app.discovery_candidates.is_empty(),'Expired choice revoked')
 app.cancel();app.catalog=old[0];app.application_access=old[1];app.local_runtime=old[2];app.provider=old[3];app.provider_name=old[4]
 for node in [catalog,access,runtime,provider]:node.queue_free()
 # Semantic decisions above are injected fixtures: not evidence of real2B understanding.
 var nodes=[{'id':'1,1','name':'Connect','type':'ControlType.Button','automation_id':'connect','ancestors':[],'enabled':true,'invoke':true},{'id':'1,2','name':'System proxy','type':'ControlType.CheckBox','automation_id':'proxy','ancestors':[],'enabled':true,'toggle':true,'toggle_state':0},{'id':'1,3','name':'Delete profile','type':'ControlType.Button','enabled':true,'invoke':true}]
 var planner=preload('res://src/core/action_proposal.gd').new()
 var plan_context=planner.prepare('включи мой впн',target(),nodes,1000,'ru',true)
 check(plan_context.map.values().any(func(n):return n.name=='Connect' and n.invoke),'Semantic invoke no longer requires literal button label')
 check(not plan_context.map.values().any(func(n):return n.name=='Delete profile'),'Unrequested destructive button excluded')
 check(plan_context.map.values().any(func(n):return n.name=='System proxy' and n.enable),'Generic stateful control available')
 var before=nodes.duplicate(true);var after=nodes.duplicate(true);after[0].id='9,9'
 check(not preload('res://src/core/observed_effect.gd').changed(before,after),'RuntimeID churn is not observed UI-state effect')
 after[0].name='Disconnect'
 check(preload('res://src/core/observed_effect.gd').changed(before,after),'Changed control state observable, not a connection proof')
 var helper=preload('res://src/tools/app_catalog.gd').new();root.add_child(helper)
 var runner=OS.get_environment('COMPANION_PWSH')
 if not runner.is_empty():
  helper.runner=runner;helper.test_runner=true;helper.scan();var result=await helper.completed
  check(result.status=='unsupported','Actual catalog helper Linux nonce roundtrip; no Windows execution')
 helper.queue_free()
 print('DISCOVERY023: %d checks, %d failures; injected semantic fixtures, not real-model/Windows acceptance' %[checks,failures]);quit(0 if failures==0 else 1)
