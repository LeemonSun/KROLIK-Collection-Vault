extends Node
## Optional Steam/portable layout: AI/text, AI/voice and AI/vision beside the EXE.
## Weights stay in place, verified in one low-priority thread and never loaded here.
signal changed
var packages={}
var verifier
var cache_path="user://bundle-cache.json"
var bundle_root=""
var finished=false
func _ready():
	if bundle_root.is_empty():
		if OS.get_executable_path().get_file().to_lower()!="companion.exe":finished=true;set_process(false);return
		bundle_root=OS.get_executable_path().get_base_dir().path_join("AI")
	var cache=JSON.parse_string(FileAccess.get_file_as_string(cache_path)) if FileAccess.file_exists(cache_path) else {}
	if not cache is Dictionary:cache={}
	for key in ["text","voice","vision"]:
		var config={"text":"local_worker","voice":"voice_worker","vision":"vision_asset"}[key]
		var spec=JSON.parse_string(FileAccess.get_file_as_string("res://config/"+config+".json"))
		var folder=bundle_root.path_join(key)
		var files=[]
		if key=="vision":files.append({"path":folder.path_join(spec.file),"sha256":spec.sha256,"bytes":spec.bytes})
		else:
			files.append({"path":folder.path_join(spec.model.file),"sha256":spec.model.sha256,"bytes":spec.model.bytes})
			for name in spec.runtime.files:files.append({"path":folder.path_join("runtime").path_join(name),"sha256":spec.runtime.files[name],"bytes":-1})
		var stats=[];var present=true
		for file in files:
			var f=FileAccess.open(file.path,FileAccess.READ)
			if not f or (int(file.bytes)>0 and f.get_length()!=int(file.bytes)):present=false;break
			stats.append([file.path,file.sha256,f.get_length(),FileAccess.get_modified_time(file.path)])
		if not present:continue
		var fingerprint=JSON.stringify(stats).sha256_text()
		packages[key]={"folder":folder,"files":files,"fingerprint":fingerprint,"ready":cache.get(key,"")==fingerprint}
	var pending={}
	for key in packages:
		if not packages[key].ready:pending[key]=packages[key].files.duplicate(true)
	if pending.is_empty():finished=true;changed.emit();set_process(false);return
	verifier=Thread.new()
	verifier.start(func():
		var result={}
		for key in pending:
			var valid=true
			for file in pending[key]:
				if FileAccess.get_sha256(file.path)!=file.sha256:valid=false;break
			result[key]=valid
		return result,Thread.PRIORITY_LOW)
func _process(_delta):
	if verifier==null or verifier.is_alive():return
	var results=verifier.wait_to_finish();verifier=null
	for key in results:packages[key].ready=results[key]
	var cache={}
	for key in packages:
		if packages[key].ready:cache[key]=packages[key].fingerprint
	var f=FileAccess.open(cache_path,FileAccess.WRITE)
	if f:f.store_string(JSON.stringify(cache));f.close()
	finished=true;changed.emit();set_process(false)
func _exit_tree():
	if verifier!=null:verifier.wait_to_finish()
