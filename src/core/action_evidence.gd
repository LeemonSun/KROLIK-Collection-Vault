extends RefCounted
## A verified control state is not a verified business goal. No model judges success.
const Planner=preload("res://src/core/action_proposal.gd")
const Controls=preload("res://src/core/control_context.gd")
static func inspect(plan,identity,nodes,before=[]):
	if not plan.get("ok",false) or not Planner.same_target(plan.get("target",{}),identity):return {"verified":false,"kind":"identity_changed"}
	if not nodes is Array or nodes.is_empty():return {"verified":false,"kind":"missing_observation"}
	var action=plan.get("action","")
	if action=="invoke":
		return {"verified":preload("res://src/core/observed_effect.gd").changed(before,nodes),"kind":"ui_change","goal_verified":false}
	var node=Controls.resolve(plan.get("node",{}),nodes,true)
	if node.is_empty():return {"verified":false,"kind":"ambiguous_or_missing_control"}
	var verified=false;var kind="unsupported"
	if action=="select":verified=node.get("selected",false)==true;kind="selection"
	elif action=="expand":verified=int(node.get("expansion",-1))==1;kind="expansion"
	elif action in ["enable","disable"]:
		verified=int(node.get("toggle_state",-1))==(1 if action=="enable" else 0);kind="toggle_state"
	return {"verified":verified,"kind":kind,"goal_verified":false}
static func receipt_kind(action):
	return {"select":"selection","expand":"expansion","write":"field_readback","enable":"toggle_state","disable":"toggle_state","invoke":"ui_change"}.get(action,"unsupported")
