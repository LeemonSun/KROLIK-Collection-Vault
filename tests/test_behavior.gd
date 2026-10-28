extends SceneTree
const Behavior=preload("res://src/desktop/companion_behavior.gd")
const Rig=preload("res://src/animation/leemon_rig.gd")
var checks=0
var failures=0
func _initialize():_run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _run():
	var bounds=Rect2i(-1280,0,1280,800);var anchor=Rect2i(-900,100,420,400);var extent=Vector2i(210,232)
	var point=Behavior.beside(anchor,bounds,extent,Vector2i(-1250,500))
	check(bounds.encloses(Rect2i(point,extent)) and not Rect2i(point,extent).intersects(anchor),"Negative-coordinate monitor placement avoids the work window")
	check(Behavior.beside(bounds,bounds,extent,Vector2i(-1250,500))==Vector2i(-1250,500),"No free flank means no pointless relocation")
	var app=root.get_node("App")
	check(Behavior.activity(app)=="idle","Quiet app has no synthetic task")
	app.goal_mode="proposal";check(Behavior.activity(app)=="wait","Approval produces a waiting pose")
	app.goal_mode="verifying";check(Behavior.activity(app)=="scan","Post-action verification produces a scanning pose")
	app.goal_mode="";app.window_read_mode="thinking";check(Behavior.activity(app)=="read","Read task is visually distinct from general chat")
	app.window_read_mode="";app.paused=true;check(Behavior.activity(app)=="sleep","Pause cannot look like active work")
	app.paused=false
	var rig=Rig.new();rig.texture=load("res://assets/characters/leemon_01/master_v1.png");rig.size=Vector2(210,232);root.add_child(rig);rig.set_process(false)
	check(Rig.CLIPS.size()==26 and rig.installed_clips==26,"Exactly 26 implemented procedural poses")
	var signatures={}
	for clip in Rig.CLIPS:
		rig.play(clip);rig._process(0.7)
		var pose=[]
		for key in rig.parts:
			var joint=rig.parts[key];pose.append([joint.position.snapped(Vector2(0.01,0.01)),snappedf(joint.rotation,0.0001),joint.scale])
		var signature=var_to_str(pose)
		check(not signatures.has(signature),"Pose has distinct evaluated transforms: "+clip)
		signatures[signature]=true
		rig._process(0.03)
		check(is_finite(rig.parts.head.rotation) and rig.parts.head.position.length()<2000,"Bounded finite pose "+clip)
	rig.set_reduced(true);rig._process(1)
	check(rig.parts.head.rotation==0 and rig.root_part.position==Vector2.ZERO,"Reduced motion returns to a stable neutral pose")
	rig.queue_free()
	print("BEHAVIOR_TESTS: %d checks, %d failures; geometry/poses, no Windows execution" %[checks,failures])
	quit(0 if failures==0 else 1)
