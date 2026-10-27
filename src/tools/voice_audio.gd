extends RefCounted
## Bounded PCM preparation; no learned VAD and no audio persistence here.
const TARGET_RATE=16000
const MAX_SECONDS=20
func prepare(wav):
	if not wav is AudioStreamWAV or wav.format!=AudioStreamWAV.FORMAT_16_BITS:return {"ok":false,"key":"voice_audio_invalid"}
	var channels=2 if wav.stereo else 1
	var frame_count=wav.data.size()/(2*channels)
	if wav.mix_rate<8000 or wav.mix_rate>192000 or frame_count<maxi(1,wav.mix_rate/4) or frame_count>wav.mix_rate*MAX_SECONDS:return {"ok":false,"key":"voice_audio_invalid"}
	var output_frames=mini(TARGET_RATE*MAX_SECONDS,int(float(frame_count)*TARGET_RATE/wav.mix_rate))
	var pcm=PackedByteArray();pcm.resize(output_frames*2)
	var power=0.0
	for i in range(output_frames):
		var source=minf(float(frame_count-1),float(i)*wav.mix_rate/TARGET_RATE)
		var left=int(source);var right=mini(left+1,frame_count-1);var weight=source-left
		var a=0.0;var b=0.0
		for channel in range(channels):
			a+=wav.data.decode_s16((left*channels+channel)*2)
			b+=wav.data.decode_s16((right*channels+channel)*2)
		var value=clampi(int(lerpf(a/channels,b/channels,weight)),-32768,32767)
		pcm.encode_s16(i*2,value);power+=pow(float(value)/32768.0,2)
	var rms=sqrt(power/maxi(1,output_frames))
	if rms<0.006:return {"ok":false,"key":"voice_silence"}
	var result=AudioStreamWAV.new();result.format=AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate=TARGET_RATE;result.stereo=false;result.data=pcm
	return {"ok":true,"wav":result,"seconds":float(output_frames)/TARGET_RATE,"rms":rms}
