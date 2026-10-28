extends SceneTree
var checks=0
var failures=0
const Composer=preload('res://src/core/draft_composer.gd')
func _initialize():run.call_deferred()
func check(value,label):
 checks+=1
 if not value:failures+=1;push_error(label)
func run():
 var map={'e0':{'name':'Body','enabled':true,'write':true},'e1':{'name':'Subject','enabled':true,'write':true}}
 var ctx={'draft_allowed':true,'goal':'Compose a short welcome in Body','map':map,'choices':['ask','write:e0','write:e1'],'messages':[{'role':'system','content':'old'},{'role':'user','content':'snapshot'}]}
 check(Composer.unique_field(ctx)=='e0','Explicit unique observed field avoids a model planning roundtrip')
 ctx.goal='Compose a short welcome';check(Composer.unique_field(ctx).is_empty(),'Ambiguous fields need selection, never first-field guess')
 ctx.map=map.duplicate(true);ctx.map.erase('e1');check(Composer.unique_field(ctx)=='e0','Only observed writable field is eligible for reviewed proposal')
 ctx.draft_allowed=false;check(Composer.unique_field(ctx).is_empty(),'Non-composing request cannot gain authoring authority');ctx.draft_allowed=true
 var selection=Composer.selection(ctx)
 check(selection.schema.properties.size()==1 and selection.schema.properties.has('choice'),'Field choice has no generated text slot')
 check(ctx.messages[0].content=='old','Selection does not mutate original context')
 for locale in ['ru','en','zh-Hans']:
  var messages=Composer.messages('Compose a greeting',locale)
  check(messages.size()==2 and messages[1].content=='Compose a greeting','Original goal preserved '+locale)
  check('Do not discuss UI actions' in messages[0].content and not 'old' in messages[0].content,'Authoring does not inherit control labels or planning instructions '+locale)
 check('Body' not in Composer.content_goal('Составь в поле Body приглашение на завтра','Body'),'Russian field reference removed from authoring request')
 check('Body' not in Composer.content_goal('Compose invitation tomorrow in Body.','Body'),'English destination is not mistaken for a meeting location')
 check('Body' not in Composer.content_goal('请写一句邀请明天参加会议的话，填入Body。','Body'),'Chinese destination separated from authored content')
 check(Composer.content_goal('Compose a greeting','Body')=='Compose a greeting','Content with no explicit field phrase unchanged')
 var app=root.get_node('App');var fixture=preload('res://tests/test_adaptive015.gd')
 var old_access=app.application_access;var old_provider=app.provider;var old_runtime=app.local_runtime;var old_name=app.provider_name
 app.cancel();app.set_locale('en')
 var access=fixture.FakeAccess.new();app.add_child(access);access.target={'handle':'1','target_pid':2,'started':'3','title':'Synthetic editor','app':'editor'}
 access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed);access.changed.connect(app._access_changed)
 var provider=fixture.FakeProvider.new();app.add_child(provider);var runtime=fixture.FakeRuntime.new();app.add_child(runtime)
 app.application_access=access;app.provider=provider;app.local_runtime=runtime;app.provider_name='local_worker'
 app.begin_agent('Compose a greeting')
 var nodes=[]
 for alias in map:
  var node=map[alias].duplicate(true);node['id']=alias;nodes.append(node)
 access._finish({'status':'inspected','title':'Synthetic editor','nodes':nodes})
 check(app.goal_mode=='thinking' and provider.calls.size()==1 and provider.calls[0].options.response_schema.properties.size()==1,'Multiple fields first get choice-only model request')
 app._goal_answer(JSON.stringify({'choice':'write:e0'}))
 check(app.goal_mode=='composing' and provider.calls.size()==2 and not provider.calls[1].options.has('response_schema'),'Selected destination then gets separate plain-text generation')
 check(access.requests.size()==1,'Neither generation can write before approval')
 app._on_answer('Welcome, everyone!')
 check(app.goal_mode=='proposal' and app.goal_plan.text=='Welcome, everyone!' and app.goal_plan.node.name=='Body','Plain content becomes a reviewed proposal for selected field')
 app.cancel();check(app.goal_composing_alias.is_empty(),'Cancellation clears authoring destination')
 app.begin_agent('Compose a greeting in Body');access._finish({'status':'inspected','title':'Synthetic editor','nodes':nodes});app._on_answer('Meet at 2 PM')
 check(not app.agent.active and 'absent from your request' in app.messages[-1].text,'Plain-text path retains independent grounding rejection')
 app.begin_agent('Compose a greeting in Body');access._finish({'status':'inspected','title':'Synthetic editor','nodes':nodes});app.cancel();var count=app.messages.size();app._on_answer('late body')
 check(app.messages.size()==count,'Late authoring callback cannot revive cancelled proposal')
 app.application_access=old_access;app.provider=old_provider;app.local_runtime=old_runtime;app.provider_name=old_name
 access.queue_free();provider.queue_free();runtime.queue_free()
 print('COMPOSER017_TESTS: %d checks, %d failures; actual App pipeline, synthetic UIA/provider' %[checks,failures])
 quit(0 if failures==0 else 1)
