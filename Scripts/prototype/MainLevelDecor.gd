extends Node2D

const DECOR_TEXTURE: Texture2D = preload("res://Art_Assets/decor/export/decor_chair_placeholder_v001.png")

var level
var grid_position: Vector2i = Vector2i.ZERO
var _sprite: Sprite2D

func configure(main_level, at_grid: Vector2i) -> void:
	level = main_level
	grid_position = at_grid
	global_position = level.map_to_world(at_grid)
	z_index = int(global_position.y)
	_ensure_sprite()
	_ensure_marker("PatronSlot", Vector2(14, 8))
	_ensure_marker("CatSlot", Vector2(-14, 8))
	queue_redraw()

func _ready() -> void:
	_ensure_sprite()

func _ensure_sprite() -> void:
	if _sprite != null:
		return
	_sprite = get_node_or_null("Sprite2D")
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		add_child(_sprite)
	_sprite.texture = DECOR_TEXTURE
	_sprite.offset = Vector2(0, -8)

func _ensure_marker(node_name: String, local_position: Vector2) -> void:
	var marker: Marker2D = get_node_or_null(node_name)
	if marker == null:
		marker = Marker2D.new()
		marker.name = node_name
		add_child(marker)
	marker.position = local_position

func _draw() -> void:
	if _sprite != null:
		return
	var points := PackedVector2Array([
		Vector2(0, -14),
		Vector2(20, 0),
		Vector2(0, 12),
		Vector2(-20, 0)
	])
	draw_colored_polygon(points, Color(0.56, 0.56, 0.56, 0.95))
	draw_polyline(PackedVector2Array([
		Vector2(0, -14),
		Vector2(20, 0),
		Vector2(0, 12),
		Vector2(-20, 0),
		Vector2(0, -14)
	]), Color(0.18, 0.18, 0.18, 1.0), 2.0, true)
