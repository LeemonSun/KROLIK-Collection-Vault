extends SceneTree
const Planner=preload('res://src/core/action_proposal.gd')
const Draft=preload('res://src/core/draft_policy.gd')
var checks=0
var failures=0
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func target():return {'handle':'12','target_pid':34,'started':'56','title':'Unfamiliar editor','app':'editor'}
func nodes():return [{'id':'1','name':'Body','type':'ControlType.Edit','enabled':true,'write':true},{'id':'2','name':'Send','type':'ControlType.Button','enabled':true,'invoke':true}]
func raw(text,element='e0',action='write'):return JSON.stringify({'action':action,'element':element,'text':text,'append':false})
func run():
	var now=Time.get_ticks_msec();var planner=Planner.new()
	for goal in ['Напиши короткое приветствие в поле Body','Составь письмо о встрече','Compose a greeting in Body','Please draft a short invitation','请写一条问候语','撰写简短邀请']:
		var context=planner.prepare(goal,target(),nodes(),now,'en',true)
		check(context.ok and context.draft_allowed,'Explicit compose goal permits a reviewed draft '+goal)
		var plan=planner.validate(raw('Hello, welcome to our meeting.'),context,target(),now)
		check(plan.ok and plan.generated and plan.text=='Hello, welcome to our meeting.','Draft need not appear verbatim in goal '+goal)
	for goal in ['найди вкладку Compose','выбери Напиши','write Body: hello','впиши Body: привет','输入 Body: 你好','click Send']:
		check(not Draft.requested(goal),'Ordinary navigation/literal input not promoted to authoring '+goal)
	var context=planner.prepare('write Body: hello',target(),nodes(),now,'en',true)
	check(not context.draft_allowed and not planner.validate(raw('invented text'),context,target(),now).ok,'Literal mode still rejects invented input')
	context=planner.prepare('Compose a greeting; click Send',target(),nodes(),now,'en',true)
	check(context.ok and context.map.size()==1 and not context.map.e0.get('invoke',false),'Draft mode offers no Send effect, even when goal mentions it')
	check(not planner.validate(raw('','e1','invoke'),context,target(),now).ok,'Invented alias cannot bypass no-send draft boundary')
	check(not planner.validate(raw('x'.repeat(513)),context,target(),now).ok,'Draft has bounded512character budget')
	check(not planner.validate(raw('bad'+String.chr(1)),context,target(),now).ok,'Control characters rejected')
	check(not planner.validate(raw('hello'),context,target(),now+90001).ok,'Expired draft rejected')
	var changed=target();changed.started='different'
	check(not planner.validate(raw('hello'),context,changed,now).ok,'Process restart invalidates draft')
	check(not planner.prepare('Compose a greeting',target(),nodes(),now,'en').get('draft_allowed',false),'Legacy one-step default does not gain new authority')
	var agent=preload('res://src/core/adaptive_agent.gd').new();agent.begin('Compose a short greeting',target(),now)
	context=agent.prepare(target(),nodes(),now,now,'en')
	var plan=agent.validate(raw('Welcome, everyone!'),context,target(),now)
	check(plan.ok and plan.generated,'Actual agent carries explicit drafting permission')
	check(agent.record(plan,true,target(),now),'Verified draft write records receipt')
	check(not agent.prepare(target(),nodes(),now,now,'en').ok,'Written field cannot be repeated by next planning cycle')
	check(not JSON.stringify(agent.history).contains('Welcome'),'Receipt does not retain generated private body')
	var nav=planner.prepare('Find the font size',target(),[{'id':'1','name':'Fonts','enabled':true,'expand':true}],now,'en',true)
	check(nav.schema.properties.size()==1 and nav.schema.properties.choice.enum==['ask','expand:e0'],'Navigation schema binds action+element, with no unused fields')
	check(planner.validate(JSON.stringify({'choice':'expand:e0'}),nav,target(),now).get('ok',false),'Compact grammar reply validates')
	check(not planner.validate(JSON.stringify({'choice':'select:e0'}),nav,target(),now).get('ok',false),'Unsupported pair cannot bypass schema')
	check(not planner.validate(JSON.stringify({'choice':'expand:e0','text':'hidden','append':false}),nav,target(),now).get('ok',false),'Navigation cannot smuggle text')
	check(not planner.validate(JSON.stringify({'choice':'expand:e0','extra':1}),nav,target(),now).get('ok',false),'Compact shape cannot add executable fields')
	check(not Draft.grounded_details('Meet tomorrow at 2 PM','Compose an invitation for tomorrow'),'Invented meeting time blocked independently of model')
	check(Draft.grounded_details('Meet at 14:30','Compose an invitation for 14:30'),'Explicit numeric detail retained')
	check(not Draft.grounded_details('Visit https://invented.example','Compose an invitation'),'Invented URL blocked')
	check(not Draft.grounded_details('Mail alice@example.com','Compose an invitation'),'Invented email blocked')
	var ungrounded=planner.validate(raw('Meet tomorrow at 2 PM'),context,target(),now)
	check(not ungrounded.get('ok',false) and ungrounded.get('reason')=='draft_unprovided_detail','Ungrounded details cannot reach draft approval')
	var app=root.get_node('App');app.cancel();app.set_locale('en')
	var old_access=app.application_access;var old_provider=app.provider;var old_runtime=app.local_runtime;var old_name=app.provider_name
	var fixture=preload('res://tests/test_adaptive015.gd')
	var access=fixture.FakeAccess.new();app.add_child(access);access.target=target()
	access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed);access.changed.connect(app._access_changed)
	var provider=fixture.FakeProvider.new();app.add_child(provider);var runtime=fixture.FakeRuntime.new();app.add_child(runtime)
	app.application_access=access;app.provider=provider;app.local_runtime=runtime;app.provider_name='local_worker'
	check(app.begin_agent('Compose a friendly greeting for the Body field'),'Application accepts explicit composing goal')
	access._finish({'status':'inspected','title':target().title,'nodes':nodes()})
	check(provider.calls[-1].options.max_tokens==256 and not provider.calls[-1].options.has('response_schema'),'Plain authoring has bounded output without action JSON')
	app._goal_answer('Welcome to the meeting!')
	check(app.goal_mode=='proposal' and app.goal_plan.generated and access.requests.size()==1,'Generated draft cannot write before approval')
	check('Welcome to the meeting!' in app.messages[-1].text and 'Nothing has been entered' in app.messages[-1].text,'Complete generated draft explicitly presented as unexecuted')
	app.confirm_window_goal();access._finish({'status':'inspected','title':target().title,'nodes':nodes()})
	check(access.requests[-1].operation=='write' and access.requests[-1].text=='Welcome to the meeting!' and access.requests[-1].confirmed,'Only reviewed draft reaches native write after fresh preflight')
	access._finish({'status':'written'})
	check(app.agent.history.size()==1,'Native verified write receipt recorded')
	app.cancel();var count=access.requests.size();await create_timer(0.45).timeout
	check(count==access.requests.size() and not app.agent.active,'Cancel revokes next draft continuation')
	app.application_access=old_access;app.provider=old_provider;app.local_runtime=old_runtime;app.provider_name=old_name
	access.queue_free();provider.queue_free();runtime.queue_free()
	print('DRAFT016_TESTS: %d checks, %d failures; actual planner/agent policy, no Windows effects' %[checks,failures])
	quit(0 if failures==0 else 1)
