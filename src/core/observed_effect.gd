extends RefCounted
## UI-state delta only, never business-goal verification.
static func fingerprint(nodes):
	var records=[]
	for node in nodes.slice(0,90):
		if not node is Dictionary:continue
		records.append(JSON.stringify({"name":node.get("name",""),"scope":preload("res://src/core/control_context.gd").descriptor(node),"selected":node.get("selected",false),"expanded":node.get("expansion",-1),"toggle":node.get("toggle_state",-1)}))
	records.sort()
	return JSON.stringify(records)
static func changed(before,after):
	return not before.is_empty() and not after.is_empty() and fingerprint(before)!=fingerprint(after)
