extends Node2D

@export var tile_width: float = 64.0
@export var tile_height: float = 32.0
@export var max_x: int = 24
@export var max_y: int = 18

var placed_decor: Dictionary = {}

@onready var decor_layer: Node2D = get_parent().get_node("DecorLayer") as Node2D

func _unhandled_input(event: InputEvent) -> void:
	var mb_event := event as InputEventMouseButton
	if mb_event != null and mb_event.pressed:
		var tile: Vector2i = world_to_iso(mb_event.position)
		if mb_event.button_index == MOUSE_BUTTON_LEFT:
			_try_place(tile)
		elif mb_event.button_index == MOUSE_BUTTON_RIGHT:
			_try_remove(tile)

func world_to_iso(pos: Vector2) -> Vector2i:
	var gx: float = floorf((pos.x / (tile_width * 0.5) + pos.y / (tile_height * 0.5)) * 0.5)
	var gy: float = floorf((pos.y / (tile_height * 0.5) - pos.x / (tile_width * 0.5)) * 0.5)
	return Vector2i(int(gx), int(gy))

func iso_to_world(tile: Vector2i) -> Vector2:
	var x: float = (tile.x - tile.y) * (tile_width * 0.5)
	var y: float = (tile.x + tile.y) * (tile_height * 0.5)
	return Vector2(x + 640, y + 150)

func _try_place(tile: Vector2i) -> void:
	if not _in_bounds(tile):
		return
	var key: String = _tile_key(tile)
	if placed_decor.has(key):
		return

	var decor := Node2D.new()
	decor.name = "Chair_%s" % key
	decor.position = iso_to_world(tile)
	decor.set_meta("tile", tile)
	decor_layer.add_child(decor)
	placed_decor[key] = {
		"tile": {"x": tile.x, "y": tile.y},
		"decor_id": "debug_chair"
	}
	queue_redraw()

func _try_remove(tile: Vector2i) -> void:
	var key: String = _tile_key(tile)
	if not placed_decor.has(key):
		return
	for child in decor_layer.get_children():
		if child.get_meta("tile", Vector2i(-999, -999)) == tile:
			child.queue_free()
			break
	placed_decor.erase(key)
	queue_redraw()

func _in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < max_x and tile.y < max_y

func _tile_key(tile: Vector2i) -> String:
	return "%d_%d" % [tile.x, tile.y]

func get_placed_decor_payload() -> Array:
	var out: Array = []
	for key in placed_decor.keys():
		out.append(placed_decor[key])
	return out

func _draw() -> void:
	for child in decor_layer.get_children():
		if child is Node2D:
			var deco_node := child as Node2D
			draw_rect(Rect2(to_local(deco_node.global_position) - Vector2(12, 12), Vector2(24, 24)), Color(0.62, 0.62, 0.62))
