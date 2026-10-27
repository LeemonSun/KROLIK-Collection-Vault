extends RefCounted
## Original Signal palette: ink, silver, porcelain, wine and a red action signal.
const INK = Color('#151719')
const PANEL = Color('#202326')
const LAYER = Color('#2b2f32')
const TEXT = Color('#f3f0e5')
const MUTED = Color('#adafa6')
const RED = Color('#f5c64f')
const WINE = Color('#6a5427')
static func box(color, radius=10, margin=12):
	var style=StyleBoxFlat.new()
	style.bg_color=color
	style.set_corner_radius_all(radius)
	style.content_margin_left=margin
	style.content_margin_right=margin
	style.content_margin_top=8
	style.content_margin_bottom=8
	return style
static func make():
	var value=Theme.new()
	value.default_font_size=15
	value.default_font=load('res://assets/fonts/NotoSansCJKsc-Regular.otf')
	for type in ['Label','Button','CheckButton','OptionButton','LineEdit','TextEdit','RichTextLabel','PopupMenu']:
		value.set_color('font_color',type,TEXT)
		value.set_color('font_disabled_color',type,Color('#7b807e'))
		value.set_color('font_hover_color',type,Color.WHITE)
		value.set_color('font_pressed_color',type,Color.WHITE)
	for type in ['Button','OptionButton']:
		value.set_stylebox('normal',type,box(LAYER))
		value.set_stylebox('hover',type,box(Color('#3e3b30')))
		value.set_stylebox('pressed',type,box(WINE))
		value.set_stylebox('disabled',type,box(Color('#242729')))
		var focus=box(Color.TRANSPARENT)
		focus.set_border_width_all(1)
		focus.border_color=RED
		value.set_stylebox('focus',type,focus)
		value.set_constant('h_separation',type,9)
	for type in ['LineEdit','TextEdit']:
		var normal=box(Color('#111416'),10)
		normal.set_border_width_all(1)
		normal.border_color=Color('#494b42')
		value.set_stylebox('normal',type,normal)
		var focus=normal.duplicate()
		focus.border_color=RED
		value.set_stylebox('focus',type,focus)
		value.set_color('caret_color',type,RED)
		value.set_color('selection_color',type,WINE)
		value.set_color('font_placeholder_color',type,Color('#999e95'))
	value.set_stylebox('panel','PopupMenu',box(PANEL,12))
	value.set_stylebox('hover','PopupMenu',box(WINE,6,8))
	value.set_constant('v_separation','PopupMenu',12)
	value.set_stylebox('scroll','VScrollBar',box(Color('#1b1f21'),3,0))
	value.set_stylebox('grabber','VScrollBar',box(Color('#62675b'),3,0))
	value.set_stylebox('grabber_highlight','VScrollBar',box(RED,3,0))
	value.set_stylebox('grabber_pressed','VScrollBar',box(RED,3,0))
	value.set_constant('separation','VBoxContainer',10)
	value.set_color('font_color','RichTextLabel',TEXT)
	value.set_color('default_color','RichTextLabel',TEXT)
	return value
static func primary(button):
	button.add_theme_stylebox_override('normal',box(WINE,10))
	button.add_theme_stylebox_override('hover',box(Color('#8b6d2c'),10))
	button.add_theme_stylebox_override('pressed',box(Color('#a38237'),10))
static func quiet(button):
	button.add_theme_stylebox_override('normal',box(Color.TRANSPARENT,8,9))
	button.add_theme_stylebox_override('hover',box(LAYER,8,9))
