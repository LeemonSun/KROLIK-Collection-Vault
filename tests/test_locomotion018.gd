extends SceneTree
const Travel=preload("res://src/desktop/locomotion.gd")
const Behavior=preload("res://src/desktop/companion_behavior.gd")
const Rig=preload("res://src/animation/leemon_rig.gd")
var checks=0
var failures=0
func check(value,label):
	checks+=1
	if not value:failures+=1;push_error(label)
func _initialize():_run.call_deferred()
func _run():
	for fps in [15,24,30,60,144]:
		for pair in [[Vector2(-1000,300),Vector2(-400,300)],[Vector2(800,300),Vector2(100,300)],[Vector2(100,300),Vector2(100,40)]]:
			var motion=Travel.new();check(motion.start(pair[0],pair[1]),"Travel starts")
			var previous=pair[0];var frames=0;var max_speed=0.0;var max_jump=0.0
			while motion.active and frames<5000:
				var result=motion.sample(1.0/fps)
				max_speed=maxf(max_speed,result.speed)
				max_jump=maxf(max_jump,previous.distance_to(result.position))
				previous=result.position;frames+=1
			check(previous.is_equal_approx(pair[1]),"Exact endpoint at "+str(fps)+"fps")
			check(max_speed<=180.001 and max_jump<=180.01/fps,"Bounded physical speed at "+str(fps)+"fps")
			check(frames<5000,"Travel terminates")
	var a=Travel.new();var b=Travel.new()
	a.start(Vector2.ZERO,Vector2(800,0));b.start(Vector2.ZERO,Vector2(800,0))
	for i in range(24):a.sample(1.0/24)
	for i in range(60):b.sample(1.0/60)
	check(a.sample(0).position.distance_to(b.sample(0).position)<0.001,"Same elapsed time gives same location across frame rates")
	var before=a.sample(0);a.sample(-1);a.sample(NAN)
	check(a.sample(0).position==before.position,"Invalid deltas do not advance motion")
	a.cancel();var stopped=a.sample(0).position
	check(a.sample(2).position==stopped,"Cancelled travel does not resume")
	check(not Travel.new().start(Vector2.ZERO,Vector2(2,0)),"No jitter-sized travel")
	for bounds in [Rect2i(-1280,0,1280,720),Rect2i(0,0,1366,768),Rect2i(0,0,320,240)]:
		var extent=Vector2i(mini(300,bounds.size.x),mini(160,bounds.size.y))
		var anchor=Rect2i(bounds.end-Vector2i(210,232),Vector2i(210,232))
		var point=Behavior.bubble_position(anchor,bounds,extent)
		check(bounds.encloses(Rect2i(point,extent)),"Speech stays on monitor")
		if bounds.size.x>320:check(not Rect2i(point,extent).intersects(anchor),"Speech leaves mascot visible when space exists")
	var rig=Rig.new();rig.size=Vector2(210,232);root.add_child(rig);rig.set_process(false)
	rig.play("walk");rig._process(0.4);rig.set_locomotion(-1,160,123);rig._process(0.1)
	var left=rig.parts.leg_l.rotation
	rig._process(0.3)
	check(is_equal_approx(left,rig.parts.leg_l.rotation),"Distance-driven feet do not pedal while window stands still")
	rig.set_locomotion(-1,0,123);rig._process(0.3)
	check(is_zero_approx(rig.parts.leg_l.rotation),"Zero velocity plants feet")
	var before_envelope=rig.parts.head.transform
	var before_clock=rig.clip_time
	var envelope=rig.hit_envelope(PackedVector2Array([Vector2(0.1,0.1),Vector2(0.9,0.1),Vector2(0.9,0.9),Vector2(0.1,0.9)]))
	check(envelope.size()>3,"All-clip input envelope can be generated")
	check(rig.parts.head.transform==before_envelope and rig.clip_time==before_clock and rig.locomotion_driven and rig.gait_distance==123,"Envelope precomputation preserves the exact live pose and gait")
	rig.set_suspended(true);check(not rig.is_processing(),"Hidden rig has no pose processing")
	rig.set_reduced(true);rig.set_suspended(false);check(not rig.is_processing(),"Reduced motion remains still after restore")
	rig.set_reduced(false);check(rig.is_processing(),"Restore resumes visible animation")
	rig.queue_free()
	print("LOCOMOTION018: %d checks, %d failures; synthetic motion/geometry, not Windows FPS" %[checks,failures])
	quit(0 if failures==0 else 1)
