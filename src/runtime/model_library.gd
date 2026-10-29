extends Node
## User-selected GGUF data only. No executable imports, downloads or automatic activation.
signal changed
var catalog=[]
var entries={}
var selected="qwen35_2b"
var path="user://model-library-v1.json"
var thread
var importing=""
var status=""
func _ready():
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://config/model_catalog.json"))
	if FileAccess.file_exists(path):
		var f=FileAccess.open(path,FileAccess.READ)
		if f and f.get_length()<65536:
			var data=JSON.parse_string(f.get_as_text())
			if data is Dictionary and data.get("schema")==1 and data.get("entries") is Dictionary:
				for id in data.entries:
					var entry=data.entries[id]
					if spec(id).is_empty() or not entry is Dictionary:continue
					if entry.get("file") is String and entry.get("sha256") is String and entry.sha256.length()==64 and typeof(entry.get("bytes")) in [TYPE_INT,TYPE_FLOAT] and typeof(entry.get("mtime")) in [TYPE_INT,TYPE_FLOAT]:
						entry.bytes=int(entry.bytes);entry.mtime=int(entry.mtime);entries[id]=entry
				if not spec(str(data.get("selected",""))).is_empty():selected=data.selected
func spec(id):
	for item in catalog:
		if item.id==id:return item
	return {}
func label():return str(spec(selected).get("name","Qwen3.5 2B"))
func record(id):return entries.get(id,{}).duplicate(true)
func available(id):
	var entry=record(id)
	if entry.is_empty():return false
	var f=FileAccess.open(str(entry.file),FileAccess.READ)
	return f!=null and f.get_length()==int(entry.bytes) and FileAccess.get_modified_time(entry.file)==int(entry.mtime)
func save():
	var f=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f==null:return false
	f.store_string(JSON.stringify({"schema":1,"selected":selected,"entries":entries}));f.flush();f.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))==OK
func choose(id):
	if thread!=null or spec(id).is_empty():return false
	var old=selected;selected=id
	if not save():selected=old;status="models_save_failed";changed.emit();return false
	status="";changed.emit();return true
func import_file(id,source):
	if thread!=null or spec(id).is_empty() or id=="qwen35_2b":return false
	var expected=spec(id).architectures.duplicate()
	importing=id;status="models_verifying";thread=Thread.new()
	thread.start(func():
		var inspector=preload("res://src/runtime/gguf_inspector.gd").new()
		var metadata=inspector.inspect(source)
		if metadata.is_empty() or metadata.get("general.architecture") not in expected:return {"ok":false}
		var digest=FileAccess.get_sha256(source)
		if digest.length()!=64 or FileAccess.get_modified_time(source)!=metadata.mtime:return {"ok":false}
		var f=FileAccess.open(source,FileAccess.READ)
		if f==null or f.get_length()!=metadata.bytes:return {"ok":false}
		return {"ok":true,"entry":{"file":source,"sha256":digest,"bytes":metadata.bytes,"mtime":metadata.mtime,"architecture":metadata.get("general.architecture"),"metadata_name":metadata.get("general.name","").left(100)}}
	,Thread.PRIORITY_LOW)
	changed.emit();return true
func _process(_delta):
	if thread==null or thread.is_alive():return
	var result=thread.wait_to_finish();thread=null
	if result.get("ok",false):
		var previous=entries.duplicate(true);entries[importing]=result.entry
		if save():status="models_imported"
		else:entries=previous;status="models_save_failed"
	else:status="models_invalid"
	importing="";changed.emit()
func _exit_tree():
	if thread!=null:thread.wait_to_finish()
