extends TextureRect
## Static runtime cutout; real body rig remains separate work.
static var cached_texture
func _ready():
	custom_minimum_size = Vector2(230, 330)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if cached_texture == null:
		cached_texture = load("res://assets/characters/signal_01/body_v1.png")
	texture = cached_texture
