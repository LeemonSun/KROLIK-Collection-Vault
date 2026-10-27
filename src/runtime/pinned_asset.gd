extends Node
## One pinned data file, explicitly installed. Never starts a worker or executes content.
signal changed
var bundle_managed=false
var bundled_verified=false
var manifest={}
var directory="user://vision-v1"
var status="vision_not_installed"
var downloading=false
var hash_thread
var http
func _ready():
	if manifest.is_empty():manifest=JSON.parse_string(FileAccess.get_file_as_string("res://config/vision_asset.json"))
	http=HTTPRequest.new();http.use_threads=true;http.timeout=3600;http.max_redirects=8
	http.download_chunk_size=1048576;add_child(http);http.request_completed.connect(_complete)
	if installed():status="vision_installed"
func path():return directory.path_join(str(manifest.get("file","asset")))
func installed():
	if bundle_managed:return bundled_verified
	var f=FileAccess.open(path(),FileAccess.READ)
	if not f or f.get_length()!=int(manifest.get("bytes",-1)):return false
	var receipt=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("installed.json"))) if FileAccess.file_exists(directory.path_join("installed.json")) else null
	return receipt is Dictionary and receipt.get("sha256")==manifest.get("sha256") and int(receipt.get("mtime",-1))==FileAccess.get_modified_time(path())
func installing():return downloading or hash_thread!=null
func install():
	if bundle_managed:return false
	if installing():return false
	if not str(manifest.get("url","")).begins_with("https://"):return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))!=OK:return false
	http.download_file=path()+".part";http.body_size_limit=int(manifest.bytes)+1024
	downloading=true;status="vision_downloading";changed.emit()
	if http.request(manifest.url)!=OK:_fail();return false
	return true
func _complete(result,code,_headers,_body):
	if not downloading:return
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:_fail();return
	var f=FileAccess.open(path()+".part",FileAccess.READ)
	if not f or f.get_length()!=int(manifest.bytes):_fail();return
	status="ai_verifying";hash_thread=Thread.new()
	var target=path()+".part"
	hash_thread.start(func():return FileAccess.get_sha256(target));changed.emit()
func _process(_delta):
	if hash_thread==null or hash_thread.is_alive():return
	var digest=hash_thread.wait_to_finish();hash_thread=null
	if digest!=manifest.sha256:_fail();return
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path()+".part"),ProjectSettings.globalize_path(path()))!=OK:_fail();return
	var f=FileAccess.open(directory.path_join("installed.json"),FileAccess.WRITE)
	if not f:_fail();return
	f.store_string(JSON.stringify({"sha256":digest,"mtime":FileAccess.get_modified_time(path())}));f.close()
	downloading=false;status="vision_installed";changed.emit()
func progress():return clampf(float(http.get_downloaded_bytes())/float(manifest.bytes),0,1) if downloading else -1.0
func cancel_install():
	if hash_thread!=null:return false
	http.cancel_request();downloading=false
	if FileAccess.file_exists(path()+".part"):DirAccess.remove_absolute(ProjectSettings.globalize_path(path()+".part"))
	status="vision_installed" if installed() else "vision_not_installed";changed.emit();return true
func _fail():
	downloading=false;status="ai_install_failed";changed.emit()
func _exit_tree():
	if http:http.cancel_request()
	if hash_thread!=null:hash_thread.wait_to_finish()
