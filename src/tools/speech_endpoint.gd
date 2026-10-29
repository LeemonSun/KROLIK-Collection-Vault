extends RefCounted
## Bounded energy endpoint; no neural model and no background microphone.
var elapsed=0.0
var voiced=0.0
var quiet=0.0
var heard=false
func reset():elapsed=0;voiced=0;quiet=0;heard=false
func feed(rms,seconds):
	if not is_finite(rms) or not is_finite(seconds) or seconds<=0:return false
	elapsed+=seconds
	if rms>=0.0012:
		voiced+=seconds;quiet=0
		if voiced>=0.16:heard=true
	else:quiet+=seconds
	return elapsed>=20 or (heard and quiet>=0.7) or (not heard and elapsed>=4.0)
