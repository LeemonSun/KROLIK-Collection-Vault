extends PanelContainer
## Drawn locally: cut corners, a signal seam and restrained material layers.
const V=preload('res://src/ui/visual_theme.gd')
var inset=14
func _ready():
	var empty=StyleBoxEmpty.new()
	empty.content_margin_left=inset
	empty.content_margin_right=inset
	empty.content_margin_top=inset
	empty.content_margin_bottom=inset
	add_theme_stylebox_override('panel',empty)
	resized.connect(queue_redraw)
	mouse_filter=Control.MOUSE_FILTER_PASS
func _draw():
	var w=size.x
	var h=size.y
	var outline=PackedVector2Array([Vector2(0,10),Vector2(10,0),Vector2(w-26,0),Vector2(w,26),Vector2(w,h-10),Vector2(w-10,h),Vector2(22,h),Vector2(0,h-22)])
	draw_colored_polygon(outline,V.INK)
	draw_colored_polygon(PackedVector2Array([Vector2(1,11),Vector2(11,1),Vector2(w-27,1),Vector2(w-2,26),Vector2(w-2,70),Vector2(1,70)]),V.PANEL)
	draw_line(Vector2(16,1),Vector2(w-32,1),Color('#4f5146'),1,true)
	draw_line(Vector2(1,78),Vector2(1,h-32),Color('#44483e'),1,true)
	draw_line(Vector2(w-25,2),Vector2(w-2,25),V.RED,2,true)
	draw_line(Vector2(2,h-21),Vector2(21,h-2),V.RED,2,true)
	for i in range(3):
		draw_line(Vector2(w-48-i*7,h-5),Vector2(w-45-i*7,h-10),Color('#696449'),1,true)
