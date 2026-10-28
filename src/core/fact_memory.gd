extends RefCounted
## Explicit compact facts, not transcript compression or a vector model.
const MAX_BYTES=524288
const MAX_FACTS=1024
var path="user://facts-v1.json"
var facts={}
var writable=true
static func key(raw):return raw.strip_edges().to_lower().replace("ё","е").replace("colour","color").replace("favourite","favorite")
static func valid(data):
	if not data is Dictionary or data.size()>MAX_FACTS:return false
	for id in data:
		if not id is String or id.is_empty() or id.length()>96:return false
		var item=data[id]
		if not item is Dictionary or item.size()!=2 or not item.get("value") is String or item.value.length()>512 or not item.get("deleted") is bool:return false
	return JSON.stringify(data).to_utf8_buffer().size()<=MAX_BYTES
func load_state():
	if not FileAccess.file_exists(path):return true
	var file=FileAccess.open(path,FileAccess.READ)
	if not file or file.get_length()>MAX_BYTES:writable=false;return false
	var parser=JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary or parser.data.get("schema")!=1 or not valid(parser.data.get("facts")):writable=false;return false
	facts=parser.data.facts;return true
func set_fact(name,value,deleted=false):
	if not writable or not name is String or not value is String:return false
	var id=key(name);var next=facts.duplicate(true)
	next[id]={"value":"" if deleted else value.strip_edges(),"deleted":deleted}
	if not valid(next):return false
	var bytes=JSON.stringify({"schema":1,"facts":next}).to_utf8_buffer()
	if bytes.size()>MAX_BYTES:return false
	var file=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if not file:return false
	file.store_buffer(bytes);file.flush();file.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))!=OK:return false
	facts=next;return true
func recall(query):
	var q=key(query);var scored=[]
	for id in facts:
		if facts[id].deleted:continue
		var score=3 if id in q else 0
		for word in id.split(" "):
			if word.length()>2 and word in q:score+=1
		if score>0:scored.append({"key":id,"value":facts[id].value,"score":score})
	scored.sort_custom(func(a,b):return a.score>b.score)
	var result=[];var used=0
	for item in scored:
		var record={"key":item.key,"value":item.value};var size=JSON.stringify(record).to_utf8_buffer().size()
		if used+size>960:continue
		result.append(record);used+=size
		if result.size()==4:break
	return result
static func merge(base,local,remote):
	# Three-way merge: divergent changes require review instead of trusting device clocks.
	if not valid(base) or not valid(local) or not valid(remote):return {"ok":false}
	var result=local.duplicate(true);var conflicts=[];var ids={}
	for data in [base,local,remote]:
		for id in data:ids[id]=true
	for id in ids:
		var before=base.get(id);var left=local.get(id);var right=remote.get(id)
		if left==right or right==before:continue
		if left==before:
			if right==null:result.erase(id)
			else:result[id]=right.duplicate(true)
		else:conflicts.append(id)
	if not valid(result):return {"ok":false}
	return {"ok":true,"facts":result,"conflicts":conflicts}
