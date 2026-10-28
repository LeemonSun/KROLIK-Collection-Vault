extends SceneTree
const Flow=preload("res://src/core/window_workflow.gd")
const Planner=preload("res://src/core/action_proposal.gd")
const Access=preload("res://src/tools/application_access.gd")
var checks=0
var failures=0
class FakeAccess extends Access:
	var requests=[]
	func _request(payload):operation=payload.operation;requests.append(payload.duplicate(true));return true
class FakeProvider extends Node:
	var calls=0
	func submit(_messages,_options):calls+=1;return true
	func cancel():pass
class FakeRuntime extends Node:
	var status="ai_not_installed"
	var generation_busy=false
	func installed():return false
	func touch():pass
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func target():return {"handle":"123","target_pid":234,"started":"345","title":"Test","app":"Test"}
func nodes(selected=false):return [{"id":"1,1","name":"Insert","enabled":true,"select":true,"selected":selected},{"id":"1,2","name":"Search","enabled":true,"write":true}]
func observe(access,selected=false):access._finish({"status":"inspected","title":"Test","nodes":nodes(selected)})
func _run():
	for raw in ["select Insert → write Search: hello","1. select Insert\n2. write Search: hello","选择 Insert -> 输入 Search: 你好"]:
		check(Flow.parse(raw).get("steps",[]).size()==2,"User-authored sequence parsed without model")
	check(Flow.parse('write Search: "hello → world" → select Insert').get("steps",[]).size()==2,"Quoted delimiter remains data")
	for raw in ["a → b → c → d → e","select Insert → ",'select "Insert',"select Insert → do not click Delete","select Insert → please do not click Delete","select Insert → 请不要点击 Delete"]:
		check(not Flow.parse(raw).get("ok",false),"Oversized, empty, unbalanced or negative sequence rejected")
	check(Flow.parse("select Insert → write Search: do not click Delete").get("ok",false),"Negative words in an explicit text payload stay data")
	var p=Planner.new();var identity=target();var t=Time.get_ticks_msec()
	for raw in ["select Insert","выбери вкладку Insert","选择标签 Insert"]:
		check(p.direct(raw,identity,nodes(),t).get("action")=="select","Literal observed selection needs no model "+raw)
	check(p.direct("write Search: MiXeD 世界",identity,nodes(),t).get("text")=="MiXeD 世界","Fast path preserves exact payload")
	check(not p.prepare("please do not click Delete",identity,[{"id":"1,3","name":"Delete","enabled":true,"invoke":true}],t).get("ok",false),"Polite negative command does not authorize invocation")
	check(not p.direct("selection",identity,nodes(),t).get("ok",false),"Descriptive word is not a selection command")
	check(not p.direct("select Insert",identity,nodes()+[nodes()[0]],t).get("ok",false),"Duplicate names never receive a guessed target")
	check(not p.direct("select Missing",identity,nodes(),t).get("ok",false),"Unknown name is not invented")
	var app=root.get_node("App");var old_access=app.application_access;var old_provider=app.provider;var old_runtime=app.local_runtime;var old_name=app.provider_name
	var access=FakeAccess.new();app.add_child(access);access.target=identity.duplicate(true)
	access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed);access.changed.connect(app._access_changed)
	var provider=FakeProvider.new();app.add_child(provider);var runtime=FakeRuntime.new();app.add_child(runtime)
	app.application_access=access;app.provider=provider;app.local_runtime=runtime;app.provider_name="unconfigured"
	check(app.begin_window_goal("select Insert → write Search: hello"),"Two-step workflow starts without any installed LLM")
	observe(access)
	check(app.goal_mode=="proposal" and app.workflow.index==0 and provider.calls==0,"First literal step is proposed without inference")
	check(access.requests.size()==1,"Proposal has no effects before approval")
	app.confirm_window_goal();observe(access)
	check(access.requests[-1].operation=="invoke" and access.requests[-1].pattern=="select","First approved step uses exact select pattern")
	access._finish({"status":"selected"});observe(access,true)
	check(app.goal_mode=="between" and app.workflow.index==1,"Only verified result advances the sequence")
	await create_timer(0.45).timeout
	check(app.goal_mode=="observing" and access.requests[-1].operation=="inspect","Second step starts with fresh observation")
	observe(access,true)
	check(app.goal_mode=="proposal" and app.goal_plan.text=="hello" and provider.calls==0,"Second step has its own visible proposal")
	app.confirm_window_goal();observe(access,true)
	check(access.requests[-1].operation=="write" and access.requests[-1].text=="hello","Second approval enters only user-authored text")
	access._finish({"status":"written"})
	check(not app.workflow.active and app.goal_mode.is_empty() and app.messages[-1].text==app.t("workflow_done"),"Sequence success follows verified receipts only")
	app.begin_window_goal("select Insert → write Search: hello");observe(access)
	app.confirm_window_goal();observe(access);access._finish({"status":"selected"});observe(access,true)
	app.cancel();var count=access.requests.size();await create_timer(0.45).timeout
	check(access.requests.size()==count and not app.workflow.active,"Cancellation invalidates the pending next-step timer")
	app.begin_window_goal("select Insert → write Search: hello");observe(access)
	app.confirm_window_goal();observe(access);access._finish({"status":"selected"});observe(access,false)
	await create_timer(0.35).timeout;observe(access,false)
	await create_timer(0.7).timeout;observe(access,false)
	check(not app.workflow.active and app.goal_mode.is_empty(),"Unverified selection stops remaining steps")
	app.begin_window_goal("select Insert → write Search: hello");observe(access)
	access.target.started="other";access.changed.emit()
	check(not app.workflow.active and app.goal_mode.is_empty(),"Window identity change cancels the entire workflow")
	app.application_access=old_access;app.provider=old_provider;app.local_runtime=old_runtime;app.provider_name=old_name
	app.cancel();access.queue_free();provider.queue_free();runtime.queue_free()
	print("WORKFLOW_TESTS: %d checks, %d failures; synthetic executor, no Windows UI executed" %[checks,failures])
	quit(0 if failures==0 else 1)
