extends "res://src/runtime/local_runtime.gd"
## Reuse the pinned installer; the ASR process exists only for one explicit recording.
signal transcribed(text)
signal transcription_failed(key)
var asr_pid=-1
var asr_started_ms=0
var asr_poll_ms=0
var job_folder=""
var verify_thread
var job_revision=0
var verify_revision=0
var requested_language="auto"
var cpu_thread_limit=2
var process_io={}
var cleanup_queue=[]
var cleanup_ms=0
func _init():base_path="user://voice-v1"
func _ready():
	if manifest.is_empty():manifest=JSON.parse_string(FileAccess.get_file_as_string("res://config/voice_worker.json"))
	super._ready()
func install():
	if asr_pid>0 or verify_thread!=null:return false
	return super.install()
func busy():return asr_pid>0 or verify_thread!=null
func transcribe(wav,language="auto"):
	if busy() or not installed():return false
	if language not in ["auto","ru","en","zh"]:return false
	if not wav is AudioStreamWAV or wav.format!=AudioStreamWAV.FORMAT_16_BITS or wav.stereo or wav.mix_rate!=16000 or wav.data.size()>640000:return false
	job_revision+=1;verify_revision=job_revision
	requested_language=language
	job_folder="user://voice-jobs".path_join(Crypto.new().generate_random_bytes(16).hex_encode())
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(job_folder))!=OK:return false
	if wav.save_to_wav(job_folder.path_join("audio.wav"))!=OK:_cleanup_job();return false
	var folder=ProjectSettings.globalize_path(runtime_path());var expected=manifest.runtime.files.duplicate(true)
	verify_thread=Thread.new()
	verify_thread.start(func():
		for name in expected:
			if FileAccess.get_sha256(folder.path_join(name))!=expected[name]:return false
		return true)
	return true
func _process(delta):
	super._process(delta)
	if Time.get_ticks_msec()>cleanup_ms and not cleanup_queue.is_empty():
		cleanup_ms=Time.get_ticks_msec()+500
		for folder in cleanup_queue.duplicate():
			if _purge_folder(folder):cleanup_queue.erase(folder)
	if verify_thread!=null and not verify_thread.is_alive():
		var valid=verify_thread.wait_to_finish();verify_thread=null
		if verify_revision==job_revision:
			if valid:_launch_asr()
			else:_failed("ai_hash_failed")
	if asr_pid<=0 or Time.get_ticks_msec()<asr_poll_ms:return
	asr_poll_ms=Time.get_ticks_msec()+100
	for key in ["stdio","stderr"]:
		if process_io.has(key):process_io[key].get_buffer(4096)
	if Time.get_ticks_msec()-asr_started_ms>90000:
		_failed("voice_timeout");return
	if not OS.is_process_running(asr_pid):
		asr_pid=-1
		var path=job_folder.path_join("result.txt")
		var file=FileAccess.open(path,FileAccess.READ)
		var text=file.get_as_text().strip_edges() if file and file.get_length()<=8192 else ""
		_cleanup_job()
		if text.is_empty() or text in ["[BLANK_AUDIO]","[Music]","(Music)"]:transcription_failed.emit("voice_no_text")
		else:transcribed.emit(text)
func build_asr_args(input_path,output_path,language,processors=-1):
	if processors<1:processors=OS.get_processor_count()
	var threads=mini(clampi(cpu_thread_limit,1,2),maxi(1,processors/2))
	return PackedStringArray(["-m",ProjectSettings.globalize_path(model_path()),"-f",input_path,"-l",language,"-t",str(threads),"-p","1","-bs","1","-bo","1","-mc","0","-nf","-np","-nt","-ng","-otxt","-of",output_path])
func _launch_asr():
	var args=build_asr_args(ProjectSettings.globalize_path(job_folder.path_join("audio.wav")),ProjectSettings.globalize_path(job_folder.path_join("result")),requested_language)
	process_io=OS.execute_with_pipe(ProjectSettings.globalize_path(runtime_path().path_join(manifest.runtime.executable)),args,false)
	asr_pid=int(process_io.get("pid",-1))
	asr_started_ms=Time.get_ticks_msec()
	if asr_pid<=0:_failed("voice_start_failed")
func _failed(key):
	cancel_transcription();transcription_failed.emit(key)
func _purge_folder(folder):
	for name in ["audio.wav","result.txt"]:
		var path=folder.path_join(name)
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path))!=OK:return false
	return not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)) or DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))==OK
func _cleanup_job():
	for key in ["stdio","stderr"]:
		if process_io.has(key):process_io[key].close()
	process_io={}
	if job_folder.is_empty():return
	if not _purge_folder(job_folder):cleanup_queue.append(job_folder)
	job_folder=""
func cancel_transcription():
	job_revision+=1
	if asr_pid>0 and OS.is_process_running(asr_pid):OS.kill(asr_pid)
	asr_pid=-1
	_cleanup_job()
func _exit_tree():
	var process_id=asr_pid
	cancel_transcription()
	var deadline=Time.get_ticks_msec()+500
	while process_id>0 and OS.is_process_running(process_id) and Time.get_ticks_msec()<deadline:OS.delay_msec(20)
	for folder in cleanup_queue:_purge_folder(folder)
	if verify_thread!=null:verify_thread.wait_to_finish()
	super._exit_tree()
