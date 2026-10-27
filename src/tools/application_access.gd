extends "res://src/tools/desktop_actions.gd"
## Explicitly selected external window. No watcher, screenshots, shell or generated code.
signal changed
signal notice(key,values)
var windows=[]
var target={}
var nodes=[]
var observed_ms=0
var pending={}
var queued_action={}
func _init():
	helper_resource="res://native/accessibility_bridge.ps1"
	support_directory="user://support/accessibility"
func _ready():completed.connect(_result)
func list_windows():
	if pid>0:return false
	windows=[];pending={};queued_action={};changed.emit()
	return _request({"operation":"windows","owner_pid":OS.get_process_id()})
func bind(index):
	if index<0 or index>=windows.size() or pid>0:return false
	target=windows[index].duplicate(true);nodes=[];pending={};queued_action={};observed_ms=0;windows=[]
	changed.emit();return inspect()
func clear_target():
	cancel();windows=[];target={};nodes=[];pending={};queued_action={};observed_ms=0;changed.emit()
func inspect():
	if target.is_empty() or pid>0:notice.emit("access_choose",{});return false
	return _request(target.merged({"operation":"inspect","owner_pid":OS.get_process_id()}))
func act(kind,name,text="",append=false):
	pending={}
	if pid>0:notice.emit("busy_message",{});return false
	if target.is_empty():notice.emit("access_choose",{});return false
	if Time.get_ticks_msec()-observed_ms>30000 or nodes.is_empty():
		queued_action={"kind":kind,"name":name,"text":text,"append":append};return inspect()
	var matches=[]
	for node in nodes:
		if str(node.get("name","")).to_lower()==name.strip_edges().to_lower():matches.append(node)
	if matches.size()!=1:notice.emit("access_ambiguous",{"name":name});return false
	var node=matches[0]
	if kind not in ["invoke","write"] or not node.get("enabled",false):notice.emit("access_unavailable",{});return false
	var payload=target.merged({"operation":kind,"element_id":node.id,"element_name":node.name,"text":text.left(2000),"append":append,"owner_pid":OS.get_process_id()})
	pending=payload.duplicate(true)
	return _request(payload)
func confirm():
	if pending.is_empty() or pid>0:return false
	if Time.get_ticks_msec()-observed_ms>30000:
		pending={};notice.emit("access_stale",{});changed.emit();return false
	var payload=pending.duplicate(true);pending={};payload["confirmed"]=true
	return _request(payload)
func _result(result):
	var status_=str(result.get("status","failed"))
	if status_!="inspected":queued_action={}
	if status_=="windows":
		windows=result.get("windows",[]);notice.emit("access_windows",{} )
	elif status_=="inspected":
		nodes=result.get("nodes",[]);observed_ms=Time.get_ticks_msec()
		if not queued_action.is_empty():
			var action=queued_action;queued_action={}
			if nodes.is_empty():notice.emit("access_unavailable",{});changed.emit();return
			act(action.kind,action.name,action.text,action.append);changed.emit();return
		var lines=PackedStringArray()
		for node in nodes:
			if not str(node.get("name","")).is_empty():lines.append(str(node.name)+(" · ✎" if node.get("write",false) else ""))
		notice.emit("access_observed",{"title":target.get("title",""),"items":"\n".join(lines).left(6000)})
	elif status_=="confirmation_required":notice.emit("access_confirmation",{"name":pending.get("element_name","")})
	else:
		var acted_name=str(pending.get("element_name",""))
		pending={}
		notice.emit("access_"+status_ if status_ in ["invoked","selected","expanded","written","not_empty","write_unsupported","write_unverified","invoke_unsupported","stale","unsupported"] else "access_failed",{"name":acted_name})
		if status_ in ["invoked","selected","expanded","written","stale"]:nodes=[];observed_ms=0
	changed.emit()

func adopt(identity):
	if pid>0 or not identity is Dictionary:return false
	for key in ["handle","target_pid","started","title","app"]:
		if not identity.has(key):return false
	target=identity.duplicate(true);nodes=[];pending={};queued_action={};observed_ms=0;windows=[];changed.emit();return true
func cancel_job():
	cancel();pending={};queued_action={};changed.emit()

func _request(payload):
	var accepted=super._request(payload)
	changed.emit();return accepted
