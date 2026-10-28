extends "res://src/tools/desktop_actions.gd"
## Explicitly selected external window. No watcher, screenshots, shell or generated code.
signal read_ready(snapshot)
signal snapshot_ready
signal changed
signal notice(key,values)
var windows=[]
var target={}
var nodes=[]
var observed_ms=0
var pending={}
var queued_action={}
var quiet=false
func _init():
	helper_resource="res://native/accessibility_bridge.ps1"
	support_directory="user://support/accessibility"
func _ready():
	completed.connect(_result)
	# Remove abandoned per-request IPC after a crash; never retain window content.
	var folder=DirAccess.open(support_directory+"/jobs")
	if folder:
		for file in folder.get_files():
			if file.ends_with(".json") or file.ends_with(".json.tmp"):folder.remove(file)
func read_content():
	if target.is_empty() or pid>0:return false
	pending={};queued_action={};nodes=[];observed_ms=0
	quiet=true
	return _request(target.merged({"operation":"read","owner_pid":OS.get_process_id()}))
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
func inspect(silent=false):
	if target.is_empty() or pid>0:notice.emit("access_choose",{});return false
	quiet=silent
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
	if status_=="read":
		var snapshot={"blocks":result.get("blocks",[]),"target":target.duplicate(true),"observed_ms":Time.get_ticks_msec(),"partial":true}
		snapshot.target["title"]=str(result.get("title",""))
		# last_result and completion receipts retain no private text.
		result.erase("blocks");result.erase("title")
		quiet=false;read_ready.emit(snapshot);changed.emit();return
	if status_=="windows":
		windows=result.get("windows",[]);notice.emit("access_windows",{} )
	elif status_=="inspected":
		nodes=result.get("nodes",[]);observed_ms=Time.get_ticks_msec()
		if result.get("title") is String:target["title"]=result.title
		if result.get("bounds") is Dictionary:target["bounds"]=result.bounds.duplicate(true)
		if quiet:
			quiet=false;snapshot_ready.emit();changed.emit();return
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
		if not quiet:notice.emit("access_"+status_ if status_ in ["invoked","selected","expanded","written","not_empty","write_unsupported","write_unverified","invoke_unsupported","stale","unsupported"] else "access_failed",{"name":acted_name})
		if status_ in ["invoked","selected","expanded","written","stale"]:nodes=[];observed_ms=0
	quiet=false
	changed.emit()

func adopt(identity):
	if pid>0 or not identity is Dictionary:return false
	for key in ["handle","target_pid","started","title","app"]:
		if not identity.has(key):return false
	target=identity.duplicate(true);nodes=[];pending={};queued_action={};observed_ms=0;windows=[];changed.emit();return true
func cancel_job():
	cancel();pending={};queued_action={};quiet=false;changed.emit()

func _request(payload):
	var accepted=super._request(payload)
	changed.emit();return accepted

func act_id(plan,confirmed=false):
	if pid>0 or not plan.get("ok",false) or not confirmed:return false
	if not preload("res://src/core/action_proposal.gd").same_target(plan.get("target",{}),target):return false
	var matches=[]
	for node in nodes:
		if node.get("id")==plan.node.get("id") and node.get("name")==plan.node.get("name"):matches.append(node)
	if matches.size()!=1:return false
	var node=matches[0]
	if not node.get("enabled",false) or not node.get(plan.action,false):return false
	quiet=true;pending={}
	var payload=target.merged({"operation":"write" if plan.action=="write" else "invoke","pattern":plan.action,"element_id":node.id,"element_name":node.name,"text":plan.text,"append":plan.append,"owner_pid":OS.get_process_id(),"confirmed":true})
	return _request(payload)
