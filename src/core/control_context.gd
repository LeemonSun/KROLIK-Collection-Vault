extends RefCounted
## Observation context, not an authority token. Labels never become instructions.
static func descriptor(node):
	var ancestors=[]
	if node.get("ancestors",[]) is Array:
		for parent in node.get("ancestors",[]).slice(-3):
			if not parent is Dictionary:continue
			ancestors.append({"name":str(parent.get("name","")).left(64),"type":str(parent.get("type","")).left(48),"automation_id":str(parent.get("automation_id","")).left(64)})
	return {"type":str(node.get("type","")).left(48),"automation_id":str(node.get("automation_id","")).left(64),"ancestors":ancestors}

static func exact(a,b):
	# Runtime IDs are opaque and insufficient alone; compare current scope as well.
	return str(a.get("id",""))!="" and str(a.get("id",""))==str(b.get("id","")) and str(a.get("name",""))==str(b.get("name","")) and descriptor(a)==descriptor(b)

static func stable(a,b):
	var da=descriptor(a);var db=descriptor(b)
	if da!=db or da.automation_id.is_empty() or da.ancestors.is_empty():return false
	if str(a.get("name",""))!=str(b.get("name","")):return false
	# AutomationId is not globally unique. Require an informative ancestor scope.
	return da.ancestors.any(func(p):return not p.name.is_empty() or not p.automation_id.is_empty())

static func same(a,b):
	return exact(a,b) or stable(a,b)

static func resolve(expected,nodes,reidentify=false):
	var matches=[]
	for node in nodes:
		if node is Dictionary and exact(expected,node):matches.append(node)
	if matches.size()==1:return matches[0]
	if matches.size()>1 or not reidentify:return {}
	for node in nodes:
		if node is Dictionary and str(expected.get("id",""))!="" and str(node.get("id",""))==str(expected.get("id","")):return {}
	for node in nodes:
		if node is Dictionary and stable(expected,node):matches.append(node)
	return matches[0] if matches.size()==1 else {}

static func label(node):
	var names=PackedStringArray()
	for parent in descriptor(node).ancestors:
		if not parent.name.is_empty():names.append(parent.name)
	return " › ".join(names)

static func prompt_scope(node):
	var result=[]
	for parent in descriptor(node).ancestors.slice(-2):
		if not parent.name.is_empty():result.append(parent.name.left(48))
	return result

static func receipt(node,action):
	var item=descriptor(node)
	item["id"]=str(node.get("id",""));item["name"]=str(node.get("name","")).left(160)
	item["action"]=action;item["result"]="verified"
	return item
