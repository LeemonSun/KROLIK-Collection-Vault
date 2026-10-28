extends SceneTree
const Agent=preload("res://src/core/adaptive_agent.gd")
const Access=preload("res://src/tools/application_access.gd")
var checks=0
var failures=0
class FakeAccess extends Access:
	var requests=[]
	func _request(payload):operation=payload.operation;requests.append(payload.duplicate(true));return true
class FakeProvider extends Node:
	var calls=[]
	func submit(messages,options):calls.append({"messages":messages.duplicate(true),"options":options.duplicate(true)});return true
	func cancel():pass
class FakeRuntime extends Node:
	var status="ai_ready"
	var generation_busy=false
	func installed():return true
	func touch():pass
	func stop():pass
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func identity():return {"handle":"123","target_pid":234,"started":"345","title":"Unknown settings app","app":"Unfamiliar app"}
func nodes(stage=0):
	var list=[{"id":"10","name":"General","type":"ControlType.TabItem","enabled":true,"select":true,"selected":stage==0},{"id":"20","name":"Appearance","type":"ControlType.TabItem","enabled":true,"select":true,"selected":stage>0},{"id":"99","name":"Delete all data","type":"ControlType.Button","enabled":true,"invoke":true}]
	if stage>0:list.append({"id":"30","name":"Fonts","type":"ControlType.TreeItem","enabled":true,"expand":true,"expansion":1 if stage==2 else 0})
	if stage==2:list.append({"id":"40","name":"Font size","type":"ControlType.Edit","enabled":true,"write":true})
	return list
func alias_for(context,name):
	for alias in context.map:
		if context.map[alias].name==name:return alias
	return ""
func raw(action,alias,text=""):return JSON.stringify({"action":action,"element":alias,"text":text,"append":false})
func observe(access,stage=0):access._finish({"status":"inspected","title":identity().title,"nodes":nodes(stage)})
func run():
	var now=Time.get_ticks_msec();var agent=Agent.new()
	check(agent.begin('Покажи, где увеличить размер шрифта',identity(),now),'Free goal starts without named app instructions')
	var context=agent.prepare(identity(),nodes(),now,now,'ru')
	check(context.ok and not alias_for(context,'Appearance').is_empty(),'Observed navigation control offered to general goal')
	check(alias_for(context,'Delete all data').is_empty(),'Delegation does not expose unrelated destructive invoke')
	var plan=agent.validate(raw('select',alias_for(context,'Appearance')),context,identity(),now)
	check(plan.ok and agent.record(plan,true,identity(),now),'Verified navigation receipt is recorded')
	context=agent.prepare(identity(),nodes(1),now,now,'ru')
	check(context.ok and alias_for(context,'Appearance').is_empty() and not alias_for(context,'Fonts').is_empty(),'Next snapshot changes available actions; completed control not repeated')
	check('verified_steps' in context.messages[1].content and 'observed_state' in context.messages[1].content,'Planner sees receipts and current state, not stale coordinates')
	check(not agent.validate(raw('invoke','e0'),context,identity(),now).ok,'Schema bypass cannot authorize unsupported effect')
	var changed=identity();changed.target_pid=999
	check(not agent.live(changed,now) and not agent.live(identity(),now+Agent.MAX_MS+1),'Changed process and overall time budget invalidate authority')
	var revision=context.agent_revision;agent.clear()
	check(not agent.validate(raw('expand',alias_for(context,'Fonts')),context,identity(),now).ok and revision!=agent.revision,'Old response invalidated after cancel')
	check(not agent.begin('please do not click Delete',identity(),now),'Explicit negative instruction still blocked')
	agent.begin('Tell a joke',identity(),now)
	check(not agent.prepare(identity(),[nodes()[2]],now,now,'en').ok,'Joke cannot expose a destructive button even in delegated mode')
	check(not agent.prepare(identity(),nodes(),now-30001,now,'en').ok,'Stale observation rejected')
	var app=root.get_node('App');app.cancel();app.set_locale('ru')
	var old_access=app.application_access;var old_provider=app.provider;var old_runtime=app.local_runtime;var old_name=app.provider_name
	var access=FakeAccess.new();app.add_child(access);access.target=identity()
	access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed);access.changed.connect(app._access_changed)
	var provider=FakeProvider.new();app.add_child(provider);var runtime=FakeRuntime.new();app.add_child(runtime)
	app.application_access=access;app.provider=provider;app.local_runtime=runtime;app.provider_name='local_worker'
	check(app.begin_agent('Покажи, где увеличить размер шрифта'),'Application begins one delegated goal')
	observe(access)
	check(provider.calls.size()==1 and access.requests.size()==1 and app.goal_mode=='thinking','Fresh observation precedes inference; no effect before approval')
	app._goal_answer(raw('select',alias_for(app.goal_context,'Appearance')))
	check(app.goal_mode=='proposal' and access.requests.size()==1,'Model proposal alone does not click')
	app.confirm_window_goal();observe(access)
	check(access.requests[-1].pattern=='select' and access.requests[-1].element_name=='Appearance','Approval includes fresh identity/capability preflight')
	access._finish({"status":"selected"});observe(access,1)
	check(app.agent.history.size()==1 and app.goal_mode=='between','Selection verified before next planning cycle')
	await create_timer(0.45).timeout
	check(app.goal_mode=='observing' and access.requests[-1].operation=='inspect','Next model step starts with a new inspection')
	observe(access,1)
	check(provider.calls.size()==2 and app.goal_context.goal=='Покажи, где увеличить размер шрифта','Original goal survives replanning without user-authored step list')
	app._goal_answer(raw('expand',alias_for(app.goal_context,'Fonts')))
	app.confirm_window_goal();observe(access,1);access._finish({"status":"expanded"});observe(access,2)
	check(app.agent.history.size()==2,'Second verified effect is recorded independently')
	await create_timer(0.45).timeout;observe(access,2)
	if app.goal_mode=='thinking':app._goal_answer(raw('ask',''))
	check(not app.agent.active and app.goal_mode.is_empty() and app.messages[-1].text.contains('Проверенных шагов: 2.'),'Model stop returns verified receipts, not invented business success')
	check(app.messages[-1].get('ephemeral',false),'Window-derived receipt stays out of saved chat')
	app.begin_agent('Покажи настройки шрифта');observe(access);app._goal_answer(raw('select',alias_for(app.goal_context,'Appearance')))
	app.confirm_window_goal();observe(access);access._finish({"status":"selected"});observe(access,1)
	app.cancel();var count=access.requests.size();await create_timer(0.45).timeout
	check(access.requests.size()==count and not app.agent.active,'Stop revokes deferred next observation')
	app.begin_agent('Покажи настройки шрифта');observe(access);app._goal_answer(raw('select',alias_for(app.goal_context,'Appearance')))
	app.confirm_window_goal();access._finish({"status":"inspected","title":identity().title,"nodes":[nodes()[0]]})
	check(not app.agent.active and access.requests[-1].operation=='inspect','Disappeared control invalidates approval without guessing another target')
	app.begin_agent('Покажи настройки шрифта');observe(access)
	app.set_paused(true);check(not app.agent.active and app.goal_mode.is_empty(),'Pause cancels agent authority');app.set_paused(false)
	app.cancel();app.application_access=old_access;app.provider=old_provider;app.local_runtime=old_runtime;app.provider_name=old_name
	access.queue_free();provider.queue_free();runtime.queue_free()
	print('ADAPTIVE015_TESTS: %d checks, %d failures; actual App loop with synthetic UIA and fake inference' %[checks,failures])
	quit(0 if failures==0 else 1)
