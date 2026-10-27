extends RefCounted
static func make():
	var value = Theme.new()
	value.default_font_size = 16
	value.default_font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	for type in ["Label","Button","CheckButton","OptionButton","LineEdit","TextEdit","RichTextLabel","PopupMenu"]:
		value.set_color("font_color",type,Color("#f4eaf2"))
	for type in ["Button","OptionButton"]:
		for state in ["normal","hover","pressed","focus"]:
			var box = StyleBoxFlat.new()
			box.bg_color = Color("#452636") if state in ["hover","pressed"] else Color("#2b2030")
			box.set_corner_radius_all(9)
			box.content_margin_left = 12
			box.content_margin_right = 12
			box.content_margin_top = 8
			box.content_margin_bottom = 8
			if state == "focus":
				box.set_border_width_all(1)
				box.border_color = Color("#ef7893")
			value.set_stylebox(state,type,box)
	for type in ["LineEdit","TextEdit"]:
		var box = StyleBoxFlat.new()
		box.bg_color = Color("#231b2a")
		box.set_corner_radius_all(8)
		box.set_border_width_all(1)
		box.border_color = Color("#644052")
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 9
		box.content_margin_bottom = 9
		value.set_stylebox("normal",type,box)
		value.set_stylebox("focus",type,box)
		value.set_color("caret_color",type,Color("#ff90aa"))
	return value
