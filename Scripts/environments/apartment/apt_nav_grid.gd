extends Node

## Apartment "level" adapter for the existing cat actor (Scenes/Prototype3D/Cat3D.tscn +
## Scripts/prototype3d/MainLevelCat3D.gd). The cat's state machine only talks to its
## `level` through a small duck-typed API (map_to_world, is_walkable, build_path, ...);
## this node implements that API for the apartment floor so the real cafe cat behaviour
## (idle / wander / sit / sleep poses, facing, trust) runs unchanged at home.
##
## Differences from MainLevel3D:
## - no rest area (the whole flat is calm), no slots, no patrons;
## - get_overstim_pressure_near() reports zero pressure, plus "calm company" (count 1,
##   pressure 0) next to `company_points`, which makes a cat sit (INTERACTING) and slowly
##   gain trust: that is how the bonding spot works.

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var cell_size: float = 0.7
var cols: int = 14
var rows: int = 10
## World XZ of the floor's min corner (cell (0,0) starts here).
var origin := Vector2(-4.9, -3.5)
var blocked: Dictionary = {}
## Cells a cat should prefer to nap on etc. (filled by the apartment).
var rest_cells: Array[Vector2i] = []
## World points where a calm human is "keeping company" (bonding). Radius in meters.
var company_points: Array[Vector3] = []
var company_radius: float = 0.4

# Fields the cat reads with level.get(...).
var actor_y_offset: float = 0.0
var data: Dictionary = {}

var camera: Camera3D = null
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.seed = 4242

## blockers: Array of Rect2 in world XZ. A cell is blocked when its centre lies inside
## a blocker grown by `pad`.
func setup(p_origin: Vector2, p_cols: int, p_rows: int, p_cell: float, blockers: Array, pad: float = 0.12) -> void:
	origin = p_origin
	cols = p_cols
	rows = p_rows
	cell_size = p_cell
	blocked.clear()
	for gz in range(rows):
		for gx in range(cols):
			var c: Vector3 = map_to_world(Vector2i(gx, gz))
			var p := Vector2(c.x, c.z)
			for r in blockers:
				if (r as Rect2).grow(pad).has_point(p):
					blocked[Vector2i(gx, gz)] = true
					break

# --- grid -----------------------------------------------------------------------------

func get_active_camera() -> Camera3D:
	return camera

func map_to_world(g: Vector2i) -> Vector3:
	return Vector3(origin.x + (float(g.x) + 0.5) * cell_size, 0.0, origin.y + (float(g.y) + 0.5) * cell_size)

func world_to_map(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - origin.x) / cell_size)), int(floor((p.z - origin.y) / cell_size)))

func get_floor_world_bounds() -> Dictionary:
	return {"min_x": origin.x, "max_x": origin.x + cols * cell_size, "min_z": origin.y, "max_z": origin.y + rows * cell_size}

func is_in_cafe_floor(g: Vector2i) -> bool:
	return g.x >= 0 and g.y >= 0 and g.x < cols and g.y < rows

func is_in_rest_area(_g: Vector2i) -> bool:
	return false

func is_blocked(g: Vector2i) -> bool:
	return blocked.has(g)

func set_blocked(g: Vector2i, on: bool) -> void:
	if on:
		blocked[g] = true
	else:
		blocked.erase(g)

func is_walkable(g: Vector2i, _allow_rest: bool = false) -> bool:
	return is_in_cafe_floor(g) and not blocked.has(g)

func walkable_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for gz in range(rows):
		for gx in range(cols):
			var c := Vector2i(gx, gz)
			if is_walkable(c):
				out.append(c)
	return out

func random_cafe_cell() -> Vector2i:
	for _i in range(40):
		var c := Vector2i(rng.randi_range(0, cols - 1), rng.randi_range(0, rows - 1))
		if is_walkable(c):
			return c
	var all: Array[Vector2i] = walkable_cells()
	return all[rng.randi_range(0, all.size() - 1)] if not all.is_empty() else Vector2i.ZERO

func random_rest_cell() -> Vector2i:
	if rest_cells.is_empty():
		return random_cafe_cell()
	return rest_cells[rng.randi_range(0, rest_cells.size() - 1)]

func get_rest_exit_cell(from_grid: Vector2i) -> Vector2i:
	return nearest_walkable_cell(from_grid, false)

func get_rest_entry_cell(_from_grid: Vector2i) -> Vector2i:
	return random_rest_cell()

func nearest_walkable_cell(g: Vector2i, _allow_rest: bool = false) -> Vector2i:
	if is_walkable(g):
		return g
	var start := Vector2i(clampi(g.x, 0, cols - 1), clampi(g.y, 0, rows - 1))
	var visited: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if is_walkable(c):
			return c
		for d in DIRS4:
			var n: Vector2i = c + d
			if visited.has(n) or not is_in_cafe_floor(n):
				continue
			visited[n] = true
			queue.append(n)
	return g

## BFS path excluding start (same contract as MainLevel3D.build_path).
func build_path(start: Vector2i, goal: Vector2i, _allow_rest: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if start == goal or not is_walkable(goal):
		return result
	var came_from: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == goal:
			break
		for d in DIRS4:
			var n: Vector2i = cur + d
			if came_from.has(n) or not is_walkable(n):
				continue
			came_from[n] = cur
			queue.append(n)
	if not came_from.has(goal):
		return result
	var cursor: Vector2i = goal
	while cursor != start:
		result.push_front(cursor)
		cursor = came_from[cursor]
	return result

# --- perception / slots (no patrons at home) ------------------------------------------------

func get_overstim_pressure_near(world_pos: Vector3, _radius: float) -> Dictionary:
	var count: int = 0
	for p in company_points:
		if Vector2(p.x, p.z).distance_to(Vector2(world_pos.x, world_pos.z)) <= company_radius:
			count = 1
			break
	return {"count": count, "pressure": 0.0, "patrons": []}

func get_patrons_near(_world_pos: Vector3, _radius: float) -> int:
	return 0

func get_decor_effects_at(_g: Vector2i) -> Dictionary:
	return {}

func request_best_slot(_kind: StringName, _actor: Node3D, _from: Vector2i, _allow_rest: bool = false) -> int:
	return -1

func claim_slot(_slot_id: int, _actor: Node3D) -> bool:
	return false

func release_actor_slot(_actor: Node3D) -> void:
	pass

func has_slot(_slot_id: int) -> bool:
	return false

func get_slot_grid(_slot_id: int) -> Vector2i:
	return Vector2i.ZERO
