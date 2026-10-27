extends SceneTree
var checks=0
var failures=0
var recognized=""
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _run():
	var voice_app=root.get_node("App")
	check(voice_app.speech_input.transcriber.base_path=="user://voice-v1" and voice_app.speech_input.transcriber.base_path!=voice_app.local_runtime.base_path,"Voice and text models have distinct install/receipt folders")
	var helper=preload("res://src/tools/voice_audio.gd").new()
	var input=AudioStreamWAV.new();input.format=AudioStreamWAV.FORMAT_16_BITS;input.mix_rate=48000;input.stereo=true
	var data=PackedByteArray();data.resize(48000*2*2)
	for i in range(48000):
		var sample=int(sin(float(i)*TAU*440/48000)*6000)
		data.encode_s16(i*4,sample);data.encode_s16(i*4+2,sample)
	input.data=data
	var prepared=helper.prepare(input)
	check(prepared.ok and prepared.wav.mix_rate==16000 and not prepared.wav.stereo and prepared.wav.data.size()==32000,"Real stereo 48kHz PCM resampled to mono16kHz")
	check(prepared.rms>0.1 and prepared.rms<0.2,"Energy retained")
	input.data=PackedByteArray();check(not helper.prepare(input).ok,"Empty audio rejected")
	data.fill(0);input.data=data
	check(helper.prepare(input).get("key")=="voice_silence","Silence rejected before model load")
	input.mix_rate=100;check(not helper.prepare(input).ok,"Invalid sample rate rejected")
	var engine=preload("res://src/tools/whisper_transcriber.gd").new()
	engine.manifest={"model":{"file":"fixture.bin"},"runtime":{}}
	for cores in [1,2,4,16]:
		var args=engine.build_asr_args("input.wav","output","ru",cores)
		check(int(args[args.find("-t")+1])<=maxi(1,cores/2) and int(args[args.find("-t")+1])<=2,"ASR bounded CPU threads "+str(cores))
		check("-ng" in args and args[args.find("-p")+1]=="1","CPU only, single processor job")
	engine.free()
	var app=root.get_node("App")
	check(not app.speech_input.busy(),"Microphone is idle on app startup")
	check(not app.speech_input.microphone.recording and app.speech_input.microphone.player==null,"No microphone stream created before user request")
	var voice=preload("res://src/tools/speech_input.gd").new();root.add_child(voice)
	voice.cancel();check(not voice.busy(),"Cancel idempotent")
	voice.queue_free()
	var path=OS.get_environment("COMPANION_VOICE_FIXTURE")
	if not path.is_empty():
		engine=preload("res://src/tools/whisper_transcriber.gd").new()
		engine.base_path=path;engine.manifest=JSON.parse_string(FileAccess.get_file_as_string(path.path_join("fixture.json")))
		root.add_child(engine)
		engine.transcribed.connect(func(text):recognized=text)
		engine.transcription_failed.connect(func(key):recognized="ERROR:"+key)
		check(engine.installed(),"Verified real ASR fixture recognized")
		var audio=AudioStreamWAV.load_from_file(OS.get_environment("COMPANION_VOICE_WAV"))
		check(engine.transcribe(audio,"en"),"Real Whisper process requested through app adapter")
		var deadline=Time.get_ticks_msec()+60000
		while recognized.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check("fellow Americans" in recognized and "ask not" in recognized,"Real audio transcription matches public test recording")
		check(engine.asr_pid<0 and engine.job_folder.is_empty() and engine.process_io.is_empty(),"Process and private transcript handles released")
		check(DirAccess.get_directories_at("user://voice-jobs").is_empty(),"No WAV or TXT job folders after completion")
		check(engine.transcribe(audio,"en"),"Second job can start")
		engine.cancel_transcription()
		await create_timer(0.3).timeout
		check(engine.asr_pid<0 and engine.job_folder.is_empty(),"Cancellation prevents later process launch and clears private audio")
		engine.queue_free()
	print("VOICE_TESTS: %s checks, %s failures; real_fixture=%s; no physical microphone on this host" % [checks,failures,not path.is_empty()])
	quit(0 if failures==0 else 1)
