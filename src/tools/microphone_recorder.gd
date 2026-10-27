extends Node
signal captured(wav)
signal failed(key)
signal changed
var recording=false
var elapsed=0.0
var player
var recorder
var bus_index=-1
var conversion
var revision=0
var conversion_revision=0
func start():
	if recording or conversion!=null:return false
	if DisplayServer.get_name()=="headless" or AudioServer.get_input_device_list().is_empty():failed.emit("voice_microphone_unavailable");return false
	if bus_index<0:
		AudioServer.add_bus();bus_index=AudioServer.bus_count-1
		AudioServer.set_bus_name(bus_index,"LeemonMicrophone")
		AudioServer.set_bus_mute(bus_index,true)
		player=AudioStreamPlayer.new();player.stream=AudioStreamMicrophone.new()
		player.bus="LeemonMicrophone";add_child(player)
	if not recorder:
		recorder=AudioEffectRecord.new();recorder.format=AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(bus_index,recorder)
	revision+=1;elapsed=0;recording=true
	recorder.set_recording_active(true);player.play();changed.emit()
	return true
func finish():
	if not recording:return
	recording=false;player.stop();recorder.set_recording_active(false)
	var data=recorder.get_recording()
	AudioServer.remove_bus_effect(bus_index,0);recorder=null
	conversion_revision=revision
	conversion=Thread.new()
	conversion.start(func():return preload("res://src/tools/voice_audio.gd").new().prepare(data))
	changed.emit()
func _process(delta):
	if recording:
		elapsed+=delta
		if elapsed>0.3 and not player.playing:cancel();failed.emit("voice_microphone_unavailable")
		elif elapsed>=20.0:finish()
	if conversion!=null and not conversion.is_alive():
		var result=conversion.wait_to_finish();conversion=null
		if conversion_revision==revision:
			if result.ok:captured.emit(result.wav)
			else:failed.emit(result.key)
		changed.emit()
func cancel():
	revision+=1;recording=false
	if is_instance_valid(player):player.stop()
	if recorder:
		recorder.set_recording_active(false)
		AudioServer.remove_bus_effect(bus_index,0);recorder=null
	changed.emit()
func _exit_tree():
	cancel()
	if conversion!=null:conversion.wait_to_finish()
	if bus_index>=0 and bus_index<AudioServer.bus_count:AudioServer.remove_bus(bus_index)
