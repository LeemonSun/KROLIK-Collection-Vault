extends Control
## One identity source, six articulated texture pieces, authored motion curves.
## No per-frame model inference or generated replacement faces.
const SOURCE_SIZE=Vector2(1199,1312)
const CLIPS=["idle","hello","thinking","talk","success","error","grab","walk","listen","stretch","settle","read","point","nod","shrug","rest"]
var texture:Texture2D
var parts={}
var pivots={}
var clip="idle"
var clip_time=0.0
var duration=0.0
var elapsed=0.0
var reduced=false
var root_part:Node2D
var installed_clips=16
var blend_from={}
var blend_time=1.0
func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	root_part=Node2D.new()
	add_child(root_part)
	# Polygons overlap only on suit seams, and keep all UVs in source pixel coordinates.
	_piece("leg_l",Vector2(486,1040),[Vector2(360,1009),Vector2(612,1009),Vector2(612,1312),Vector2(280,1312),Vector2(280,1180),Vector2(360,1090)],0)
	_piece("leg_r",Vector2(721,1040),[Vector2(612,1009),Vector2(875,1009),Vector2(875,1100),Vector2(950,1190),Vector2(950,1312),Vector2(612,1312)],0)
	_piece("arm_l",Vector2(355,772),[Vector2(0,700),Vector2(321,700),Vector2(410,814),Vector2(379,919),Vector2(374,1051),Vector2(0,1051)],1)
	_piece("arm_r",Vector2(854,772),[Vector2(877,702),Vector2(1199,702),Vector2(1199,1032),Vector2(882,1032),Vector2(870,960),Vector2(826,918),Vector2(811,858)],1)
	_piece("head",Vector2(603,728),[Vector2(0,0),Vector2(1199,0),Vector2(1199,707),Vector2(884,707),Vector2(869,719),Vector2(601,745),Vector2(340,688),Vector2(307,703),Vector2(0,703)],2)
	_piece("body",Vector2(600,1023),[Vector2(307,695),Vector2(343,681),Vector2(598,734),Vector2(874,689),Vector2(895,737),Vector2(835,902),Vector2(860,1009),Vector2(843,1035),Vector2(636,1055),Vector2(599,1030),Vector2(568,1055),Vector2(374,1035),Vector2(375,920),Vector2(404,817)],3)
	resized.connect(_fit)
	_fit()
func _piece(id,pivot,points,z):
	var joint=Node2D.new();joint.position=pivot;joint.z_index=z
	root_part.add_child(joint)
	var polygon=Polygon2D.new()
	polygon.texture=texture
	polygon.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var local=PackedVector2Array()
	for point in points:local.append(point-pivot)
	polygon.polygon=local
	polygon.uv=PackedVector2Array(points)
	joint.add_child(polygon)
	parts[id]=joint;pivots[id]=pivot
func _fit():
	if root_part:root_part.scale=size/SOURCE_SIZE
func play(id,seconds=0.0):
	if id not in CLIPS:return false
	if clip==id and id in ["thinking","grab","walk","listen","stretch","settle"]:return true
	blend_from={}
	if root_part:
		blend_from["root"]=root_part.position
		for part in parts:blend_from[part]=[parts[part].position,parts[part].rotation,parts[part].scale]
	blend_time=0
	clip=id;clip_time=0;duration=seconds
	return true
func set_reduced(value):
	reduced=value
	if reduced:_rest()
func _rest():
	if not root_part:return
	root_part.position=Vector2.ZERO
	for id in parts:
		parts[id].position=pivots[id];parts[id].rotation=0;parts[id].scale=Vector2.ONE
func _process(delta):
	if not root_part or not is_visible_in_tree():return
	elapsed+=delta;clip_time+=delta
	if reduced:return
	_rest()
	if duration>0 and clip_time>=duration:play("idle")
	var weight=smoothstep(0.0,0.25,clip_time)
	if duration>0:weight*=1.0-smoothstep(maxf(0,duration-0.35),duration,clip_time)
	# Feet remain fixed in idle; breathing is in the upper body, leaf and wrists.
	var breath=sin(elapsed*1.65)
	parts.head.position.y+=breath*2.8
	parts.head.rotation=sin(elapsed*0.48)*0.007
	parts.arm_l.rotation=sin(elapsed*1.2)*0.009
	parts.arm_r.rotation=-sin(elapsed*1.2)*0.009
	match clip:
		"hello":
			parts.arm_r.rotation=weight*(-0.88+sin(clip_time*12.0)*0.12)
			parts.head.rotation=-weight*0.035
		"thinking":
			parts.head.rotation=weight*(0.055+sin(clip_time*1.5)*0.012)
			parts.arm_r.rotation=-weight*0.19
			parts.arm_l.rotation=weight*0.08
		"talk":
			parts.head.rotation=weight*sin(clip_time*3.3)*0.025
			parts.arm_r.rotation=weight*(-0.18+sin(clip_time*3.0)*0.08)
		"success":
			root_part.position.y=-sin(minf(1.0,clip_time/0.8)*PI)*7.0*weight
			parts.arm_l.rotation=weight*0.45;parts.arm_r.rotation=-weight*0.45
			parts.head.rotation=weight*sin(clip_time*5.0)*0.025
		"error":
			parts.head.rotation=weight*0.07
			parts.arm_l.rotation=weight*0.18;parts.arm_r.rotation=-weight*0.18
		"grab":
			parts.arm_l.rotation=weight*0.25;parts.arm_r.rotation=-weight*0.25
			parts.leg_l.rotation=sin(clip_time*4)*0.05
			parts.leg_r.rotation=-sin(clip_time*4)*0.05
		"listen":
			parts.head.rotation=-0.025*weight+sin(elapsed*0.7)*0.009
			parts.arm_l.rotation=0.05*weight
		"stretch":
			var stretch=sin(minf(clip_time/1.8,1.0)*PI)*weight
			parts.arm_l.rotation=stretch*0.42;parts.arm_r.rotation=-stretch*0.42
			parts.head.position.y-=stretch*7
		"settle":
			var spring=sin(clip_time*16)*exp(-clip_time*5)
			parts.head.position.y+=spring*9
			parts.body.scale.y=1+spring*0.015
			parts.arm_l.rotation=spring*0.16;parts.arm_r.rotation=-spring*0.16
		"read":
			parts.head.rotation=weight*0.045;parts.head.position.y+=weight*4
			parts.arm_l.rotation=weight*0.1;parts.arm_r.rotation=-weight*0.12
		"point":
			parts.arm_r.rotation=weight*(-0.6+sin(clip_time*2.8)*0.025)
			parts.head.rotation=-weight*0.035
		"nod":
			parts.head.position.y+=sin(minf(clip_time/0.75,1.0)*TAU)*5*weight
			parts.head.rotation=sin(minf(clip_time/0.75,1.0)*TAU)*0.025*weight
		"shrug":
			parts.arm_l.rotation=0.32*weight;parts.arm_r.rotation=-0.32*weight
			parts.head.rotation=-0.04*weight
		"rest":
			parts.head.rotation=0.055*weight
			parts.head.position.y+=5*weight;parts.arm_l.rotation=0.025*weight
		"walk":
			var step=sin(clip_time*10.5)*weight
			parts.leg_l.rotation=step*0.095;parts.leg_r.rotation=-step*0.095
			parts.arm_l.rotation=-step*0.06;parts.arm_r.rotation=step*0.06
			root_part.position.y=-absf(step)*3.0
			parts.head.position.y+=sin(clip_time*10.5)*1.4
	# Blend between authored poses over 180ms, including interruption/cancellation.
	blend_time+=delta
	var blend=smoothstep(0.0,0.18,blend_time)
	if blend<1 and not blend_from.is_empty():
		root_part.position=Vector2(blend_from.get("root",Vector2.ZERO)).lerp(root_part.position,blend)
		for id in parts:
			if blend_from.has(id):
				parts[id].position=Vector2(blend_from[id][0]).lerp(parts[id].position,blend)
				parts[id].rotation=lerp_angle(float(blend_from[id][1]),parts[id].rotation,blend)
				parts[id].scale=Vector2(blend_from[id][2]).lerp(parts[id].scale,blend)
	else:blend_from={}
func map_outline(point):
	var source=point*SOURCE_SIZE
	var id="body"
	if source.y<707:id="head"
	elif source.y>1040:id="leg_l" if source.x<612 else "leg_r"
	elif source.x<374:id="arm_l"
	elif source.x>846:id="arm_r"
	return (parts[id].transform*(source-pivots[id]))*root_part.scale+root_part.position

func hit_envelope(source_outline):
	# Precompute an input/render envelope for all current clips. Windows clips pixels
	# outside this region, so a moving region causes redraws and limb cut-offs.
	var saved=[clip,clip_time,duration,elapsed,reduced,blend_from.duplicate(true),blend_time]
	reduced=false
	var cloud=PackedVector2Array()
	for id in CLIPS:
		play(id)
		for step in range(12):
			_process(0.12)
			for point in source_outline:
				var mapped=map_outline(point)
				for offset in [Vector2(-12,-12),Vector2(12,-12),Vector2(12,12),Vector2(-12,12)]:
					cloud.append((mapped+offset).clamp(Vector2.ZERO,size))
	clip=saved[0];clip_time=saved[1];duration=saved[2];elapsed=saved[3];reduced=saved[4];blend_from=saved[5];blend_time=saved[6]
	_rest()
	return Geometry2D.convex_hull(cloud)
