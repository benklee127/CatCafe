extends Node2D

## Screen-space position of tile (0,0). iso_to_world adds it, world_to_iso subtracts it.
const ORIGIN := Vector2(640, 150)

@export var tile_width: float = 64.0
@export var tile_height: float = 32.0
@export var max_x: int = 24
@export var max_y: int = 18

var placed_decor: Dictionary = {}

@onready var decor_layer: Node2D = get_parent().get_node("DecorLayer") as Node2D

func _unhandled_input(event: InputEvent) -> void:
	var mb_event := event as InputEventMouseButton
	if mb_event != null and mb_event.pressed:
		var tile: Vector2i = world_to_iso(get_global_mouse_position())
		if mb_event.button_index == MOUSE_BUTTON_LEFT:
			_try_place(tile)
		elif mb_event.button_index == MOUSE_BUTTON_RIGHT:
			_try_remove(tile)

## Inverse of iso_to_world. Tile centres map back to themselves; the +0.5 half-tile
## shift makes the whole diamond around a centre resolve to that tile.
func world_to_iso(pos: Vector2) -> Vector2i:
	var p: Vector2 = pos - ORIGIN
	var fx: float = (p.x / (tile_width * 0.5) + p.y / (tile_height * 0.5)) * 0.5
	var fy: float = (p.y / (tile_height * 0.5) - p.x / (tile_width * 0.5)) * 0.5
	return Vector2i(floori(fx + 0.5), floori(fy + 0.5))

func iso_to_world(tile: Vector2i) -> Vector2:
	var x: float = (tile.x - tile.y) * (tile_width * 0.5)
	var y: float = (tile.x + tile.y) * (tile_height * 0.5)
	return Vector2(x, y) + ORIGIN

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

## Run-state payload in the contract shape: {decor_id, anchor:[x,y], rotation}.
func get_placed_decor_payload() -> Array:
	var out: Array = []
	for key in placed_decor.keys():
		var entry: Dictionary = placed_decor[key]
		var t: Dictionary = entry.get("tile", {})
		out.append({
			"decor_id": String(entry.get("decor_id", "debug_chair")),
			"anchor": [int(t.get("x", 0)), int(t.get("y", 0))],
			"rotation": 0
		})
	return out

## Re-places decor from a saved payload. Accepts the contract shape
## ({anchor:[x,y]}) and the old legacy shape ({tile:{x,y}}).
func restore_placed_decor(payload: Array) -> void:
	for entry_variant in payload:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var tile := Vector2i(-1, -1)
		var anchor: Variant = entry.get("anchor", null)
		var legacy_tile: Variant = entry.get("tile", null)
		if anchor is Array and (anchor as Array).size() >= 2:
			tile = Vector2i(int(anchor[0]), int(anchor[1]))
		elif legacy_tile is Dictionary:
			tile = Vector2i(int(legacy_tile.get("x", -1)), int(legacy_tile.get("y", -1)))
		_try_place(tile)

func _draw() -> void:
	var rest_marker: Node2D = get_parent().get_node_or_null("RestArea") as Node2D
	if rest_marker != null:
		var rest_local: Vector2 = to_local(rest_marker.global_position)
		draw_circle(rest_local, 36.0, Color(0.62, 0.78, 0.64, 0.35))
		draw_arc(rest_local, 36.0, 0.0, TAU, 32, Color(0.45, 0.62, 0.48), 2.0)
	for child in decor_layer.get_children():
		if child is Node2D:
			var deco_node := child as Node2D
			draw_rect(Rect2(to_local(deco_node.global_position) - Vector2(12, 12), Vector2(24, 24)), Color(0.62, 0.62, 0.62))
