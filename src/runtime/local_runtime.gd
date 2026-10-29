extends Node
## Explicit, pinned local model installation and an owned CPU worker. No cloud inference.
signal status_changed
signal ready_for_chat(port, token)
var bundle_managed=false
var bundled_verified=false
var manifest = {}
var base_path = "user://local-ai-v2"
var status = "ai_not_installed"
var detail = ""
var downloading = false
var last_launch_summary={}
var pid = -1
var port = 0
var token = ""
var last_used_ms = 0
var idle_seconds = 120
var generation_busy = false
var download
var probe
var hash_thread
var hash_target = ""
var phase = ""
var deadline_ms = 0
var next_probe_ms = 0
var starting = false
var _options = {}
var next_liveness_ms=0
var start_verifier
var start_revision=0
var verifier_revision=0
var custom_model={}
var original_model={}
var runtime_only=false
var model_change_busy=false
var probe_revision=0
var shutting_down=false

func _ready():
	if manifest.is_empty():
		manifest = JSON.parse_string(FileAccess.get_file_as_string("res://config/local_worker.json"))
	original_model=manifest.model.duplicate(true)
	download = HTTPRequest.new()
	download.use_threads = true
	download.timeout = 3600
	download.max_redirects = 8
	download.download_chunk_size = 1024 * 1024
	add_child(download)
	download.request_completed.connect(_download_complete)
	_make_probe()
	if installed():
		status = "ai_installed"

func _make_probe():
	probe = HTTPRequest.new()
	probe.timeout = 2.0
	probe.max_redirects = 0
	probe.body_size_limit = 65536
	probe.set_http_proxy("", -1)
	probe.set_https_proxy("", -1)
	add_child(probe)
	var revision=probe_revision
	probe.request_completed.connect(func(result,code,headers,body):
		if revision==probe_revision:_probe_complete(result,code,headers,body))

func _status(value, extra = ""):
	status = value
	detail = extra
	status_changed.emit()

func model_path():
	if not custom_model.is_empty():return str(custom_model.get("file","user://missing-model.gguf"))
	return base_path.path_join(str(manifest.model.file))

func select_external(entry={}):
	if downloading or hash_thread!=null or start_verifier!=null or starting or pid>0:return false
	custom_model=entry.duplicate(true)
	manifest.model=original_model.duplicate(true) if entry.is_empty() else {"file":str(entry.get("file","")).get_file(),"sha256":entry.get("sha256",""),"bytes":entry.get("bytes",0)}
	_status("ai_installed" if installed() else "ai_not_installed")
	return true

func runtime_available():
	if bundle_managed and not bundled_verified:return false
	for name in manifest.runtime.files:
		if not FileAccess.file_exists(runtime_path().path_join(name)):return false
	return true

func runtime_path():
	return base_path.path_join("runtime")

func installed():
	if not custom_model.is_empty():
		var f=FileAccess.open(model_path(),FileAccess.READ)
		return runtime_available() and str(custom_model.get("sha256","")).length()==64 and f!=null and f.get_length()==int(custom_model.get("bytes",-1)) and FileAccess.get_modified_time(model_path())==int(custom_model.get("mtime",-1))
	if bundle_managed:return bundled_verified
	if manifest.is_empty():
		return false
	var receipt_path = base_path.path_join("installed.json")
	if not FileAccess.file_exists(receipt_path) or not FileAccess.file_exists(model_path()):
		return false
	var receipt = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	var model = FileAccess.open(model_path(), FileAccess.READ)
	return receipt is Dictionary and receipt.get("model_sha256") == manifest.model.sha256 and receipt.get("runtime_sha256") == manifest.runtime.sha256 and model != null and model.get_length() == int(manifest.model.bytes) and int(receipt.get("model_mtime", -1)) == FileAccess.get_modified_time(model_path()) and FileAccess.file_exists(runtime_path().path_join(manifest.runtime.executable))

func install():return _install(false)
func install_runtime_only():return _install(true)
func _install(only_runtime):
	if bundle_managed:return false
	if not custom_model.is_empty() and not only_runtime:return false
	if downloading or hash_thread != null or start_verifier!=null or starting or pid > 0:
		return false
	if OS.get_name() != manifest.get("platform"):
		_status("ai_windows_only")
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_path))
	runtime_only=only_runtime
	downloading = true
	phase = "runtime"
	return _download_part()

func _download_part():
	var part = manifest.runtime if phase == "runtime" else manifest.model
	var target = base_path.path_join("worker.zip.part") if phase == "runtime" else model_path() + ".part"
	# Runtime and model URLs are fixed in the reviewed manifest, never supplied by model output.
	if not str(part.url).begins_with("https://"):
		_fail("ai_install_failed")
		return false
	download.download_file = target
	download.body_size_limit = int(part.bytes) + 1024
	_status("ai_downloading_runtime" if phase == "runtime" else "ai_downloading_model")
	var error = download.request(part.url)
	if error != OK:
		_fail("ai_install_failed")
		return false
	return true

func _download_complete(result, code, _headers, _body):
	if not downloading:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("ai_install_failed")
		return
	var target = download.download_file
	var part = manifest.runtime if phase == "runtime" else manifest.model
	var file = FileAccess.open(target, FileAccess.READ)
	if file == null or file.get_length() != int(part.bytes):
		_fail("ai_hash_failed")
		return
	hash_target = target
	hash_thread = Thread.new()
	_status("ai_verifying")
	hash_thread.start(func(): return FileAccess.get_sha256(target))

func _process(_delta):
	if start_verifier!=null and not start_verifier.is_alive():
		var valid=start_verifier.wait_to_finish()
		start_verifier=null
		if starting and verifier_revision==start_revision:
			if valid:_spawn_worker()
			else:starting=false;_status("ai_hash_failed")
	if hash_thread != null and not hash_thread.is_alive():
		var digest = hash_thread.wait_to_finish()
		hash_thread = null
		var part = manifest.runtime if phase == "runtime" else manifest.model
		if digest != part.sha256:
			_fail("ai_hash_failed")
		elif phase == "runtime":
			if not _extract_runtime(hash_target):
				_fail("ai_install_failed")
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(hash_target))
				if runtime_only:
					downloading=false
					_status("ai_installed" if installed() else "ai_not_installed")
				else:
					phase = "model"
					_download_part()
		else:
			var path = ProjectSettings.globalize_path(model_path())
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(hash_target), path) != OK:
				_fail("ai_install_failed")
			else:
				var receipt = {"model_sha256": manifest.model.sha256, "runtime_sha256": manifest.runtime.sha256, "model_mtime": FileAccess.get_modified_time(model_path())}
				var f = FileAccess.open(base_path.path_join("installed.json"), FileAccess.WRITE)
				if f == null:
					_fail("ai_install_failed")
				else:
					f.store_string(JSON.stringify(receipt))
					f.close()
					downloading = false
					_status("ai_installed")
	var now = Time.get_ticks_msec()
	if pid>0 and now>=next_liveness_ms:
		next_liveness_ms=now+500
		if not OS.is_process_running(pid):
			pid=-1
			starting=false
			_status("ai_worker_failed")
	if starting and start_verifier==null:
		if now > deadline_ms:
			stop()
			_status("ai_worker_failed")
		elif now >= next_probe_ms and probe.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
			next_probe_ms = now + 500
			probe.request("http://127.0.0.1:%s/v1/models" % port, ["Authorization: Bearer " + token])
	elif pid > 0 and not generation_busy and now - last_used_ms > idle_seconds * 1000:
		stop()
		_status("ai_sleeping")

func _extract_runtime(path):
	var zip = ZIPReader.new()
	if zip.open(path) != OK:
		return false
	var dir = runtime_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	# Copy only the pinned allowlist. No paths supplied by the archive are interpreted.
	for name in manifest.runtime.files:
		var prefix=str(manifest.runtime.get("archive_prefix",""))
		var member=prefix+name
		if ".." in prefix or name.get_file() != name or not zip.file_exists(member):
			zip.close()
			return false
		var data = zip.read_file(member)
		var context = HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(data)
		if context.finish().hex_encode() != manifest.runtime.files[name]:
			zip.close()
			return false
		var file = FileAccess.open(dir.path_join(name), FileAccess.WRITE)
		if file == null:
			zip.close()
			return false
		file.store_buffer(data)
		file.close()
	zip.close()
	return true

func start(options = {}):
	if model_change_busy:return false
	if pid > 0 or starting:
		return true
	if downloading or hash_thread != null or start_verifier!=null:
		return false
	if not installed():
		_status("ai_not_installed")
		return false
	if OS.get_name() != manifest.get("platform"):
		_status("ai_windows_only")
		return false
	if not memory_headroom(options,OS.get_memory_info()):
		_status("ai_memory_low")
		return false
	_options=options.duplicate(true)
	start_revision+=1;verifier_revision=start_revision
	starting=true
	deadline_ms=Time.get_ticks_msec()+120000
	var folder=ProjectSettings.globalize_path(runtime_path())
	var expected=manifest.runtime.files.duplicate(true)
	var selected_path=ProjectSettings.globalize_path(model_path())
	var expected_model=str(custom_model.get("sha256",""))
	start_verifier=Thread.new()
	start_verifier.start(func():
		for name in expected:
			if FileAccess.get_sha256(folder.path_join(name))!=expected[name]:return false
		if not expected_model.is_empty() and FileAccess.get_sha256(selected_path)!=expected_model:return false
		return true)
	_status("ai_starting")
	return true

func _spawn_worker():
	var options=_options
	var socket = TCPServer.new()
	port = 0
	for _attempt in range(32):
		var candidate = randi_range(20000, 55000)
		if socket.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			socket.stop()
			break
	if port == 0:
		starting=false
		_status("ai_worker_failed")
		return false
	token = Crypto.new().generate_random_bytes(32).hex_encode()
	_options = options.duplicate()
	idle_seconds = clampi(int(options.get("idle_unload_seconds", 120)), 30, 900)
	last_launch_summary=_describe_launch(options)
	var args = build_args(options)
	pid = OS.create_process(ProjectSettings.globalize_path(runtime_path().path_join(manifest.runtime.executable)), args, false)
	if pid <= 0:
		starting=false
		_status("ai_worker_failed")
		return false
	starting = true
	deadline_ms = Time.get_ticks_msec() + 120000
	next_probe_ms = 0
	touch()
	_status("ai_starting")
	return true

func launch_summary():return last_launch_summary.duplicate(true)
func _describe_launch(options,processor_count=-1):
	var args=build_args(options,processor_count)
	var result={}
	for key in ["--threads","--threads-batch","--ctx-size","--batch-size","--ubatch-size","--parallel","--n-gpu-layers","--cache-ram","--ctx-checkpoints","--prio"]:
		var index=args.find(key)
		if index>=0 and index+1<args.size():result[key.trim_prefix("--")]=int(args[index+1])
	result["reasoning"]="off";result["idle_unload_seconds"]=clampi(int(options.get("idle_unload_seconds",120)),30,900)
	return result
func build_args(options, processor_count=-1):
	if processor_count<1:processor_count=OS.get_processor_count()
	var threads=clampi(int(options.get("cpu_threads",2)),1,mini(8,maxi(1,processor_count/2)))
	var args=PackedStringArray(["--model", ProjectSettings.globalize_path(model_path()), "--host", "127.0.0.1", "--port", str(port), "--api-key", token, "--alias", "companion", "--ctx-size", str(clampi(int(options.get("context_tokens", 2048)), 1024, 4096)), "--threads", str(threads), "--threads-batch", str(threads), "--parallel", "1", "--n-gpu-layers", "0", "--batch-size", str(clampi(int(options.get("batch_tokens",128)),32,128)), "--ubatch-size", str(clampi(int(options.get("batch_tokens",128)),32,128)), "--poll", "0", "--prio", "-1", "--no-ui", "--jinja", "--reasoning", "off"])
	# Single-user desktop worker: avoid the upstream multi-prefix RAM cache.
	args.append_array(PackedStringArray(["--cache-ram","0","--ctx-checkpoints","0"]))
	args.append("--log-disable")
	if not str(options.get("vision_projector", "")).is_empty():
		args.append_array(PackedStringArray(["--mmproj",str(options.vision_projector),"--no-mmproj-offload","--image-max-tokens","256"]))
	return args

func _probe_complete(result, code, _headers, body):
	if not starting:
		return
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary and data.get("data") is Array and not data.data.is_empty() and data.data[0].get("id") == "companion":
			starting = false
			_status("ai_ready")
			ready_for_chat.emit(port, token)

func touch():
	last_used_ms = Time.get_ticks_msec()

func progress():
	if not downloading or status == "ai_verifying":
		return -1.0
	var size = manifest.runtime.bytes if phase == "runtime" else manifest.model.bytes
	return clampf(float(download.get_downloaded_bytes()) / float(size), 0.0, 1.0)

func cancel_install():
	if hash_thread != null:
		return false # A bounded hash is finishing; no worker can start meanwhile.
	download.cancel_request()
	downloading = false
	var partials=[base_path.path_join("worker.zip.part")]
	if custom_model.is_empty():partials.append(model_path()+".part")
	for path in partials:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_status("ai_installed" if installed() else "ai_not_installed")
	return true

func _fail(key):
	downloading = false
	_status(key)

func stop():
	start_revision+=1
	starting = false
	generation_busy = false
	if probe:
		probe_revision+=1
		probe.cancel_request()
		remove_child(probe);probe.queue_free();probe=null
		if not shutting_down:_make_probe()
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1
	token = ""

func _exit_tree():
	shutting_down=true
	if start_verifier!=null:start_verifier.wait_to_finish()
	if download:
		download.cancel_request()
	if hash_thread != null:
		hash_thread.wait_to_finish()
		hash_thread = null
	stop()

func memory_headroom(options,info):
	var available=int(info.get("available",info.get("free",0)))
	if available<=0:return true # Unknown OS accounting is not a fabricated hardware limit.
	var mib=1024*1024
	var required=int(manifest.get("model",{}).get("bytes",0))+800*mib
	if not str(options.get("vision_projector","")).is_empty():required+=1024*mib
	var reserve=clampi(int(info.get("physical",0))/10,512*mib,2048*mib)
	return available>=required+reserve
