extends "res://src/tools/desktop_actions.gd"
## Transient browser chrome only. No browser profiles, cookies, page DOM or model.
var candidates=[]
var query=""
var observed_ms=0
func _init():
	helper_resource="res://native/accessibility_bridge.ps1"
	support_directory="user://support/tabs"
func find_tabs(text):
	candidates=[];query=text;observed_ms=0
	return _request({"operation":"tabs","owner_pid":OS.get_process_id()})
func matches(result):
	candidates=[]
	var key=preload("res://src/core/desktop_task_intent.gd").tab_key(query)
	for item in result.get("tabs",[]):
		if not item is Dictionary or not item.get("node") is Dictionary or not item.get("identity") is Dictionary:continue
		if key in preload("res://src/core/desktop_task_intent.gd").tab_key(item.node.get("name","")):
			candidates.append(item.duplicate(true))
	observed_ms=Time.get_ticks_msec()
	return candidates
func choose(index):
	if pid>0 or observed_ms<=0 or Time.get_ticks_msec()-observed_ms>30000 or index<0 or index>=candidates.size():return false
	var item=candidates[index];var node=item.node
	candidates=[];observed_ms=0
	return _request(item.identity.merged({"operation":"tab_select","owner_pid":OS.get_process_id(),"element_id":node.id,"element_name":node.name,"element_descriptor":node}))
func forget():
	cancel();candidates=[];query="";observed_ms=0
