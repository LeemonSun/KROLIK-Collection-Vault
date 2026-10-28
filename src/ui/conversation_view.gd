extends ScrollContainer
## Incremental conversation cards. Plain selectable text; app messages never become BBCode.
const V=preload("res://src/ui/visual_theme.gd")
var scroll_active=true
var rows
var entries=[]
var user_title=""
var follow_pending=false
var follow_start=false
func _ready():
	horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",14);add_child(rows)
func get_parsed_text():
	var texts=PackedStringArray()
	for item in entries:texts.append(str(item.text))
	return "\n".join(texts)
func set_messages(items,title):
	if not is_instance_valid(rows):return
	var bar=get_v_scroll_bar()
	var follow=entries.is_empty() or bar.value+bar.page>=bar.max_value-28
	var prefix=title==user_title and items.size()>=entries.size()
	if prefix:
		for index in range(entries.size()):
			if entries[index]!=items[index]:prefix=false;break
	if not prefix:
		for child in rows.get_children():rows.remove_child(child);child.queue_free()
		entries=[]
	user_title=title
	for index in range(entries.size(),items.size()):
		var item=items[index]
		_card(item,index==items.size()-1 and prefix)
		entries.append(item.duplicate(true))
	if follow and not follow_pending:
		follow_pending=true;_follow.call_deferred()
func _card(item,animate):
	var user=item.speaker=="user"
	var line=HBoxContainer.new();line.add_theme_constant_override("separation",16)
	rows.add_child(line)
	if user:
		var spacer=Control.new();spacer.custom_minimum_size.x=12;line.add_child(spacer)
	var card=PanelContainer.new();card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var style=V.box(Color("#292d2d") if user else Color("#1d2223"),12,14)
	style.content_margin_top=11;style.content_margin_bottom=13
	if not user:style.border_width_left=2;style.border_color=Color("#8c753e")
	card.add_theme_stylebox_override("panel",style);line.add_child(card)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",6);card.add_child(column)
	var heading=HBoxContainer.new();column.add_child(heading)
	var label=Label.new();label.text=user_title if user else "LEEMON"
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",10)
	label.add_theme_color_override("font_color",V.MUTED if user else V.RED);heading.add_child(label)
	var copy=Button.new();copy.tooltip_text=get_tree().root.get_node("App").t("copy");copy.icon=load("res://assets/ui/copy.svg");copy.expand_icon=true
	copy.add_theme_constant_override("icon_max_width",12);copy.custom_minimum_size=Vector2(22,20)
	V.quiet(copy);copy.add_theme_stylebox_override("normal",V.box(Color.TRANSPARENT,6,4));copy.add_theme_stylebox_override("hover",V.box(V.LAYER,6,4));copy.pressed.connect(func():DisplayServer.clipboard_set(item.text));heading.add_child(copy)
	var body=RichTextLabel.new();body.bbcode_enabled=false;body.selection_enabled=true
	body.scroll_active=false;body.fit_content=true;body.text=item.text
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size",15)
	body.add_theme_color_override("default_color",V.TEXT)
	body.add_theme_constant_override("line_separation",4);column.add_child(body)
	if animate and is_visible_in_tree():
		card.modulate.a=0.45
		var app=get_tree().root.get_node("App")
		if not app.paused and not app.motion.reduced_motion:create_tween().tween_property(card,"modulate:a",1.0,0.18)
		else:card.modulate.a=1.0
func _follow():
	if not is_inside_tree():return
	var tree=get_tree()
	await tree.process_frame
	if not is_inside_tree():return
	await tree.process_frame
	if not is_inside_tree():return
	await tree.process_frame
	if not is_inside_tree():return
	scroll_vertical=int(rows.get_child(rows.get_child_count()-1).position.y) if follow_start and rows.get_child_count()>0 else int(get_v_scroll_bar().max_value)
	follow_start=false;follow_pending=false

func follow_latest():
	if not follow_pending:
		follow_pending=true;_follow.call_deferred()

func reveal_latest():
	follow_start=true
	if not follow_pending:
		follow_pending=true;_follow.call_deferred()
