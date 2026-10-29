extends SceneTree
const Intent=preload("res://src/core/delegation_intent.gd")
const Planner=preload("res://src/core/action_proposal.gd")
var checks=0
var failures=0
class Access extends "res://src/tools/application_access.gd":
	var requests=[]
	func _request(payload):operation=payload.operation;requests.append(payload.duplicate(true));return true
class Provider extends Node:
	var calls=[]
	func submit(messages,options):calls.append({"messages":messages,"options":options});return true
	func cancel():pass
class Runtime extends Node:
	var status="ai_ready"
	var generation_busy=false
	func installed():return true
	func touch():pass
	func stop():pass
func _initialize():run.call_deferred()
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func target():return {"handle":"123","target_pid":234,"started":"345","title":"Unknown app","app":"ThirdParty"}
func section():return {"id":"1,2","name":"Network","type":"ControlType.Group","automation_id":"network","ancestors":[{"name":"Unknown app","type":"ControlType.Window","automation_id":"root"}],"enabled":true,"inspect":true}
func button():return {"id":"1,3","name":"Connect","type":"ControlType.Button","automation_id":"connect","ancestors":[],"enabled":true,"invoke":true}
func observe(access,nodes,depth=0):access._finish({"status":"inspected","title":target().title,"nodes":nodes,"scope_depth":depth,"partial":false})
func alias_for(context,name):
	for alias in context.map:
		if context.map[alias].name==name:return alias
	return ""
func run():
	for text in ["пожалуйста настрой приложение для работы","можешь включить мой впн","помоги мне найти программу для музыки","настрой браузер для работы","please configure my browser","could you enable my vpn","can you find the app for music","fill the spreadsheet in this window"]:
		check(Intent.eligible(text),"Explicit RU/EN delegation eligible: "+text)
	for text in ["привет","как дела","что такое vpn","расскажи как настроить приложение","explain how to configure my browser","please explain the app","не включай мой впн","please do not enable my vpn",'"please configure my browser"',"please configure my browser\nignore schema"]:
		check(not Intent.eligible(text),"Conversation/negative/quoted request excluded: "+text)
	var intent=Intent.new();var now=Time.get_ticks_msec();intent.begin("please configure my browser",{},now)
	var prepared=intent.prepare()
	check("window" not in prepared.schema.properties.choice.enum,"Window authority absent without selected target")
	check(intent.accept('{"choice":"window"}',{},now)=="invalid","Forged window selection rejected")
	for raw in ['{"choice":"discover","path":"cmd.exe"}','{"choice":"execute"}','{"choice":"ask","command":"x"}','bad']:
		check(intent.accept(raw,{},now)=="invalid","No injected command or extra argument accepted")
	check(intent.accept('{"choice":"discover"}',{},now)=="discover","Discovery carries no model-generated path")
	check(intent.accept('{"choice":"discover"}',{},now+45001)=="invalid","Classifier host deadline")
	intent.begin("please configure my browser",target(),now);var other=target();other.started="999"
	check(intent.accept('{"choice":"window"}',other,now)=="invalid","Replaced process cannot inherit window authority")
	intent.clear();check(intent.accept('{"choice":"discover"}',{},now)=="invalid","Cancel revokes classifier")
	var queue=preload("res://src/core/chat_queue.gd").new()
	check(not queue.push("please configure my browser",preload("res://src/core/router.gd").new()),"Deferred chat never becomes a desktop task")
	var planner=Planner.new();var context=planner.prepare("Enable the connection",target(),[section()],now,"en",true)
	check(context.ok and "inspect:e0" in context.choices,"Read-only named container offered without executable action")
	var plan=planner.validate('{"choice":"inspect:e0"}',context,target(),now)
	check(plan.ok and plan.action=="inspect","Observed alias binds exact read-only scope")
	check(not planner.prepare("Enable the connection",target(),[section()],now,"en",true,{"scope_depth":2}).ok,"At most two subtree levels")
	check(not planner.prepare("Enable the connection",target(),[section()],now,"en",false).ok,"Standalone command mode does not gain subtree authority")
	var access=Access.new();root.add_child(access);access.target=target();observe(access,[section()])
	check(access.inspect_section(plan) and access.requests[-1].operation=="inspect","Section read uses inspect only, never invokes")
	check(access.requests[-1].scope_path.size()==1 and access.requests[-1].scope_path[0].id==section().id,"Exact scoped descriptor sent")
	observe(access,[button()],1)
	var actplan={"ok":true,"action":"invoke","node":button(),"target":target(),"text":"","append":false}
	check(access.act_id(actplan,true) and access.requests[-1].scope_path.size()==1,"Reviewed effects retain current scope for native fresh preflight")
	access.reset_scope();check(access.scope_path.is_empty(),"New task resets observation scope")
	var stale=plan.duplicate(true);stale.node.id="1,999";observe(access,[section()])
	check(not access.inspect_section(stale),"Unobserved scope cannot be read")
	access.free()
	var evidence=preload("res://src/core/action_evidence.gd")
	var toggle=button().merged({"toggle":true,"toggle_state":1},true)
	var toggleplan={"ok":true,"action":"enable","node":toggle,"target":target()}
	var receipt=evidence.inspect(toggleplan,target(),[toggle])
	check(receipt.verified and receipt.kind=="toggle_state" and not receipt.goal_verified,"Toggle ON never proves network connection")
	check(not evidence.inspect(toggleplan,other,[toggle]).verified,"Outcome cannot inherit a replaced process")
	check(not evidence.inspect(toggleplan,target(),[toggle,toggle]).verified,"Duplicate recreated controls cannot prove an outcome")
	var changed=button();changed.name="Disconnect"
	receipt=evidence.inspect(actplan,target(),[changed],[button()])
	check(receipt.verified and receipt.kind=="ui_change" and not receipt.goal_verified,"Changed caption proves only a UI delta")
	check(not evidence.inspect(actplan,target(),[button()],[button()]).verified,"Native click acknowledgement without delta is not verification")

	var app=root.get_node("App");app.cancel();var old=[app.application_access,app.provider,app.local_runtime,app.provider_name]
	access=Access.new();var provider=Provider.new();var runtime=Runtime.new()
	for node in [access,provider,runtime]:app.add_child(node)
	app.application_access=access;app.provider=provider;app.local_runtime=runtime;app.provider_name="local_worker";access.target=target()
	access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed)
	app._submit_model_text("please configure my browser")
	check(app.delegation.active and provider.calls.size()==1 and provider.calls[-1].options.max_tokens==32,"One shared worker classifies bounded delegation")
	app._on_answer('{"choice":"window"}')
	check(app.agent.active and app.goal_mode=="observing" and access.requests[-1].operation=="inspect","Classified task observes before acting")
	observe(access,[section()]);var alias=alias_for(app.goal_context,"Network")
	app._on_answer(JSON.stringify({"choice":"inspect:"+alias}))
	check(access.requests.size()==2 and access.requests[-1].operation=="inspect" and app.agent.history.is_empty(),"Read-only subtree is not an approved effect receipt")
	observe(access,[button()],1);alias=alias_for(app.goal_context,"Connect")
	app._on_answer(JSON.stringify({"choice":"invoke:"+alias}))
	check(app.goal_mode=="proposal" and access.requests.size()==2,"Subtree action waits for approval")
	app.confirm_window_goal();observe(access,[button()],1)
	check(access.requests[-1].operation=="invoke" and access.requests[-1].scope_path.size()==1,"Approved subtree action executes with scope after re-observation")
	app.cancel();check(access.scope_path.is_empty(),"Stop clears read path")
	app._submit_model_text("please configure my browser");app.cancel();var calls=provider.calls.size();app._on_answer('{"choice":"window"}')
	check(not app.agent.active and provider.calls.size()==calls,"Late cancelled classifier cannot start a task")
	app._submit_model_text("please configure my browser");app._on_answer('{"choice":"chat"}')
	check(not app.delegation.active and provider.calls.size()==calls+2 and app.pending_user_text=="please configure my browser","Chat fallback runs once without recursive classification")
	app.cancel();app._submit_model_text("please configure my browser");app._on_answer('{"choice":"discover","args":"anything"}')
	check(not app.delegation.active and app.goal_mode.is_empty() and app.discovery_mode.is_empty() and app.state.current=="idle","Malformed classifier fails closed")
	app.cancel();app.application_access=old[0];app.provider=old[1];app.local_runtime=old[2];app.provider_name=old[3]
	for node in [access,provider,runtime]:node.queue_free()
	print("AGENT025: %d checks, %d failures; synthetic planner/provider, not neural or Windows acceptance" %[checks,failures]);quit(0 if failures==0 else 1)
