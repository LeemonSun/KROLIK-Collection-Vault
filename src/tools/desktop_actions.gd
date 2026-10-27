extends Node
signal completed(result)
var pid=-1
var nonce=""
var job=""
var started_ms=0
var last_result={}
var runner="powershell.exe"
var test_runner=false
func request(target):
	if pid>0:return false
	if OS.get_name()!="Windows" and not test_runner:
		_finish.call_deferred({"status":"unsupported"})
		return true
	var support="user://support"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(support+"/jobs"))
	var helper=FileAccess.get_file_as_bytes("res://native/desktop_bridge.ps1")
	var output=FileAccess.open(support+"/desktop_bridge.ps1",FileAccess.WRITE)
	if not output:
		_finish.call_deferred({"status":"failed"});return true
	output.store_buffer(helper); output.close()
	nonce=Crypto.new().generate_random_bytes(16).hex_encode()
	job=support+"/jobs/"+nonce
	output=FileAccess.open(job+".request.json",FileAccess.WRITE)
	if not output:
		_finish.call_deferred({"status":"failed"});return true
	output.store_string(JSON.stringify({"nonce":nonce,"target":target}));output.close()
	var arguments=PackedStringArray(["-NoLogo","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",ProjectSettings.globalize_path(support+"/desktop_bridge.ps1"),"-RequestPath",ProjectSettings.globalize_path(job+".request.json"),"-ResultPath",ProjectSettings.globalize_path(job+".result.json")])
	pid=OS.create_process(runner,arguments,false)
	started_ms=Time.get_ticks_msec()
	if pid<0:_finish.call_deferred({"status":"failed"})
	return true
func _process(_delta):
	if pid<=0:return
	if FileAccess.file_exists(job+".result.json"):
		var file=FileAccess.open(job+".result.json",FileAccess.READ)
		var parsed=JSON.new()
		if file and file.get_length()<32768 and parsed.parse(file.get_as_text())==OK and parsed.data is Dictionary and parsed.data.get("nonce")==nonce:
			_finish(parsed.data);return
	if Time.get_ticks_msec()-started_ms>15000:
		if OS.is_process_running(pid):OS.kill(pid)
		_finish({"status":"timeout"})
	elif not OS.is_process_running(pid):_finish({"status":"failed"})
func _finish(result):
	pid=-1;last_result=result
	_cleanup()
	completed.emit(result)
func _cleanup():
	if job.is_empty():return
	for suffix in [".request.json",".result.json",".result.json.tmp"]:
		if FileAccess.file_exists(job+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(job+suffix))
	job="";nonce=""
func cancel():
	if pid>0 and OS.is_process_running(pid):OS.kill(pid)
	pid=-1
	_cleanup()
func _exit_tree():cancel()
