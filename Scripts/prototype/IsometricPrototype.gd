extends MainLevel

const FLOOR_TILE_TEXTURE: Texture2D = preload("res://Art_Assets/tiles/export/tile_floor_seamless_v001.png")
const REST_TILE_TEXTURE: Texture2D = preload("res://Art_Assets/tiles/export/tile_rest_seamless_v001.png")
const IsoFloorTileScript = preload("res://Scripts/prototype/IsoFloorTile.gd")

@export var tile_draw_y_offset: float = 0.0
@export var floor_tile_scale: float = 1.0
@export var floor_tile_height: float = 8.0
@export var rest_tile_height: float = 14.0
@export var floor_left_side_color: Color = Color(0.42, 0.34, 0.22, 1.0)
@export var floor_right_side_color: Color = Color(0.56, 0.45, 0.30, 1.0)
@export var rest_left_side_color: Color = Color(0.56, 0.34, 0.16, 1.0)
@export var rest_right_side_color: Color = Color(0.72, 0.43, 0.20, 1.0)
@export var show_zone_overlays: bool = false
@export var room_area_tint: Color = Color(0.45, 0.75, 1.0, 0.10)
@export var rest_area_tint: Color = Color(1.0, 0.78, 0.35, 0.26)
@export var divider_color: Color = Color(0.95, 0.35, 0.25, 0.95)
@export var divider_width: float = 4.0

@onready var tile_layer: Node2D = $TileLayer

func _ready() -> void:
	draw_debug_grid = false
	_build_tile_layer()
	super._ready()

func _build_tile_layer() -> void:
	for child in tile_layer.get_children():
		child.queue_free()

	for y in range(cafe_floor_rect.position.y, cafe_floor_rect.end.y):
		for x in range(cafe_floor_rect.position.x, cafe_floor_rect.end.x):
			var grid_pos: Vector2i = Vector2i(x, y)
			var is_rest: bool = is_in_rest_area(grid_pos)
			var tile := Node2D.new()
			tile.set_script(IsoFloorTileScript)
			var texture: Texture2D = REST_TILE_TEXTURE if is_rest else FLOOR_TILE_TEXTURE
			var thickness: float = rest_tile_height if is_rest else floor_tile_height
			var left_color: Color = rest_left_side_color if is_rest else floor_left_side_color
			var right_color: Color = rest_right_side_color if is_rest else floor_right_side_color
			tile.call("configure", texture, cell_width, cell_height, thickness, floor_tile_scale, left_color, right_color)
			tile.position = map_to_world(grid_pos) + Vector2(0, tile_draw_y_offset)
			# Keep floor below actors while preserving iso overlap.
			tile.z_index = int(tile.position.y) - 200
			tile_layer.add_child(tile)

func _draw() -> void:
	if not show_zone_overlays:
		return
	_draw_area_rect(cafe_floor_rect, room_area_tint)
	_draw_area_rect(rest_area_rect, rest_area_tint)
	_draw_rest_boundary()

func _draw_area_rect(rect: Rect2i, tint: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_draw_iso_cell(Vector2i(x, y), tint)

func _draw_rest_boundary() -> void:
	var dirs := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]
	for y in range(rest_area_rect.position.y, rest_area_rect.end.y):
		for x in range(rest_area_rect.position.x, rest_area_rect.end.x):
			var rest_cell := Vector2i(x, y)
			for d in dirs:
				var neighbor: Vector2i = rest_cell + d
				if not is_in_cafe_floor(neighbor) or is_in_rest_area(neighbor):
					continue
				var a: Vector2 = map_to_world(rest_cell)
				var b: Vector2 = map_to_world(neighbor)
				var midpoint: Vector2 = (a + b) * 0.5
				var normal: Vector2 = (b - a).normalized()
				var tangent: Vector2 = Vector2(-normal.y, normal.x)
				var span: float = min(cell_width, cell_height) * 0.45
				draw_line(midpoint - tangent * span, midpoint + tangent * span, divider_color, divider_width, true)
