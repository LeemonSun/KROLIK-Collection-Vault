extends PanelContainer
## Original Leemon surface_style: quiet graphite, warm upper light and a citrus-ring signature.
const V=preload('res://src/ui/visual_theme.gd')
var inset=14
var surface_style
var header
func _ready():
	var empty=StyleBoxEmpty.new()
	empty.content_margin_left=inset;empty.content_margin_right=inset
	empty.content_margin_top=inset;empty.content_margin_bottom=inset
	add_theme_stylebox_override('panel',empty)
	surface_style=V.box(V.INK,16,0);surface_style.set_border_width_all(1);surface_style.border_color=Color('#3b403d')
	header=V.box(V.PANEL,15,0);header.corner_radius_bottom_left=0;header.corner_radius_bottom_right=0
	resized.connect(queue_redraw);mouse_filter=Control.MOUSE_FILTER_PASS
func _draw():
	if not surface_style:return
	draw_style_box(surface_style,Rect2(Vector2.ZERO,size))
	draw_style_box(header,Rect2(Vector2.ONE,Vector2(maxf(0,size.x-2),66)))
	draw_line(Vector2(18,67),Vector2(size.x-18,67),Color('#3b403a'),1,true)
	var origin=Vector2(size.x-30,size.y-28)
	draw_arc(origin,12,PI*0.15,PI*1.4,24,Color('#71613a'),1.2,true)
	draw_line(origin+Vector2(-3,-11),origin+Vector2(3,-14),V.RED,1.5,true)
