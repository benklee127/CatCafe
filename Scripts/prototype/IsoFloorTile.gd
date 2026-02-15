extends Node2D

var tile_texture: Texture2D
var tile_scale: float = 1.0
var cell_width: float = 64.0
var cell_height: float = 32.0
var block_height: float = 8.0
var side_left_color: Color = Color(0.44, 0.36, 0.24, 1.0)
var side_right_color: Color = Color(0.56, 0.45, 0.30, 1.0)

var _top_sprite: Sprite2D

func configure(texture: Texture2D, width: float, height: float, thickness: float, scale_value: float, left_color: Color, right_color: Color) -> void:
	tile_texture = texture
	cell_width = width
	cell_height = height
	block_height = thickness
	tile_scale = scale_value
	side_left_color = left_color
	side_right_color = right_color
	_ensure_top_sprite()
	queue_redraw()

func _ready() -> void:
	_ensure_top_sprite()

func _ensure_top_sprite() -> void:
	if _top_sprite == null:
		_top_sprite = get_node_or_null("Top")
	if _top_sprite == null:
		_top_sprite = Sprite2D.new()
		_top_sprite.name = "Top"
		add_child(_top_sprite)
	_top_sprite.texture = tile_texture
	_top_sprite.scale = Vector2(tile_scale, tile_scale)
	_top_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Raise top face so side faces are visible underneath.
	_top_sprite.position = Vector2(0, -block_height)

func _draw() -> void:
	var half_w: float = cell_width * 0.5
	var half_h: float = cell_height * 0.5
	var top_pt := Vector2(0, -half_h - block_height)
	var right_pt := Vector2(half_w, -block_height)
	var bottom_pt := Vector2(0, half_h - block_height)
	var left_pt := Vector2(-half_w, -block_height)

	var left_bottom := left_pt + Vector2(0, block_height)
	var bottom_bottom := bottom_pt + Vector2(0, block_height)
	var right_bottom := right_pt + Vector2(0, block_height)

	var left_face := PackedVector2Array([left_pt, bottom_pt, bottom_bottom, left_bottom])
	var right_face := PackedVector2Array([right_pt, bottom_pt, bottom_bottom, right_bottom])

	draw_colored_polygon(left_face, side_left_color)
	draw_colored_polygon(right_face, side_right_color)
