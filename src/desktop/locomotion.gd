extends RefCounted
## Bounded, time-sampled travel. Gait follows distance, never frame count.
var origin=Vector2.ZERO
var destination=Vector2.ZERO
var distance=0.0
var travel_seconds=0.0
var anticipation=0.14
var clock=0.0
var active=false
var direction=1.0

func start(from,to,pixels_per_second=180.0):
	origin=Vector2(from);destination=Vector2(to)
	distance=origin.distance_to(destination)
	clock=0.0
	direction=-1.0 if destination.x<origin.x else 1.0
	active=distance>=8.0
	# Quintic easing has peak speed 1.875 * average speed.
	travel_seconds=maxf(0.38,distance*1.875/clampf(pixels_per_second,80,360))
	return active

func sample(delta):
	if not is_finite(delta) or delta<0:delta=0
	if active:clock+=delta
	var p=clampf((clock-anticipation)/maxf(travel_seconds,0.001),0,1)
	var eased=p*p*p*(p*(p*6.0-15.0)+10.0)
	var velocity=distance*30.0*p*p*(1.0-p)*(1.0-p)/maxf(travel_seconds,0.001)
	if p>=1:active=false
	return {"position":origin.lerp(destination,eased),"distance":distance*eased,
		"speed":velocity,"direction":direction,"stage":"prepare" if clock<anticipation else ("travel" if active else "arrived"),"active":active}

func cancel():
	active=false
