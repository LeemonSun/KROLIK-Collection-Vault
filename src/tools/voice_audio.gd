extends RefCounted
## Linear-time PCM preparation. Cache the engine-owned data ONCE, preserve quiet short speech.
const TARGET_RATE=16000
const MAX_SECONDS=20
func prepare(wav):
	if not wav is AudioStreamWAV or wav.format!=AudioStreamWAV.FORMAT_16_BITS:return {"ok":false,"key":"voice_audio_invalid"}
	var input=wav.data
	var channels=2 if wav.stereo else 1
	if input.size()%(2*channels)!=0:return {"ok":false,"key":"voice_audio_invalid"}
	var frame_count=input.size()/(2*channels)
	if wav.mix_rate<8000 or wav.mix_rate>192000 or frame_count<maxi(1,wav.mix_rate/4) or frame_count>wav.mix_rate*MAX_SECONDS:return {"ok":false,"key":"voice_audio_invalid"}
	# Select the strongest stereo channel. Averaging anti-phase microphones can erase speech.
	var channel=0
	if channels==2:
		var left_energy=0.0;var right_energy=0.0
		for i in range(0,frame_count,16):
			left_energy+=pow(float(input.decode_s16(i*4)),2);right_energy+=pow(float(input.decode_s16(i*4+2)),2)
		if right_energy>left_energy:channel=1
	var count=mini(TARGET_RATE*MAX_SECONDS,int(float(frame_count)*TARGET_RATE/wav.mix_rate))
	var pcm=PackedByteArray();pcm.resize(count*2)
	var power=0.0;var blocks=[];var block_energy=0.0;var peak=0.0
	for i in range(count):
		var source=minf(float(frame_count-1),float(i)*wav.mix_rate/TARGET_RATE)
		var left=int(source);var right=mini(left+1,frame_count-1)
		var value=clampi(int(lerpf(input.decode_s16((left*channels+channel)*2),input.decode_s16((right*channels+channel)*2),source-left)),-32768,32767)
		pcm.encode_s16(i*2,value)
		var energy=pow(float(value)/32768.0,2);power+=energy;block_energy+=energy
		if (i+1)%320==0 or i==count-1:
			var rms=sqrt(block_energy/float((i%320)+1));blocks.append(rms);peak=maxf(peak,rms);block_energy=0
	if peak<0.00025:return {"ok":false,"key":"voice_silence"}
	var start=0;var finish=count;var threshold=maxf(0.00025,peak*0.08)
	for i in range(blocks.size()):
		if blocks[i]>=threshold:start=maxi(0,i*320-1600);break
	for i in range(blocks.size()-1,-1,-1):
		if blocks[i]>=threshold:finish=mini(count,(i+1)*320+1600);break
	pcm=pcm.slice(start*2,finish*2)
	var rms=sqrt(power/maxi(1,count))
	var gain=minf(12.0,0.08/maxf(rms,0.000001)) if rms<0.04 else 1.0
	if gain>1:
		for i in range(pcm.size()/2):pcm.encode_s16(i*2,clampi(int(pcm.decode_s16(i*2)*gain),-32768,32767))
	var result=AudioStreamWAV.new();result.format=AudioStreamWAV.FORMAT_16_BITS;result.mix_rate=TARGET_RATE;result.stereo=false;result.data=pcm
	return {"ok":true,"wav":result,"seconds":float(finish-start)/TARGET_RATE,"rms":rms,"gain":gain}
