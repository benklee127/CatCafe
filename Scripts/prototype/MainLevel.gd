extends Node2D
class_name MainLevel

const CatScene = preload("res://Scenes/Prototype/Cat.tscn")
const HumanScene = preload("res://Scenes/Prototype/Human.tscn")
const MainLevelDecorScript = preload("res://Scripts/prototype/MainLevelDecor.gd")

@export var cell_width: float = 64.0
@export var cell_height: float = 32.0
@export var grid_origin: Vector2 = Vector2(512, 140)
@export var cafe_floor_rect: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(12, 10))
@export var rest_area_rect: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(4, 4))
@export var draw_debug_grid: bool = true
@export var cats_to_spawn: int = 1
@export var patrons_to_spawn: int = 3
@export var background_texture: Texture2D

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var hovered_grid: Vector2i = Vector2i.ZERO
var blocked_cells: Dictionary = {}
var decor_by_cell: Dictionary = {}
var interaction_slots: Dictionary = {}
var actor_slot_claims: Dictionary = {}
var slot_ids_by_decor: Dictionary = {}
var _next_slot_id: int = 1

@onready var background_sprite: Sprite2D = $Background
@onready var decor_layer: Node2D = $Actors/Decor
@onready var cats_layer: Node2D = $Actors/Cats
@onready var patrons_layer: Node2D = $Actors/Patrons

func _ready() -> void:
	rng.randomize()
	if background_texture != null:
		background_sprite.texture = background_texture
	for _i in range(cats_to_spawn):
		spawn_cat()
	for _i in range(patrons_to_spawn):
		spawn_patron()
	queue_redraw()

func _process(_delta: float) -> void:
	hovered_grid = world_to_map(get_global_mouse_position())
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_decor"):
		place_decor(hovered_grid)
	elif event.is_action_pressed("remove_decor"):
		remove_decor(hovered_grid)

func map_to_world(grid_pos: Vector2i) -> Vector2:
	var half_w: float = cell_width * 0.5
	var half_h: float = cell_height * 0.5
	var world_x: float = (grid_pos.x - grid_pos.y) * half_w
	var world_y: float = (grid_pos.x + grid_pos.y) * half_h
	return grid_origin + Vector2(world_x, world_y)

func world_to_map(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = world_pos - grid_origin
	var half_w: float = cell_width * 0.5
	var half_h: float = cell_height * 0.5
	var gx: int = floori((local.x / half_w + local.y / half_h) * 0.5)
	var gy: int = floori((local.y / half_h - local.x / half_w) * 0.5)
	return Vector2i(gx, gy)

func is_in_rest_area(grid_pos: Vector2i) -> bool:
	return rest_area_rect.has_point(grid_pos)

func is_in_cafe_floor(grid_pos: Vector2i) -> bool:
	return cafe_floor_rect.has_point(grid_pos)

func is_walkable(grid_pos: Vector2i, allow_rest_area: bool) -> bool:
	if is_blocked(grid_pos):
		return false
	if allow_rest_area and is_in_rest_area(grid_pos):
		return true
	return is_in_cafe_floor(grid_pos) and not is_in_rest_area(grid_pos)

func random_cafe_cell() -> Vector2i:
	return _random_walkable_cell(false, cafe_floor_rect)

func random_rest_cell() -> Vector2i:
	return _random_cell_in_rect(rest_area_rect)

func is_blocked(grid_pos: Vector2i) -> bool:
	return blocked_cells.has(grid_pos)

func set_blocked(grid_pos: Vector2i, blocked: bool) -> void:
	if blocked:
		blocked_cells[grid_pos] = true
	else:
		blocked_cells.erase(grid_pos)

func place_decor(grid_pos: Vector2i) -> bool:
	if not _can_place_decor(grid_pos):
		return false

	var decor: Node2D = MainLevelDecorScript.new()
	decor.name = "Decor_%d_%d" % [grid_pos.x, grid_pos.y]
	decor.call("configure", self, grid_pos)
	decor_layer.add_child(decor)
	decor_by_cell[grid_pos] = decor
	set_blocked(grid_pos, true)
	_register_decor_slots(decor, grid_pos)
	queue_redraw()
	return true

func remove_decor(grid_pos: Vector2i) -> bool:
	if not decor_by_cell.has(grid_pos):
		return false

	var decor: Node2D = decor_by_cell[grid_pos]
	_unregister_slots_for_decor(decor)
	decor_by_cell.erase(grid_pos)
	set_blocked(grid_pos, false)
	if is_instance_valid(decor):
		decor.queue_free()
	queue_redraw()
	return true

func request_best_slot(kind: StringName, actor: Node2D, from_grid: Vector2i, allow_rest_area: bool = false) -> int:
	var best_slot_id: int = -1
	var best_cost: int = 1_000_000
	for slot_id in interaction_slots.keys():
		var slot_data: Dictionary = interaction_slots[slot_id]
		if slot_data.get("kind", &"") != kind:
			continue
		if slot_data.get("claimed_by", null) != null:
			continue
		var slot_grid: Vector2i = slot_data.get("grid", Vector2i.ZERO)
		var path_cost: int = 0
		if slot_grid != from_grid:
			var path: Array[Vector2i] = build_path(from_grid, slot_grid, allow_rest_area)
			if path.is_empty():
				continue
			path_cost = path.size()
		if path_cost < best_cost:
			best_cost = path_cost
			best_slot_id = slot_id
	return best_slot_id

func claim_slot(slot_id: int, actor: Node2D) -> bool:
	if not interaction_slots.has(slot_id):
		return false
	var slot_data: Dictionary = interaction_slots[slot_id]
	var existing = slot_data.get("claimed_by", null)
	if existing != null and existing != actor:
		return false

	release_actor_slot(actor)
	slot_data["claimed_by"] = actor
	interaction_slots[slot_id] = slot_data
	actor_slot_claims[actor.get_instance_id()] = slot_id
	return true

func release_actor_slot(actor: Node2D) -> void:
	var actor_id: int = actor.get_instance_id()
	if not actor_slot_claims.has(actor_id):
		return
	var slot_id: int = actor_slot_claims[actor_id]
	actor_slot_claims.erase(actor_id)
	if not interaction_slots.has(slot_id):
		return
	var slot_data: Dictionary = interaction_slots[slot_id]
	if slot_data.get("claimed_by", null) == actor:
		slot_data["claimed_by"] = null
		interaction_slots[slot_id] = slot_data

func has_slot(slot_id: int) -> bool:
	return interaction_slots.has(slot_id)

func get_slot_grid(slot_id: int) -> Vector2i:
	if not interaction_slots.has(slot_id):
		return Vector2i(-9999, -9999)
	return interaction_slots[slot_id].get("grid", Vector2i(-9999, -9999))

func get_slot_world(slot_id: int) -> Vector2:
	if not interaction_slots.has(slot_id):
		return Vector2.ZERO
	var marker: Marker2D = interaction_slots[slot_id].get("marker", null)
	if marker == null:
		return map_to_world(get_slot_grid(slot_id))
	return marker.global_position

func get_patrons_near(world_pos: Vector2, radius: float) -> int:
	var count: int = 0
	for patron in patrons_layer.get_children():
		if patron is Node2D and (patron as Node2D).global_position.distance_to(world_pos) <= radius:
			count += 1
	return count

func spawn_cat() -> Node2D:
	var spawn_cell: Vector2i = random_cafe_cell()
	if is_in_rest_area(spawn_cell):
		spawn_cell = Vector2i(rest_area_rect.end.x + 1, rest_area_rect.end.y + 1)
		if not is_in_cafe_floor(spawn_cell):
			spawn_cell = Vector2i(cafe_floor_rect.position.x, cafe_floor_rect.position.y)

	var cat: Node2D = CatScene.instantiate()
	cat.name = "Cat_%d" % cats_layer.get_child_count()
	cat.call("configure", self, spawn_cell)
	cats_layer.add_child(cat)
	return cat

func spawn_patron() -> Node2D:
	var spawn_cell: Vector2i = random_cafe_cell()
	var patron: Node2D = HumanScene.instantiate()
	patron.name = "Patron_%d" % patrons_layer.get_child_count()
	patron.call("configure", self, spawn_cell)
	patrons_layer.add_child(patron)
	return patron

func build_path(start: Vector2i, goal: Vector2i, allow_rest_area: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if start == goal:
		return result
	if not is_walkable(start, true):
		return result
	if not is_walkable(goal, allow_rest_area):
		return result

	var queue: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var visited: Dictionary = {}
	visited[start] = true
	came_from[start] = start

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == goal:
			break
		for dir in directions:
			var next: Vector2i = current + dir
			if visited.has(next):
				continue
			if not is_walkable(next, allow_rest_area):
				continue
			visited[next] = true
			came_from[next] = current
			queue.push_back(next)

	if not came_from.has(goal):
		return result

	var cursor: Vector2i = goal
	while cursor != start:
		result.push_front(cursor)
		cursor = came_from[cursor]
	return result

func _random_cell_in_rect(rect: Rect2i) -> Vector2i:
	var min_x: int = rect.position.x
	var max_x: int = rect.end.x - 1
	var min_y: int = rect.position.y
	var max_y: int = rect.end.y - 1
	return Vector2i(rng.randi_range(min_x, max_x), rng.randi_range(min_y, max_y))

func _random_walkable_cell(allow_rest_area: bool, rect: Rect2i) -> Vector2i:
	for _attempt in range(64):
		var candidate: Vector2i = _random_cell_in_rect(rect)
		if is_walkable(candidate, allow_rest_area):
			return candidate
	return rect.position

func _can_place_decor(grid_pos: Vector2i) -> bool:
	if not is_walkable(grid_pos, false):
		return false
	return not decor_by_cell.has(grid_pos)

func _register_decor_slots(decor: Node2D, decor_cell: Vector2i) -> void:
	var slot_ids: Array[int] = []
	var patron_cell: Vector2i = _pick_slot_cell(decor_cell, [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)
	])
	var cat_cell: Vector2i = _pick_slot_cell(decor_cell, [
		Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)
	])

	var patron_marker: Marker2D = decor.get_node_or_null("PatronSlot")
	if patron_marker != null and patron_cell.x > -9000:
		slot_ids.append(_register_slot(&"patron", patron_cell, patron_marker, decor))

	var cat_marker: Marker2D = decor.get_node_or_null("CatSlot")
	if cat_marker != null and cat_cell.x > -9000:
		slot_ids.append(_register_slot(&"cat", cat_cell, cat_marker, decor))

	slot_ids_by_decor[decor.get_instance_id()] = slot_ids

func _register_slot(kind: StringName, slot_grid: Vector2i, marker: Marker2D, decor: Node2D) -> int:
	var slot_id: int = _next_slot_id
	_next_slot_id += 1
	interaction_slots[slot_id] = {
		"kind": kind,
		"grid": slot_grid,
		"marker": marker,
		"decor": decor,
		"claimed_by": null
	}
	return slot_id

func _unregister_slots_for_decor(decor: Node2D) -> void:
	var decor_id: int = decor.get_instance_id()
	if not slot_ids_by_decor.has(decor_id):
		return
	var slot_ids: Array = slot_ids_by_decor[decor_id]
	for slot_id_variant in slot_ids:
		var slot_id: int = int(slot_id_variant)
		if not interaction_slots.has(slot_id):
			continue
		var slot_data: Dictionary = interaction_slots[slot_id]
		var claimed_by = slot_data.get("claimed_by", null)
		if claimed_by != null and claimed_by is Node2D:
			actor_slot_claims.erase((claimed_by as Node2D).get_instance_id())
			if (claimed_by as Node2D).has_method("on_slot_invalidated"):
				(claimed_by as Node2D).call_deferred("on_slot_invalidated", slot_id)
		interaction_slots.erase(slot_id)
	slot_ids_by_decor.erase(decor_id)

func _pick_slot_cell(decor_cell: Vector2i, offsets: Array[Vector2i]) -> Vector2i:
	for offset in offsets:
		var cell: Vector2i = decor_cell + offset
		if is_walkable(cell, false):
			return cell
	return Vector2i(-9999, -9999)

func _draw() -> void:
	if not draw_debug_grid:
		return
	_draw_rect_outline(cafe_floor_rect, Color(0.1, 0.75, 0.95, 0.7))
	_draw_rect_outline(rest_area_rect, Color(0.95, 0.65, 0.15, 0.8))
	_draw_blocked_cells()
	_draw_slots()
	_draw_cell_hover(hovered_grid)

func _draw_rect_outline(rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell: Vector2i = Vector2i(x, y)
			var cell_color: Color = color
			cell_color.a = 0.08
			_draw_iso_cell(cell, cell_color)
			if x == rect.position.x or x == rect.end.x - 1 or y == rect.position.y or y == rect.end.y - 1:
				_draw_iso_cell_outline(cell, color)

func _draw_cell_hover(cell: Vector2i) -> void:
	var color: Color = Color(0.85, 0.95, 0.2, 0.75)
	if not is_walkable(cell, true):
		color = Color(1.0, 0.2, 0.2, 0.75)
	_draw_iso_cell_outline(cell, color)

func _draw_iso_cell(cell: Vector2i, color: Color) -> void:
	var half_w: float = cell_width * 0.5
	var half_h: float = cell_height * 0.5
	var c: Vector2 = map_to_world(cell)
	var points := PackedVector2Array([
		c + Vector2(0, -half_h),
		c + Vector2(half_w, 0),
		c + Vector2(0, half_h),
		c + Vector2(-half_w, 0)
	])
	draw_colored_polygon(points, color)

func _draw_iso_cell_outline(cell: Vector2i, color: Color) -> void:
	var half_w: float = cell_width * 0.5
	var half_h: float = cell_height * 0.5
	var c: Vector2 = map_to_world(cell)
	var points := PackedVector2Array([
		c + Vector2(0, -half_h),
		c + Vector2(half_w, 0),
		c + Vector2(0, half_h),
		c + Vector2(-half_w, 0),
		c + Vector2(0, -half_h)
	])
	draw_polyline(points, color, 2.0, true)

func _draw_blocked_cells() -> void:
	for cell_key in blocked_cells.keys():
		var cell: Vector2i = cell_key
		_draw_iso_cell(cell, Color(0.7, 0.2, 0.2, 0.22))
		_draw_iso_cell_outline(cell, Color(0.95, 0.25, 0.25, 0.9))

func _draw_slots() -> void:
	for slot_id in interaction_slots.keys():
		var slot_data: Dictionary = interaction_slots[slot_id]
		var marker: Marker2D = slot_data.get("marker", null)
		var slot_kind: StringName = slot_data.get("kind", &"")
		var world_pos: Vector2 = get_slot_world(slot_id)
		if marker != null:
			world_pos = marker.global_position
		var local_pos: Vector2 = to_local(world_pos)
		var color: Color = Color(0.25, 0.85, 0.95, 0.9) if slot_kind == &"patron" else Color(0.95, 0.85, 0.25, 0.9)
		if slot_data.get("claimed_by", null) != null:
			color = Color(0.45, 1.0, 0.45, 0.95)
		draw_circle(local_pos, 4.0, color)
