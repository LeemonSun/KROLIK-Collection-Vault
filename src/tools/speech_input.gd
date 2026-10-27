extends Node
signal changed
signal text_ready(text)
signal failed(key)
var transcriber
var microphone
var state="idle"
var language="ru"
var error_key=""
func _ready():
	transcriber=preload("res://src/tools/whisper_transcriber.gd").new()
	add_child(transcriber)
	microphone=preload("res://src/tools/microphone_recorder.gd").new()
	add_child(microphone)
	microphone.captured.connect(_captured)
	microphone.failed.connect(_failed)
	microphone.changed.connect(func():changed.emit())
	transcriber.transcribed.connect(func(text):state="idle";error_key="";text_ready.emit(text);changed.emit())
	transcriber.transcription_failed.connect(_failed)
	transcriber.status_changed.connect(func():changed.emit())
func installed():return is_instance_valid(transcriber) and transcriber.installed()
func installing():return is_instance_valid(transcriber) and (transcriber.downloading or transcriber.hash_thread!=null)
func busy():return state in ["recording","preparing","transcribing"]
func install():
	if busy():return false
	return transcriber.install()
func start(locale):
	if busy() or not installed():return false
	language={"ru":"ru","en":"en","zh-Hans":"zh"}.get(locale,"auto")
	error_key="";state="recording"
	if not microphone.start():state="idle";return false
	changed.emit();return true
func finish():
	if state!="recording":return
	state="preparing";microphone.finish();changed.emit()
func _captured(wav):
	state="transcribing";changed.emit()
	if not transcriber.transcribe(wav,language):_failed("voice_start_failed")
func _failed(key):
	state="idle";error_key=key;failed.emit(key);changed.emit()
func cancel():
	if is_instance_valid(microphone):microphone.cancel()
	if is_instance_valid(transcriber):transcriber.cancel_transcription()
	state="idle";changed.emit()
