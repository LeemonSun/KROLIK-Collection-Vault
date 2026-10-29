extends RefCounted
## One Leemon palette: graphite, warm paper and amber.
const INK = Color('#17191d')
const PANEL = Color('#24272d')
const LAYER = Color('#30343b')
const TEXT = Color('#f5f0df')
const MUTED = Color('#b1b3ba')
const RED = Color('#f4c34d')
const AMBER_DARK = Color('#6a5427')
static func box(color, radius=14, margin=12):
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
	value.default_font_size=16
	value.default_font=load('res://assets/fonts/NotoSansCJKsc-Regular.otf')
	for type in ['Label','Button','CheckButton','OptionButton','LineEdit','TextEdit','RichTextLabel','PopupMenu']:
		value.set_color('font_color',type,TEXT)
		value.set_color('font_disabled_color',type,Color('#7b807e'))
		value.set_color('font_hover_color',type,Color.WHITE)
		value.set_color('font_pressed_color',type,Color.WHITE)
	for type in ['Button','OptionButton']:
		value.set_stylebox('normal',type,box(LAYER))
		value.set_stylebox('hover',type,box(Color('#3e3b30')))
		value.set_stylebox('pressed',type,box(AMBER_DARK))
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
		value.set_color('selection_color',type,AMBER_DARK)
		value.set_color('font_placeholder_color',type,Color('#999e95'))
	value.set_stylebox('panel','PopupMenu',box(PANEL,12))
	value.set_stylebox('hover','PopupMenu',box(AMBER_DARK,6,8))
	value.set_constant('v_separation','PopupMenu',12)
	value.set_stylebox('scroll','VScrollBar',box(Color('#1b1f21'),3,3))
	value.set_stylebox('grabber','VScrollBar',box(Color('#62675b'),3,3))
	value.set_stylebox('grabber_highlight','VScrollBar',box(RED,3,3))
	value.set_stylebox('grabber_pressed','VScrollBar',box(RED,3,3))
	for state in ['normal','hover','pressed','hover_pressed','disabled']:
		value.set_stylebox(state,'CheckButton',box(PANEL,12,12))
	value.set_color('button_checked_color','CheckButton',RED)
	value.set_constant('separation','VBoxContainer',10)
	value.set_color('font_color','RichTextLabel',TEXT)
	value.set_color('default_color','RichTextLabel',TEXT)
	return value
static func primary(button):
	button.add_theme_stylebox_override('normal',box(RED,14))
	button.add_theme_stylebox_override('hover',box(Color('#ffda76'),14))
	button.add_theme_stylebox_override('pressed',box(Color('#d4a439'),14))
	for kind in ['font_color','font_hover_color','font_pressed_color']:
		button.add_theme_color_override(kind,INK)
	for kind in ['icon_normal_color','icon_hover_color','icon_pressed_color']:
		button.add_theme_color_override(kind,INK)
static func quiet(button):
	button.add_theme_stylebox_override('normal',box(Color.TRANSPARENT,8,9))
	button.add_theme_stylebox_override('hover',box(LAYER,8,9))
