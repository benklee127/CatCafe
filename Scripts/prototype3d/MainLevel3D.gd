extends Node3D
class_name MainLevel3D

const GridIso3DScript = preload("res://Scripts/prototype3d/GridIso3D.gd")
const Cat3DScene = preload("res://Scenes/Prototype3D/Cat3D.tscn")
const Human3DScene = preload("res://Scenes/Prototype3D/Human3D.tscn")

@export var cell_width_3d: float = 1.25
@export var cell_depth_3d: float = 1.25
@export var grid_origin_3d: Vector3 = Vector3(-7.5, 0.0, -6.0)
@export var mini_tiles_per_axis: int = 2
@export var auto_center_grid_origin: bool = true
@export var grid_center_world: Vector3 = Vector3.ZERO
@export var auto_size_cells_to_target: bool = true
@export var target_floor_world_size: Vector2 = Vector2(18.0, 14.0)
@export var enforce_square_cells: bool = true
@export var floor_tile_gap_ratio: float = 0.0
@export var show_grid_lines: bool = true
@export var grid_line_width_ratio: float = 0.04
@export var grid_line_height_offset: float = 0.01
@export var grid_line_color: Color = Color(0.72, 0.66, 0.55, 1.0)
@export var strict_blocking_from_mesh_bounds: bool = true
@export var block_back_wall_edge_cells: bool = false
@export var block_north_wall_edge: bool = true
@export var block_west_wall_edge: bool = true
@export var cafe_floor_rect: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(12, 10))
@export var rest_area_rect: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(4, 4))
@export var cats_to_spawn: int = 1
@export var patrons_to_spawn: int = 3
@export var floor_tile_height_3d: float = 0.28
@export var rest_tile_height_3d: float = 0.45
@export var actor_y_offset: float = 0.35
@export var iso_yaw_degrees: float = 45.0
@export var iso_pitch_degrees: float = 35.264
@export var iso_distance_multiplier: float = 1.9
@export var iso_vertical_padding: float = 4.0
@export var iso_viewport_margin_ratio: float = 0.08

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var data: Dictionary = {}
var decor_data_by_id: Dictionary = {}
var decor_ui_by_id: Dictionary = {}
var decor_mesh_by_id: Dictionary = {}

var blocked_cells: Dictionary = {}
var decor_instances: Dictionary = {}
var decor_anchor_by_cell: Dictionary = {}
var _grid_subdivision_applied: bool = false

@onready var data_loader: Node = $DataLoader
@onready var floor_grid: Node3D = $WorldRoot/FloorGrid
@onready var decor_layer: Node3D = $WorldRoot/DecorLayer3D
@onready var actor_root: Node3D = $WorldRoot/ActorLayer3D
@onready var cat_layer: Node3D = $WorldRoot/ActorLayer3D/CatLayer
@onready var patron_layer: Node3D = $WorldRoot/ActorLayer3D/PatronLayer
@onready var slot_manager: Node = $SlotManager3D
@onready var camera: Camera3D = $CameraRig/Camera3D

func _ready() -> void:
	rng.randomize()
	_apply_grid_subdivision()
	_apply_floor_layout_settings()
	_load_data()
	floor_grid.call("rebuild", self)
	_frame_camera_to_floor()
	_spawn_actors()

func get_active_camera() -> Camera3D:
	return camera

func map_to_world(grid_pos: Vector2i) -> Vector3:
	return GridIso3DScript.map_to_world(grid_pos, grid_origin_3d, cell_width_3d, cell_depth_3d)

func world_to_map(world_pos: Vector3) -> Vector2i:
	return GridIso3DScript.world_to_map(world_pos, grid_origin_3d, cell_width_3d, cell_depth_3d)

func get_floor_world_bounds() -> Dictionary:
	var min_cell: Vector2i = cafe_floor_rect.position
	var max_cell: Vector2i = cafe_floor_rect.end - Vector2i.ONE
	var a: Vector3 = map_to_world(min_cell)
	var b: Vector3 = map_to_world(max_cell)
	return {
		"min_x": minf(a.x, b.x) - cell_width_3d * 0.5,
		"max_x": maxf(a.x, b.x) + cell_width_3d * 0.5,
		"min_z": minf(a.z, b.z) - cell_depth_3d * 0.5,
		"max_z": maxf(a.z, b.z) + cell_depth_3d * 0.5
	}

func rotate_offset(offset: Vector2i, rotation_deg: int) -> Vector2i:
	var rot: int = _normalize_rotation(rotation_deg)
	match rot:
		90:
			return Vector2i(-offset.y, offset.x)
		180:
			return Vector2i(-offset.x, -offset.y)
		270:
			return Vector2i(offset.y, -offset.x)
		_:
			return offset

func is_in_rest_area(grid_pos: Vector2i) -> bool:
	return rest_area_rect.has_point(grid_pos)

func is_in_cafe_floor(grid_pos: Vector2i) -> bool:
	return cafe_floor_rect.has_point(grid_pos)

func is_walkable(grid_pos: Vector2i, allow_rest_area: bool) -> bool:
	if is_blocked(grid_pos):
		return false
	if _is_blocked_by_back_wall(grid_pos):
		return false
	if allow_rest_area and is_in_rest_area(grid_pos):
		return true
	return is_in_cafe_floor(grid_pos) and not is_in_rest_area(grid_pos)

func is_blocked(grid_pos: Vector2i) -> bool:
	return blocked_cells.has(_cell_key(grid_pos))

func set_blocked(grid_pos: Vector2i, blocked: bool) -> void:
	var key: String = _cell_key(grid_pos)
	if blocked:
		blocked_cells[key] = true
	else:
		blocked_cells.erase(key)

func random_cafe_cell() -> Vector2i:
	return _random_walkable_cell(false, cafe_floor_rect)

func random_rest_cell() -> Vector2i:
	return _random_cell_in_rect(rest_area_rect)

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
	visited[_cell_key(start)] = true
	came_from[_cell_key(start)] = start

	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == goal:
			break
		for d in directions:
			var next: Vector2i = current + d
			var next_key: String = _cell_key(next)
			if visited.has(next_key):
				continue
			if not is_walkable(next, allow_rest_area):
				continue
			visited[next_key] = true
			came_from[next_key] = current
			queue.push_back(next)

	if not came_from.has(_cell_key(goal)):
		return result

	var cursor: Vector2i = goal
	while cursor != start:
		result.push_front(cursor)
		cursor = came_from[_cell_key(cursor)]
	return result

func can_place_decor(anchor_grid: Vector2i, decor_id: String, rotation_deg: int) -> bool:
	return get_place_block_reason(anchor_grid, decor_id, rotation_deg).is_empty()

func get_place_block_reason(anchor_grid: Vector2i, decor_id: String, rotation_deg: int) -> String:
	var mesh_entry: Dictionary = decor_mesh_by_id.get(decor_id, {})
	if mesh_entry.is_empty():
		return "missing_mesh_map"
	var allowed: Array = mesh_entry.get("rotations", [])
	var rot: int = _normalize_rotation(rotation_deg)
	if not _is_rotation_allowed(allowed, rot):
		return "rotation_not_allowed"

	var footprint: Array = _occupied_cells(anchor_grid, mesh_entry, rot)
	for cell in footprint:
		var c: Vector2i = cell
		if not is_in_cafe_floor(c):
			return "out_of_cafe_floor:%s" % str(c)
		if _is_blocked_by_back_wall(c):
			return "blocked_by_back_wall:%s" % str(c)
		if is_in_rest_area(c):
			return "inside_rest_area:%s" % str(c)
		if decor_anchor_by_cell.has(_cell_key(c)):
			return "occupied_by_decor:%s" % str(c)
		var decor_def: Dictionary = decor_data_by_id.get(decor_id, {})
		var walkable: bool = bool(decor_def.get("placement", {}).get("walkable", false))
		if not walkable and is_blocked(c):
			return "blocked_cell:%s" % str(c)
	return ""

func place_decor(anchor_grid: Vector2i, decor_id: String, rotation_deg: int) -> bool:
	if not can_place_decor(anchor_grid, decor_id, rotation_deg):
		return false

	var mesh_entry: Dictionary = decor_mesh_by_id[decor_id]
	var rot: int = _normalize_rotation(rotation_deg)
	var decor_scene_path: String = mesh_entry.get("mesh_scene", "")
	if decor_scene_path.is_empty():
		return false
	var packed: PackedScene = load(decor_scene_path)
	if packed == null:
		push_error("Decor scene missing: %s" % decor_scene_path)
		return false

	var decor_instance: Node3D = packed.instantiate()
	decor_instance.name = "%s_%s" % [decor_id, _cell_key(anchor_grid)]
	decor_instance.position = get_decor_world_position(anchor_grid, decor_id, rot)
	decor_instance.rotation_degrees = Vector3(0.0, float(rot), 0.0)
	decor_layer.add_child(decor_instance)

	var footprint: Array = _occupied_cells(anchor_grid, mesh_entry, rot)
	var anchor_key: String = _cell_key(anchor_grid)
	var decor_def: Dictionary = decor_data_by_id.get(decor_id, {})
	var walkable: bool = bool(decor_def.get("placement", {}).get("walkable", false))
	for cell in footprint:
		var c: Vector2i = cell
		decor_anchor_by_cell[_cell_key(c)] = anchor_key
		if not walkable:
			set_blocked(c, true)

	var slot_ids: Array[int] = _register_decor_slots(anchor_grid, mesh_entry, rot, anchor_key)
	decor_instances[anchor_key] = {
		"node": decor_instance,
		"decor_id": decor_id,
		"rotation": rot,
		"walkable": walkable,
		"occupied": footprint,
		"slot_ids": slot_ids
	}
	return true

func remove_decor(any_cell: Vector2i) -> bool:
	var cell_key: String = _cell_key(any_cell)
	if not decor_anchor_by_cell.has(cell_key):
		return false
	var anchor_key: String = decor_anchor_by_cell[cell_key]
	if not decor_instances.has(anchor_key):
		return false
	var rec: Dictionary = decor_instances[anchor_key]
	var walkable: bool = bool(rec.get("walkable", false))
	for cell in rec.get("occupied", []):
		var c: Vector2i = cell
		decor_anchor_by_cell.erase(_cell_key(c))
		if not walkable:
			set_blocked(c, false)

	slot_manager.call("remove_slots", rec.get("slot_ids", []))
	var n: Node3D = rec.get("node", null)
	if n != null and is_instance_valid(n):
		n.queue_free()
	decor_instances.erase(anchor_key)
	return true

func get_available_decor_ids() -> Array[String]:
	var out: Array[String] = []
	for key in decor_mesh_by_id.keys():
		var id: String = String(key)
		if not id.is_empty():
			out.append(id)
	out.sort()
	return out

func get_decor_inspection_data(grid_pos: Vector2i) -> Dictionary:
	var anchor_key: String = decor_anchor_by_cell.get(_cell_key(grid_pos), "")
	if anchor_key.is_empty():
		return {}
	var rec: Dictionary = decor_instances.get(anchor_key, {})
	if rec.is_empty():
		return {}
	var decor_id: String = String(rec.get("decor_id", ""))
	var ui: Dictionary = decor_ui_by_id.get(decor_id, {})
	var mesh_map: Dictionary = decor_mesh_by_id.get(decor_id, {})
	return {
		"id": decor_id,
		"name": String(ui.get("name", decor_id.capitalize())),
		"color": String(ui.get("color", "Unknown")),
		"durability": int(ui.get("durability", 100)),
		"mesh_scene": String(mesh_map.get("mesh_scene", ""))
	}

func get_decor_blocking_cells(anchor_grid: Vector2i, decor_id: String, rotation_deg: int) -> Array[Vector2i]:
	var mesh_entry: Dictionary = decor_mesh_by_id.get(decor_id, {})
	if mesh_entry.is_empty():
		return []
	var rot: int = _normalize_rotation(rotation_deg)
	var raw: Array[Vector2i] = _occupied_cells(anchor_grid, mesh_entry, rot)
	var out: Array[Vector2i] = []
	for cell in raw:
		out.append(cell)
	return out

func get_decor_world_position(anchor_grid: Vector2i, decor_id: String, rotation_deg: int) -> Vector3:
	var mesh_entry: Dictionary = decor_mesh_by_id.get(decor_id, {})
	if mesh_entry.is_empty():
		return map_to_world(anchor_grid)
	var rot: int = _normalize_rotation(rotation_deg)
	var pivot: Vector3 = _array_to_vec3(mesh_entry.get("pivot_offset", [0, 0, 0]))
	var center_offset: Vector3 = _footprint_world_center_offset(mesh_entry, rot, true)
	return map_to_world(anchor_grid) + center_offset + pivot

func request_best_slot(kind: StringName, actor: Node3D, from_grid: Vector2i, allow_rest_area: bool = false) -> int:
	return int(slot_manager.call("request_best_slot", kind, actor, from_grid, self, allow_rest_area))

func claim_slot(slot_id: int, actor: Node3D) -> bool:
	return bool(slot_manager.call("claim_slot", slot_id, actor))

func release_actor_slot(actor: Node3D) -> void:
	slot_manager.call("release_actor_slot", actor)

func has_slot(slot_id: int) -> bool:
	return bool(slot_manager.call("has_slot", slot_id))

func get_slot_grid(slot_id: int) -> Vector2i:
	return slot_manager.call("get_slot_grid", slot_id)

func get_slot_world(slot_id: int) -> Vector3:
	return slot_manager.call("get_slot_world", slot_id)

func get_patrons_near(world_pos: Vector3, radius: float) -> int:
	var count: int = 0
	for p in patron_layer.get_children():
		if p is Node3D:
			var pos: Vector3 = (p as Node3D).global_position
			if Vector2(pos.x, pos.z).distance_to(Vector2(world_pos.x, world_pos.z)) <= radius:
				count += 1
	return count

func _load_data() -> void:
	if data_loader != null and data_loader.has_method("load_all_data"):
		data = data_loader.load_all_data()
	else:
		data = {}
	for d in data.get("decor", []):
		if typeof(d) == TYPE_DICTIONARY:
			decor_data_by_id[d.get("id", "")] = d
	for u in data.get("decor_ui", []):
		if typeof(u) == TYPE_DICTIONARY:
			decor_ui_by_id[u.get("id", "")] = u
	for m in data.get("decor_mesh_map", []):
		if typeof(m) == TYPE_DICTIONARY:
			decor_mesh_by_id[m.get("decor_id", "")] = m
	_apply_mesh_bounds_blocking_footprints()

func _apply_mesh_bounds_blocking_footprints() -> void:
	if not strict_blocking_from_mesh_bounds:
		return
	for key in decor_mesh_by_id.keys():
		var decor_id: String = String(key)
		var entry: Dictionary = decor_mesh_by_id.get(decor_id, {})
		if entry.is_empty():
			continue
		var scene_path: String = String(entry.get("mesh_scene", ""))
		if scene_path.is_empty():
			continue
		var computed_offsets: Array[Vector2i] = _compute_mesh_scene_blocking_offsets(scene_path)
		if computed_offsets.is_empty():
			continue
		entry["blocking_footprint"] = _offsets_to_array_pairs(computed_offsets)
		decor_mesh_by_id[decor_id] = entry

func _compute_mesh_scene_blocking_offsets(scene_path: String) -> Array[Vector2i]:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return []
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		inst.free()
		return []
	var bounds: Dictionary = _collect_mesh_bounds(inst as Node3D, Transform3D.IDENTITY)
	inst.free()
	if not bool(bounds.get("has", false)):
		return []
	var aabb: AABB = bounds.get("aabb", AABB())
	var cells_x: int = maxi(1, int(ceil(aabb.size.x / maxf(cell_width_3d, 0.001))))
	var cells_z: int = maxi(1, int(ceil(aabb.size.z / maxf(cell_depth_3d, 0.001))))
	var out: Array[Vector2i] = []
	for z in range(cells_z):
		for x in range(cells_x):
			out.append(Vector2i(x, z))
	return out

func _collect_mesh_bounds(node: Node3D, parent_xform: Transform3D) -> Dictionary:
	var xform: Transform3D = parent_xform * node.transform
	var has_bounds: bool = false
	var merged: AABB = AABB()
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var mesh_aabb: AABB = mi.mesh.get_aabb()
			var transformed: AABB = _transform_aabb(mesh_aabb, xform)
			merged = transformed
			has_bounds = true
	for child in node.get_children():
		if child is Node3D:
			var child_info: Dictionary = _collect_mesh_bounds(child as Node3D, xform)
			if bool(child_info.get("has", false)):
				var child_aabb: AABB = child_info.get("aabb", AABB())
				if has_bounds:
					merged = merged.merge(child_aabb)
				else:
					merged = child_aabb
					has_bounds = true
	return {
		"has": has_bounds,
		"aabb": merged
	}

func _transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var corners: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
		aabb.position + Vector3(0.0, aabb.size.y, 0.0),
		aabb.position + Vector3(0.0, 0.0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
		aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
		aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size
	]
	var min_v := Vector3(1e30, 1e30, 1e30)
	var max_v := Vector3(-1e30, -1e30, -1e30)
	for p in corners:
		var wp: Vector3 = xform * p
		min_v.x = minf(min_v.x, wp.x)
		min_v.y = minf(min_v.y, wp.y)
		min_v.z = minf(min_v.z, wp.z)
		max_v.x = maxf(max_v.x, wp.x)
		max_v.y = maxf(max_v.y, wp.y)
		max_v.z = maxf(max_v.z, wp.z)
	return AABB(min_v, max_v - min_v)

func _offsets_to_array_pairs(offsets: Array[Vector2i]) -> Array:
	var out: Array = []
	for off in offsets:
		out.append([off.x, off.y])
	return out

func _spawn_actors() -> void:
	for _i in range(cats_to_spawn):
		spawn_cat()
	for _i in range(patrons_to_spawn):
		spawn_patron()

func spawn_cat() -> Node3D:
	var spawn_cell: Vector2i = random_cafe_cell()
	var cat: Node3D = Cat3DScene.instantiate()
	cat.name = "Cat3D_%d" % cat_layer.get_child_count()
	cat_layer.add_child(cat)
	cat.call("configure", self, spawn_cell)
	return cat

func spawn_patron() -> Node3D:
	var spawn_cell: Vector2i = random_cafe_cell()
	var patron: Node3D = Human3DScene.instantiate()
	patron.name = "Human3D_%d" % patron_layer.get_child_count()
	patron_layer.add_child(patron)
	patron.call("configure", self, spawn_cell)
	return patron

func _footprint_cells(anchor: Vector2i, mesh_entry: Dictionary, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var data: Dictionary = _normalized_offsets(mesh_entry, "footprint", rot)
	var offsets: Array = data.get("offsets", [])
	for off in offsets:
		out.append(anchor + (off as Vector2i))
	return out

func _occupied_cells(anchor: Vector2i, mesh_entry: Dictionary, rot: int) -> Array[Vector2i]:
	var key: String = "blocking_footprint" if mesh_entry.has("blocking_footprint") else "footprint"
	var out: Array[Vector2i] = []
	var data: Dictionary = _normalized_offsets(mesh_entry, key, rot)
	var offsets: Array = data.get("offsets", [])
	for off in offsets:
		out.append(anchor + (off as Vector2i))
	return out

func _register_decor_slots(anchor: Vector2i, mesh_entry: Dictionary, rot: int, owner_key: String) -> Array[int]:
	var out: Array[int] = []
	var slot_markers: Dictionary = mesh_entry.get("slot_markers", {})
	var footprint_norm: Dictionary = _normalized_offsets(mesh_entry, "footprint", rot)
	var footprint_shift: Vector2i = footprint_norm.get("shift", Vector2i.ZERO)
	for kind_key in slot_markers.keys():
		var kind: StringName = StringName(kind_key)
		for marker_raw in slot_markers[kind_key]:
			var arr: Array = marker_raw
			if arr.size() < 2:
				continue
			var off := Vector2i(int(arr[0]), int(arr[1]))
			var cell: Vector2i = anchor + rotate_offset(off, rot) - footprint_shift
			var world_pos: Vector3 = map_to_world(cell)
			var id: int = int(slot_manager.call("add_slot", kind, cell, world_pos, owner_key))
			out.append(id)
	return out

func _footprint_world_center_offset(mesh_entry: Dictionary, rot: int, use_blocking: bool) -> Vector3:
	var key: String = "blocking_footprint" if use_blocking and mesh_entry.has("blocking_footprint") else "footprint"
	var data: Dictionary = _normalized_offsets(mesh_entry, key, rot)
	var offsets: Array = data.get("offsets", [])
	if offsets.is_empty():
		return Vector3.ZERO
	var min_x: int = (offsets[0] as Vector2i).x
	var max_x: int = min_x
	var min_y: int = (offsets[0] as Vector2i).y
	var max_y: int = min_y
	for item in offsets:
		var off: Vector2i = item
		min_x = mini(min_x, off.x)
		max_x = maxi(max_x, off.x)
		min_y = mini(min_y, off.y)
		max_y = maxi(max_y, off.y)
	var center_x: float = (float(min_x) + float(max_x)) * 0.5 * cell_width_3d
	var center_z: float = (float(min_y) + float(max_y)) * 0.5 * cell_depth_3d
	return Vector3(center_x, 0.0, center_z)

func _normalized_offsets(mesh_entry: Dictionary, key: String, rot: int) -> Dictionary:
	var rotated: Array[Vector2i] = []
	for raw in mesh_entry.get(key, []):
		var arr: Array = raw
		if arr.size() < 2:
			continue
		var off := Vector2i(int(arr[0]), int(arr[1]))
		rotated.append(rotate_offset(off, rot))
	if rotated.is_empty():
		rotated.append(Vector2i.ZERO)
	var min_x: int = rotated[0].x
	var min_y: int = rotated[0].y
	for off in rotated:
		min_x = mini(min_x, off.x)
		min_y = mini(min_y, off.y)
	var shift := Vector2i(min_x, min_y)
	var normalized: Array[Vector2i] = []
	for off in rotated:
		var n: Vector2i = off - shift
		if not normalized.has(n):
			normalized.append(n)
	return {
		"offsets": normalized,
		"shift": shift
	}

func _random_cell_in_rect(rect: Rect2i) -> Vector2i:
	var min_x: int = rect.position.x
	var max_x: int = rect.end.x - 1
	var min_y: int = rect.position.y
	var max_y: int = rect.end.y - 1
	return Vector2i(rng.randi_range(min_x, max_x), rng.randi_range(min_y, max_y))

func _random_walkable_cell(allow_rest_area: bool, rect: Rect2i) -> Vector2i:
	for _i in range(64):
		var c: Vector2i = _random_cell_in_rect(rect)
		if is_walkable(c, allow_rest_area):
			return c
	return rect.position

func _normalize_rotation(rotation_deg: int) -> int:
	var r: int = rotation_deg % 360
	if r < 0:
		r += 360
	return int(round(float(r) / 90.0)) * 90 % 360

func _array_to_vec3(raw: Array) -> Vector3:
	if raw.size() < 3:
		return Vector3.ZERO
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _is_rotation_allowed(allowed: Array, rot: int) -> bool:
	for value in allowed:
		if _normalize_rotation(int(value)) == rot:
			return true
	return false

func _is_blocked_by_back_wall(cell: Vector2i) -> bool:
	if not block_back_wall_edge_cells:
		return false
	if not is_in_cafe_floor(cell):
		return false
	if block_north_wall_edge and cell.y == cafe_floor_rect.position.y:
		return true
	if block_west_wall_edge and cell.x == cafe_floor_rect.position.x:
		return true
	return false

func _cell_key(cell: Vector2i) -> String:
	return "%d_%d" % [cell.x, cell.y]

func _frame_camera_to_floor() -> void:
	if camera == null:
		return
	var min_cell: Vector2i = cafe_floor_rect.position
	var max_cell: Vector2i = cafe_floor_rect.end - Vector2i.ONE
	var min_world: Vector3 = map_to_world(min_cell)
	var max_world: Vector3 = map_to_world(max_cell)
	var center: Vector3 = (min_world + max_world) * 0.5
	var extent_x: float = absf(max_world.x - min_world.x)
	var extent_z: float = absf(max_world.z - min_world.z)
	var radius: float = maxf(extent_x, extent_z) * 0.5
	var view_distance: float = maxf(6.0, radius * iso_distance_multiplier)
	var yaw_rad: float = deg_to_rad(iso_yaw_degrees)
	var pitch_rad: float = deg_to_rad(iso_pitch_degrees)
	var horizontal_dist: float = view_distance * cos(pitch_rad)
	var vertical_dist: float = view_distance * sin(pitch_rad) + iso_vertical_padding
	var offset := Vector3(cos(yaw_rad), 0.0, sin(yaw_rad)) * horizontal_dist
	offset.y = vertical_dist
	var cam_pos: Vector3 = center + offset
	var target: Vector3 = center + Vector3(0.0, 0.2, 0.0)
	camera.global_position = cam_pos
	camera.look_at(target, Vector3.UP)
	_fit_camera_to_floor_bounds(target)

func _fit_camera_to_floor_bounds(target: Vector3) -> void:
	if camera == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var margin_x: float = viewport_size.x * clampf(iso_viewport_margin_ratio, 0.0, 0.35)
	var margin_y: float = viewport_size.y * clampf(iso_viewport_margin_ratio, 0.0, 0.35)
	var bounds: Array[Vector3] = _get_floor_bounds_points()
	for _i in range(24):
		var fits: bool = true
		for p in bounds:
			if camera.is_position_behind(p):
				fits = false
				break
			var screen: Vector2 = camera.unproject_position(p)
			if screen.x < margin_x or screen.x > viewport_size.x - margin_x:
				fits = false
				break
			if screen.y < margin_y or screen.y > viewport_size.y - margin_y:
				fits = false
				break
		if fits:
			return
		var back_dir: Vector3 = (camera.global_position - target).normalized()
		camera.global_position += back_dir * 1.0
		camera.look_at(target, Vector3.UP)

func _get_floor_bounds_points() -> Array[Vector3]:
	var min_cell: Vector2i = cafe_floor_rect.position
	var max_cell: Vector2i = cafe_floor_rect.end - Vector2i.ONE
	var a: Vector3 = map_to_world(min_cell)
	var b: Vector3 = map_to_world(max_cell)
	var min_x: float = minf(a.x, b.x) - cell_width_3d * 0.5
	var max_x: float = maxf(a.x, b.x) + cell_width_3d * 0.5
	var min_z: float = minf(a.z, b.z) - cell_depth_3d * 0.5
	var max_z: float = maxf(a.z, b.z) + cell_depth_3d * 0.5
	var min_y: float = -maxf(floor_tile_height_3d, rest_tile_height_3d)
	var max_y: float = maxf(1.2, rest_tile_height_3d + 0.8)
	return [
		Vector3(min_x, min_y, min_z),
		Vector3(max_x, min_y, min_z),
		Vector3(min_x, min_y, max_z),
		Vector3(max_x, min_y, max_z),
		Vector3(min_x, max_y, min_z),
		Vector3(max_x, max_y, min_z),
		Vector3(min_x, max_y, max_z),
		Vector3(max_x, max_y, max_z)
	]

func _apply_floor_layout_settings() -> void:
	var cells_x: int = maxi(1, cafe_floor_rect.size.x)
	var cells_y: int = maxi(1, cafe_floor_rect.size.y)
	if auto_size_cells_to_target:
		var candidate_w: float = target_floor_world_size.x / float(cells_x)
		var candidate_d: float = target_floor_world_size.y / float(cells_y)
		if enforce_square_cells:
			var edge: float = minf(candidate_w, candidate_d)
			cell_width_3d = edge
			cell_depth_3d = edge
		else:
			cell_width_3d = candidate_w
			cell_depth_3d = candidate_d
	if auto_center_grid_origin:
		var min_cell: Vector2i = cafe_floor_rect.position
		var max_cell: Vector2i = cafe_floor_rect.end - Vector2i.ONE
		var center_cell_x: float = (float(min_cell.x) + float(max_cell.x)) * 0.5
		var center_cell_y: float = (float(min_cell.y) + float(max_cell.y)) * 0.5
		grid_origin_3d = grid_center_world - Vector3(center_cell_x * cell_width_3d, 0.0, center_cell_y * cell_depth_3d)

func _apply_grid_subdivision() -> void:
	if _grid_subdivision_applied:
		return
	var factor: int = maxi(1, mini_tiles_per_axis)
	if factor > 1:
		cafe_floor_rect = _scale_rect(cafe_floor_rect, factor)
		rest_area_rect = _scale_rect(rest_area_rect, factor)
	_grid_subdivision_applied = true

func _scale_rect(rect: Rect2i, factor: int) -> Rect2i:
	return Rect2i(rect.position * factor, rect.size * factor)
