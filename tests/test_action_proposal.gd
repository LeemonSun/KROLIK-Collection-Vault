extends SceneTree
const Planner=preload("res://src/core/action_proposal.gd")
const Access=preload("res://src/tools/application_access.gd")
var checks=0
var failures=0
var answer=""
class FakeAccess extends Access:
	var requests=[]
	func _request(payload):operation=payload.operation;requests.append(payload.duplicate(true));return true
class FakeProvider extends Node:
	var requests=[]
	func submit(messages,options):requests.append({"messages":messages,"options":options});return true
	func cancel():pass
class FakeRuntime extends Node:
	var status="ai_ready"
	var generation_busy=false
	var manifest={}
	func installed():return true
	func touch():pass
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _nodes():return [{"id":"1,1","name":"Home","type":"ControlType.TabItem","enabled":true,"select":true,"selected":true},{"id":"1,2","name":"Insert","type":"ControlType.TabItem","enabled":true,"select":true,"selected":false},{"id":"1,3","name":"Search","type":"ControlType.Edit","enabled":true,"write":true},{"id":"1,4","name":"Delete","type":"ControlType.Button","enabled":true,"invoke":true}]
func _target():return {"handle":"123","target_pid":234,"started":"345","title":"Demo","app":"Editor"}
func _raw(alias,action="select",text=""):return JSON.stringify({"action":action,"element":alias,"text":text,"append":false})
func _run():
	var planner=Planner.new();var target=_target();var context=planner.prepare("select Insert",target,_nodes(),1000)
	var alias=""
	for key in context.map:
		if context.map[key].name=="Insert":alias=key
	check(context.ok and not alias.is_empty(),"Observed controls map to bounded opaque aliases")
	check(planner.validate(_raw(alias),context,target,1001).get("ok"),"Valid observed action accepted as proposal")
	for raw in ['not JSON','{"command":"shell.exec"}',_raw("unknown"),_raw(alias,"done"),_raw(alias,"write","invented"),JSON.stringify({"action":"select","element":alias,"text":"","append":false,"shell":"calc"})]:
		check(not planner.validate(raw,context,target,1001).get("ok",false),"Malformed, invented or unsupported instruction rejected")
	check(not planner.validate(_raw(alias),context,target,1000+Planner.TTL_MS+1).get("ok",false),"Stale model observation rejected")
	var changed=target.duplicate();changed.started="different"
	check(not planner.validate(_raw(alias),context,changed,1001).get("ok",false),"PID reuse does not retain action authority")
	check(not planner.prepare("Tell me a joke",target,_nodes(),1000).get("ok",false),"Unrelated goals never reach model action generation")
	check(not planner.prepare("do not click Delete",target,_nodes(),1000).get("ok",false),"Negated goals do not authorize actions")
	var safe_context=planner.prepare("select Insert",target,_nodes(),1000)
	check(not safe_context.map.values().any(func(n):return n.get("invoke",false)),"Model cannot invoke a button not explicitly named in a click instruction")
	var writer=planner.prepare("write hello into Search",target,_nodes(),1000)
	var write_alias=""
	for key in writer.map:
		if writer.map[key].name=="Search":write_alias=key
	check(planner.validate(_raw(write_alias,"write","hello"),writer,target,1001).get("ok",false),"Only verbatim user-authored text can be proposed")
	check(not planner.validate(_raw(write_alias,"write","goodbye"),writer,target,1001).get("ok",false),"Invented field contents rejected")
	for phrase in ["переключись на вкладку Insert","найди кнопку поиска","switch to the Insert tab","选择插入标签"]:
		check(Planner.contextual_goal(phrase),"Pinned-window UI intent recognized without developer syntax")
	for phrase in ["привет","не нажимай кнопку","найди в интернете информацию про вкладки","open notepad","на какой мы планете"]:
		check(not Planner.contextual_goal(phrase),"Conversation/global app/web intent stays outside window actions")
	var router=preload("res://src/core/router.gd").new()
	for text in ["в этом окне: найди вкладку вставки","In this window: select Insert","在此窗口：选择插入"]:
		check(router.route(text).get("tool")=="access.goal","Explicit scoped goal routing: "+text)
	check(router.route("не в этом окне нажми кнопку").kind=="chat","Negated/discussed goal is not an action")
	var app=root.get_node("App");var original_access=app.application_access;var original_provider=app.provider;var original_runtime=app.local_runtime;var original_name=app.provider_name
	var access=FakeAccess.new();app.add_child(access);access.target=target.duplicate(true)
	access.snapshot_ready.connect(app._goal_observed);access.completed.connect(app._goal_access_completed)
	var provider=FakeProvider.new();app.add_child(provider)
	var runtime=FakeRuntime.new();app.add_child(runtime)
	app.application_access=access;app.provider=provider;app.provider_name="local_worker";app.local_runtime=runtime
	var original_turns=app.session_turns.duplicate(true)
	check(app.begin_window_goal("select Insert"),"Real app goal controller starts a fresh observation")
	access._finish({"status":"inspected","nodes":_nodes(),"title":"Demo"})
	check(app.goal_mode=="thinking" and provider.requests.size()==1,"Observation passes to one constrained model request")
	for key in app.goal_context.map:
		if app.goal_context.map[key].name=="Insert":alias=key
	app._on_answer(_raw(alias))
	check(app.goal_mode=="proposal" and access.requests.size()==1,"Model reply alone cannot execute an effect")
	check(app.confirm_window_goal() and access.requests[-1].operation=="inspect","Approval re-observes before execution")
	access._finish({"status":"inspected","nodes":_nodes(),"title":"Demo"})
	check(access.requests[-1].operation=="invoke" and access.requests[-1].pattern=="select","Fresh exact element and pattern executed only after approval")
	access._finish({"status":"selected"})
	check(app.goal_mode=="verifying" and access.requests[-1].operation=="inspect","Selection gets an actual post-observation")
	var after=_nodes();after[1].selected=true
	access._finish({"status":"inspected","nodes":after,"title":"Demo"})
	check(app.goal_mode.is_empty() and app.messages[-1].text==app.t("goal_verified_select",{"name":"Insert"}),"Success requires selected state in the fresh observation")
	check(app.goal_context.is_empty() and app.goal_plan.is_empty() and app.session_turns==original_turns,"Private UI context never enters dialogue memory")
	app.begin_window_goal("select Insert");access._finish({"status":"inspected","nodes":_nodes(),"title":"Demo"})
	for key in app.goal_context.map:
		if app.goal_context.map[key].name=="Insert":alias=key
	app._on_answer(_raw(alias));app.cancel()
	var count=access.requests.size()
	check(not app.confirm_window_goal() and access.requests.size()==count,"Cancelled proposal never replays later")
	app.application_access=original_access;app.provider=original_provider;app.provider_name=original_name;app.local_runtime=original_runtime
	access.queue_free();provider.queue_free();runtime.queue_free()
	var fixture=OS.get_environment("COMPANION_GOAL_FIXTURE")
	if not fixture.is_empty():await _actual_model(fixture)
	print("ACTION_PROPOSAL_TESTS: %d checks, %d failures; real_model=%s; Windows UI not executed" %[checks,failures,not fixture.is_empty()])
	quit(0 if failures==0 else 1)
func _actual_model(path):
	var runtime=preload("res://src/runtime/local_runtime.gd").new();runtime.base_path=path;runtime.manifest=JSON.parse_string(FileAccess.get_file_as_string(path.path_join("fixture.json")))
	root.add_child(runtime);check(runtime.start({"cpu_threads":2,"context_tokens":2048}),"Actual owned compact-model worker starts")
	var deadline=Time.get_ticks_msec()+60000
	while runtime.status=="ai_starting" and Time.get_ticks_msec()<deadline:await process_frame
	check(runtime.status=="ai_ready","Authenticated local planner ready")
	var provider=preload("res://src/providers/llama_http_provider.gd").new();root.add_child(provider);provider.configure_local(runtime.port,runtime.token)
	provider.completed.connect(func(text):answer=text);provider.failed.connect(func(key):answer="ERROR:"+key)
	var planner=Planner.new()
	for spec in [["ru","Переключись на вкладку Insert","select","Insert"],["en","Write hello into the Search field","write","Search"],["zh-Hans","切换到Insert标签","select","Insert"],["en","Tell me a joke","ask",""]]:
		var context=planner.prepare(spec[1],_target(),_nodes(),Time.get_ticks_msec(),spec[0]);answer=""
		if spec[2]=="ask":
			check(not context.get("ok",false),"Unrelated request rejected before model or executor")
			continue
		runtime.generation_busy=true;runtime.touch()
		provider.submit(context.messages,{"max_tokens":256,"context_tokens":2048,"response_schema":context.schema})
		deadline=Time.get_ticks_msec()+60000
		while answer.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		var proposed=planner.validate(answer,context,_target(),Time.get_ticks_msec())
		check(proposed.get("ok",false) and proposed.get("action")==spec[2] and (spec[2]=="ask" or proposed.get("node",{}).get("name")==spec[3]),"Actual model chooses grounded step "+spec[0]+": "+answer)
		if spec[2]=="write":check(proposed.get("text")=="hello","Actual model preserves exact requested text")
		check(provider.request_messages.is_empty(),"Adapter clears observed UI after response")
		print("REAL_GOAL ",JSON.stringify({"locale":spec[0],"input":spec[1],"output":answer,"elapsed_ms":provider.last_usage.get("elapsed_ms",0),"valid":proposed.get("ok",false)}))
	runtime.stop();provider.queue_free();runtime.queue_free()
