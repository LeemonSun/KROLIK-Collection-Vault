extends RefCounted
## Read-only UI model. Labels/animation never grant authority or infer task success.
static func snapshot(app):
	var kind="";var detail="";var identity="";var token="";var choices=[]
	if app.goal_mode=="proposal":
		kind="review";token=JSON.stringify(app.goal_plan)
		var name=str(app.goal_plan.get("node",{}).get("name",""))
		identity=str(app.goal_plan.get("target",{}).get("title",""))
		var action="draft" if app.goal_plan.get("generated",false) else ("append" if app.goal_plan.get("append",false) and app.goal_plan.get("action")=="write" else str(app.goal_plan.get("action","select")))
		detail=app.t("orbit_review_"+action,{"name":name})
		var scope=preload("res://src/core/control_context.gd").label(app.goal_plan.get("node",{}))
		if not scope.is_empty():detail+="\n"+scope
		if app.goal_plan.get("action")=="write":detail+="\n\n"+str(app.goal_plan.get("text",""))
	elif not app.discovery_candidates.is_empty() or not app.browser_tabs.candidates.is_empty():
		kind="choice";choices=(app.discovery_candidates if not app.discovery_candidates.is_empty() else app.browser_tabs.candidates).duplicate(true);token=JSON.stringify(choices)
		detail=app.t("orbit_choose_app" if not app.discovery_candidates.is_empty() else "orbit_choose_tab")
	elif not app.goal_mode.is_empty():kind="observe" if app.goal_mode in ["observing","verifying","verify_wait"] else ("work" if app.goal_mode in ["executing","confirming"] else "think")
	elif not app.discovery_mode.is_empty():kind="find"
	elif not app.window_read_mode.is_empty():kind="observe"
	elif app.public_page.busy:kind="read"
	elif app.state.current=="executing" and (app.browser_tabs.pid>0 or app.vpn_connection.pid>0 or not app.launch_goal.is_empty() or not app.launch_vpn.is_empty()):kind="work"
	if kind.is_empty():return {}
	if detail.is_empty():detail=app.t("orbit_detail_"+kind)
	return {"kind":kind,"heading":app.t("orbit_task_"+kind),"detail":detail,"identity":identity,"token":token,"choices":choices}
static func review_live(app,token):
	return not app.paused and app.goal_mode=="proposal" and not token.is_empty() and token==JSON.stringify(app.goal_plan) and Time.get_ticks_msec()<=app.goal_deadline_ms
static func choice_live(app,token):
	var items=app.discovery_candidates if not app.discovery_candidates.is_empty() else app.browser_tabs.candidates
	return not app.paused and not items.is_empty() and token==JSON.stringify(items)
