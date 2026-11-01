extends Node3D
class_name MainLevel3D

const GridIso3DScript = preload("res://Scripts/prototype3d/GridIso3D.gd")
const Cat3DScene = preload("res://Scenes/Prototype3D/Cat3D.tscn")
const Human3DScene = preload("res://Scenes/Prototype3D/Human3D.tscn")
const CAT_FACTORY_PATH: String = "res://Scripts/data/CatFactory.gd"
const STARTER_LAYOUT_PATH: String = "res://Data/starter_layout.json"
const DataLoaderScript = preload("res://Scripts/data/DataLoader.gd")
const CatGenomeScript = preload("res://Scripts/prototype3d/CatGenome.gd")
## A placement may strand at most this many cafe/rest cells (small pockets against walls).
const MAX_STRANDED_CELLS: int = 3
const REFUND_RATIO: float = 0.5
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const UNAVAILABLE_CAT_STATES: Array[StringName] = [&"retreating", &"rest", &"returning"]

## Run state for the HUD (contract 1.4).
signal economy_changed(money: int, reputation: int)
signal cat_drought_changed(active: bool)
signal day_changed(day: int)
signal patron_left(patron)
## Emitted after decor is placed or removed (anchor in level cells).
signal decor_changed(decor_id: String, anchor: Vector2i, placed: bool)
## Emitted after a save attempt (day end, window close, manual).
signal run_saved(ok: bool, reason: String)
## A cat's trust band changed (re-emitted from every cat, including later rescues).
signal cat_trust_changed(cat, old_id: StringName, new_id: StringName)
## A ready cat went home; reputation_gain is what the adoption earned.
signal cat_adopted(cat_name: String, reputation_gain: int)
## Debug cat rendering settings changed (F6 / F8 / HUD debug panel).
signal debug_settings_changed

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
## Legacy: derive blocking from model bounds. Off: decor_mesh_map "footprint" is the single source of truth.
@export var strict_blocking_from_mesh_bounds: bool = false
@export var block_back_wall_edge_cells: bool = false
@export var block_north_wall_edge: bool = true
@export var block_west_wall_edge: bool = true
## Base tiles (before subdivision). Overridden by rooms.json when it has the 3D shape.
@export var cafe_floor_rect: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(12, 10))
@export var rest_area_rect: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(4, 4))
## Cafe-side door cells in LEVEL cells (after subdivision). Empty = rooms.json or a default doorway.
@export var rest_door_cells: Array[Vector2i] = []
## -1 = use balance_config.population.starting_cats (default 3).
@export var cats_to_spawn: int = -1
## -1 = use balance_config.population.patron_target_count (default 3).
@export var patrons_to_spawn: int = -1
@export var place_starter_layout: bool = true
## Patrons keep arriving through the entrance (population.patron_spawn_interval_sec).
@export var spawn_patrons_over_time: bool = true
## 0 = random seed per boot. Overridden by a "--seed=N" command-line argument.
@export var run_seed: int = 0
## Load/save the run through the SaveSystem child. `--no-save` disables it, `--new-game` clears the save on boot.
@export var use_save: bool = true
## Saving/loading is skipped in headless runs and when the level is not the current scene
## (probes, capture tools) so test runs never touch the player's slot. Set true (or pass
## `--save`) to opt in.
var force_save: bool = false
@export var floor_tile_height_3d: float = 0.28
@export var rest_tile_height_3d: float = 0.45
@export var actor_y_offset: float = 0.0
## Orthographic diorama camera (contract 1.6): yaw 45, pitch 40, size 12 (zoom 8-17).
@export var iso_yaw_degrees: float = 45.0
@export var iso_pitch_degrees: float = 40.0
@export var camera_default_size: float = 14.5
@export var camera_min_size: float = 8.0
@export var camera_max_size: float = 17.0
@export var camera_fit_padding: float = 1.12
@export var camera_distance: float = 40.0
@export var camera_pan_speed: float = 9.0
@export var camera_zoom_step: float = 1.0

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var cat_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var patron_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var data: Dictionary = {}
var balance: Dictionary = {}
var decor_data_by_id: Dictionary = {}
var decor_ui_by_id: Dictionary = {}
var decor_mesh_by_id: Dictionary = {}
var cat_factory: RefCounted = null

var blocked_cells: Dictionary = {}
var decor_instances: Dictionary = {}
var decor_anchor_by_cell: Dictionary = {}
var _grid_subdivision_applied: bool = false

# Room cells in level cells (resolved after subdivision).
var entrance_cell: Vector2i = Vector2i(-1, -1)
var patron_spawn_cells: Array[Vector2i] = []
var cat_spawn_cells: Array[Vector2i] = []
var _room_door_base: Array[Vector2i] = []
var _room_entrance_base: Vector2i = Vector2i(-1, -1)
var _room_patron_spawns_base: Array[Vector2i] = []
var _room_cat_spawns_base: Array[Vector2i] = []
var _door_cafe_cells: Array[Vector2i] = []
var _door_rest_cells: Array[Vector2i] = []
var _door_edges: Dictionary = {}

# Run state (contract 1.4, B-internal).
var money: int = 0
var reputation: int = 0
var day: int = 1
var day_time_sec: float = 0.0
var day_length_sec: float = 180.0
var cat_drought: bool = false
var use_viewport_rig: bool = true
# Debug cat rendering (HUD debug panel F7, F8, F6). Applied to every cat in the
# "cats" group and to each newly spawned cat; persisted in DEBUG_SETTINGS_PATH
# (separate from the run save) only when _debug_cfg_writable.
const DEBUG_SETTINGS_PATH: String = "user://debug_settings.cfg"
const DEBUG_DENSITIES: Array[int] = [48, 56, 64, 80, 96]
const DEBUG_EXPRESSIONS: Array[String] = ["open", "happy", "stressed", "sleepy", "angry", "worried", "sad", "surprised", "smug"]
var cat_pixel_art: bool = true
var cat_pixel_density: int = 56
var cat_eye_override: String = ""          # "" = each cat's genome shape
var cat_expression_override: String = ""   # "" = auto (game-driven)
var _debug_cfg_writable: bool = false
var _drought_check_timer: float = 0.0
var _cat_seq: int = 0
var _patron_seq: int = 0
var _patron_spawn_timer: float = 2.0
var _saved_state: Dictionary = {}
var _saved_state_loaded: bool = false
var _seed_salt: int = 0
var _new_game_confirm_sec: float = 0.0
var _save_blocked: bool = false
var adoptions_total: int = 0

@onready var data_loader: Node = $DataLoader
@onready var floor_grid: Node3D = $WorldRoot/FloorGrid
@onready var decor_layer: Node3D = $WorldRoot/DecorLayer3D
@onready var actor_root: Node3D = $WorldRoot/ActorLayer3D
@onready var cat_layer: Node3D = $WorldRoot/ActorLayer3D/CatLayer
@onready var patron_layer: Node3D = $WorldRoot/ActorLayer3D/PatronLayer
@onready var slot_manager: Node = $SlotManager3D
@onready var camera: Camera3D = $CameraRig/Camera3D

func _ready() -> void:
	_init_save_flags()
	_load_debug_settings()
	_init_seeds()
	_load_data()
	_apply_room_data()
	_apply_grid_subdivision()
	_apply_floor_layout_settings()
	_prepare_decor_mesh_entries()
	_init_run_state()
	floor_grid.call("rebuild", self)
	_frame_camera_to_floor()
	if place_starter_layout:
		_place_starting_decor()
	_spawn_actors()

func _process(delta: float) -> void:
	_update_camera(delta)
	_update_build_grid_visibility()
	_update_day_timer(delta)
	_update_patron_spawning(delta)
	if _new_game_confirm_sec > 0.0:
		_new_game_confirm_sec -= delta
	_drought_check_timer -= delta
	if _drought_check_timer <= 0.0:
		_drought_check_timer = 0.25
		_update_cat_drought()

func _unhandled_input(event: InputEvent) -> void:
	if _camera_unhandled_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F6:
			toggle_viewport_rig()
			get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.keycode == KEY_F8:
			toggle_cat_render_mode()
			get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.keycode == KEY_F9:
			if _new_game_confirm_sec > 0.0:
				_new_game_confirm_sec = 0.0
				start_new_game()
			else:
				_new_game_confirm_sec = 3.0
				_hud_notice("Press F9 again to start a new game (erases the save)", 3.0)
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_run("close")

## F6 debug: flip every cat between the SubViewport rig and the fallback sprite.
func toggle_viewport_rig() -> void:
	set_viewport_rig(not use_viewport_rig)
	_hud_notice("Cat rig: %s" % ("procedural" if use_viewport_rig else "fallback sprite"), 1.5)

func set_viewport_rig(on: bool) -> void:
	use_viewport_rig = on
	if is_inside_tree():
		get_tree().call_group("cats", "set_use_viewport_rig", use_viewport_rig)
	_debug_settings_updated()

## F8 debug: flip every cat between the pixel and the smooth renderer.
func toggle_cat_render_mode() -> void:
	set_cat_render_mode(not cat_pixel_art, cat_pixel_density)
	_hud_notice("Cats: %s" % ("pixel" if cat_pixel_art else "smooth"), 1.5)

## Pixel (density = art px across the rig viewport) or smooth rendering for
## every cat. World size and feet-on-floor stay identical (configure_rig_rendering).
func set_cat_render_mode(pixel: bool, density: int = -1) -> void:
	cat_pixel_art = pixel
	if density > 0:
		cat_pixel_density = clampi(density, 32, 192)
	if is_inside_tree():
		get_tree().call_group("cats", "configure_rig_rendering", cat_pixel_art, cat_pixel_density)
	_debug_settings_updated()

## Eye shape shown on every cat ("" = each cat's own genome shape). Visual only:
## the cat defs / save keep the genome shape.
func set_cat_eye_override(shape: String) -> void:
	shape = CatGenomeScript.legacy_eye_shape(shape)
	cat_eye_override = shape if CatGenomeScript.EYE_SHAPES.has(shape) else ""
	if is_inside_tree():
		get_tree().call_group("cats", "set_eye_shape_override", cat_eye_override)
	_debug_settings_updated()

## Face expression forced on every cat ("" = auto).
func set_cat_expression_override(expr: String) -> void:
	cat_expression_override = expr if DEBUG_EXPRESSIONS.has(expr) else ""
	if is_inside_tree():
		get_tree().call_group("cats", "set_expression_override", cat_expression_override)
	_debug_settings_updated()

func get_debug_settings() -> Dictionary:
	return {
		"pixel_art": cat_pixel_art, "pixel_density": cat_pixel_density,
		"viewport_rig": use_viewport_rig, "eye_shape": cat_eye_override,
		"expression": cat_expression_override,
	}

# Debug settings are read and written only when the run save would be (a real
# game window, MainLevel3D as the current scene) or with --save /
# --debug-settings, so headless runs, probes and capture tools never touch the
# player's file and always start from the defaults.
func _load_debug_settings() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	var is_main: bool = is_inside_tree() and get_tree().current_scene == self
	_debug_cfg_writable = args.has("--debug-settings") or force_save or (DisplayServer.get_name() != "headless" and is_main)
	if not _debug_cfg_writable:
		return
	var cfg := ConfigFile.new()
	if cfg.load(DEBUG_SETTINGS_PATH) != OK:
		return
	cat_pixel_art = bool(cfg.get_value("cats", "pixel_art", cat_pixel_art))
	cat_pixel_density = clampi(int(cfg.get_value("cats", "pixel_density", cat_pixel_density)), 32, 192)
	use_viewport_rig = bool(cfg.get_value("cats", "viewport_rig", use_viewport_rig))
	var es: String = CatGenomeScript.legacy_eye_shape(str(cfg.get_value("cats", "eye_shape", "")))
	cat_eye_override = es if CatGenomeScript.EYE_SHAPES.has(es) else ""
	var ex: String = str(cfg.get_value("cats", "expression", ""))
	cat_expression_override = ex if DEBUG_EXPRESSIONS.has(ex) else ""

func _debug_settings_updated() -> void:
	debug_settings_changed.emit()
	if not _debug_cfg_writable:
		return
	var cfg := ConfigFile.new()
	var d: Dictionary = get_debug_settings()
	for k in d.keys():
		cfg.set_value("cats", k, d[k])
	if cfg.save(DEBUG_SETTINGS_PATH) != OK:
		push_warning("Could not write %s" % DEBUG_SETTINGS_PATH)

# Applies the debug render settings to a cat that was just configured.
func _apply_debug_to_cat(cat: Node) -> void:
	if not use_viewport_rig and cat.has_method("set_use_viewport_rig"):
		cat.call("set_use_viewport_rig", false)
	if cat_eye_override != "" and cat.has_method("set_eye_shape_override"):
		cat.call("set_eye_shape_override", cat_eye_override)
	if cat_expression_override != "" and cat.has_method("set_expression_override"):
		cat.call("set_expression_override", cat_expression_override)

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

## Grid rotation matches Node3D.rotation_degrees.y: +90 maps model +Z (0,1) to +X (1,0).
func rotate_offset(offset: Vector2i, rotation_deg: int) -> Vector2i:
	var rot: int = _normalize_rotation(rotation_deg)
	match rot:
		90:
			return Vector2i(offset.y, -offset.x)
		180:
			return Vector2i(-offset.x, -offset.y)
		270:
			return Vector2i(-offset.y, offset.x)
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
	return _random_walkable_cell(true, rest_area_rect)

# --- Rest-area doors -------------------------------------------------------

func get_rest_door_cells() -> Array[Vector2i]:
	return _door_cafe_cells.duplicate()

func is_rest_door_cell(grid_pos: Vector2i) -> bool:
	return _door_cafe_cells.has(grid_pos)

## Cafe-side door cell nearest from_grid (contract 1.4).
func get_rest_exit_cell(from_grid: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1_000_000
	for c in _door_cafe_cells:
		if not is_walkable(c, false):
			continue
		var d: int = absi(c.x - from_grid.x) + absi(c.y - from_grid.y)
		if d < best_d:
			best_d = d
			best = c
	if best_d == 1_000_000:
		return random_cafe_cell()
	return best

## Rest-side door cell nearest from_grid (contract 1.4).
func get_rest_entry_cell(from_grid: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1_000_000
	for c in _door_rest_cells:
		if not is_walkable(c, true):
			continue
		var d: int = absi(c.x - from_grid.x) + absi(c.y - from_grid.y)
		if d < best_d:
			best_d = d
			best = c
	if best_d == 1_000_000:
		return random_rest_cell()
	return best

## BFS flood from grid to the nearest walkable cell, preferring the same side of the
## rest partition so actors are never teleported across it (contract 1.4).
func nearest_walkable_cell(grid: Vector2i, allow_rest: bool) -> Vector2i:
	if is_walkable(grid, allow_rest):
		return grid
	var start: Vector2i = Vector2i(
		clampi(grid.x, cafe_floor_rect.position.x, cafe_floor_rect.end.x - 1),
		clampi(grid.y, cafe_floor_rect.position.y, cafe_floor_rect.end.y - 1))
	var want_rest: bool = allow_rest and is_in_rest_area(grid)
	var fallback: Vector2i = Vector2i(-9999, -9999)
	var visited: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if is_walkable(c, allow_rest):
			if is_in_rest_area(c) == want_rest:
				return c
			if fallback.x == -9999:
				fallback = c
		for d in DIRS4:
			var n: Vector2i = c + d
			if visited.has(n) or not is_in_cafe_floor(n):
				continue
			visited[n] = true
			queue.append(n)
	if fallback.x != -9999:
		return fallback
	return grid

# --- Pathing ----------------------------------------------------------------

## BFS path (excluding start). The start cell may be blocked. If start is in the rest
## area, rest cells are traversable. Rest<->cafe moves only happen across door edges.
func build_path(start: Vector2i, goal: Vector2i, allow_rest_area: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if start == goal:
		return result
	var allow_rest: bool = allow_rest_area or is_in_rest_area(start)
	if not is_walkable(goal, allow_rest):
		return result

	var came_from: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var found: bool = false
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == goal:
			found = true
			break
		for d in DIRS4:
			var next: Vector2i = current + d
			if came_from.has(next):
				continue
			if not is_walkable(next, allow_rest):
				continue
			if not _can_step(current, next):
				continue
			came_from[next] = current
			queue.append(next)

	if not found and not came_from.has(goal):
		return result
	var cursor: Vector2i = goal
	while cursor != start:
		result.push_front(cursor)
		cursor = came_from[cursor]
	return result

## Distance field (steps) from start to every reachable cell, same rules as build_path.
func path_distances_from(start: Vector2i, allow_rest_area: bool) -> Dictionary:
	var allow_rest: bool = allow_rest_area or is_in_rest_area(start)
	var dist: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		var dc: int = int(dist[current])
		for d in DIRS4:
			var next: Vector2i = current + d
			if dist.has(next):
				continue
			if not is_walkable(next, allow_rest):
				continue
			if not _can_step(current, next):
				continue
			dist[next] = dc + 1
			queue.append(next)
	return dist

func _can_step(from: Vector2i, to: Vector2i) -> bool:
	var from_rest: bool = is_in_rest_area(from)
	var to_rest: bool = is_in_rest_area(to)
	if from_rest == to_rest:
		return true
	if _door_edges.is_empty():
		return true
	var cafe_cell: Vector2i = from if to_rest else to
	var rest_cell: Vector2i = to if to_rest else from
	return _door_edges.has(_edge_key(cafe_cell, rest_cell))

func _edge_key(cafe_cell: Vector2i, rest_cell: Vector2i) -> String:
	return "%d_%d>%d_%d" % [cafe_cell.x, cafe_cell.y, rest_cell.x, rest_cell.y]

# --- Decor placement -------------------------------------------------------

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

	var walkable: bool = _is_decor_walkable(decor_id)
	var footprint: Array[Vector2i] = _occupied_cells(anchor_grid, mesh_entry, rot)
	var other_slot_cells: Dictionary = {}
	if not walkable:
		other_slot_cells = _all_slot_cells()
	for c in footprint:
		if not is_in_cafe_floor(c):
			return "out_of_cafe_floor:%s" % str(c)
		if _is_blocked_by_back_wall(c):
			return "blocked_by_back_wall:%s" % str(c)
		if is_in_rest_area(c):
			return "inside_rest_area:%s" % str(c)
		if decor_anchor_by_cell.has(_cell_key(c)):
			return "occupied_by_decor:%s" % str(c)
		if not walkable and is_blocked(c):
			return "blocked_cell:%s" % str(c)
		if not walkable and is_rest_door_cell(c):
			return "blocks_rest_door:%s" % str(c)
		if not walkable and c == entrance_cell:
			return "blocks_entrance:%s" % str(c)
		if other_slot_cells.has(c):
			return "blocks_slot:%s" % str(c)

	var actor_cells: Dictionary = {}
	if not walkable:
		actor_cells = _actor_cells()
		for c in footprint:
			if actor_cells.has(c):
				return "occupied_by_actor:%s" % str(c)

	for slot in _slot_cells_for(anchor_grid, mesh_entry, rot):
		var sc: Vector2i = slot.get("cell", Vector2i.ZERO)
		if not is_in_cafe_floor(sc) or is_in_rest_area(sc) or _is_blocked_by_back_wall(sc):
			return "slot_blocked:%s" % str(sc)
		if is_blocked(sc):
			return "slot_blocked:%s" % str(sc)
		if not walkable and footprint.has(sc):
			return "slot_blocked:%s" % str(sc)
	if not walkable:
		var conn: String = _connectivity_block_reason(footprint, other_slot_cells, actor_cells)
		if not conn.is_empty():
			return conn
	return ""

## GP-02 / CR-1: blocking decor must not cut the entrance off from the nap-zone doors, any
## seat, any actor, or more than a small pocket of floor. Compares one BFS from the entrance
## before and after temporarily blocking the footprint.
func _connectivity_block_reason(footprint: Array[Vector2i], slot_cells: Dictionary, actor_cells: Dictionary) -> String:
	if entrance_cell.x < 0 or not is_walkable(entrance_cell, false):
		return ""
	var before: Dictionary = path_distances_from(entrance_cell, true)
	var added: Array[String] = []
	for c in footprint:
		var k: String = _cell_key(c)
		if not blocked_cells.has(k):
			blocked_cells[k] = true
			added.append(k)
	var after: Dictionary = path_distances_from(entrance_cell, true)
	for k in added:
		blocked_cells.erase(k)
	var required: Array = []
	required.append_array(_door_cafe_cells)
	required.append_array(_door_rest_cells)
	required.append_array(slot_cells.keys())
	required.append_array(actor_cells.keys())
	for c in required:
		if footprint.has(c):
			continue
		if before.has(c) and not after.has(c):
			return "would_block_path:%s" % str(c)
	var lost: int = 0
	for c in before.keys():
		if not after.has(c) and not footprint.has(c):
			lost += 1
			if lost > MAX_STRANDED_CELLS:
				return "would_block_path:%s" % str(c)
	return ""

## Placement + funds check for the build menu ("insufficient_funds").
func get_purchase_block_reason(anchor_grid: Vector2i, decor_id: String, rotation_deg: int) -> String:
	var reason: String = get_place_block_reason(anchor_grid, decor_id, rotation_deg)
	if not reason.is_empty():
		return reason
	if money < get_decor_cost(decor_id):
		return "insufficient_funds"
	return ""

## Places decor and spends its cost. place_decor() itself is free (starter layout, loads).
func purchase_decor(anchor_grid: Vector2i, decor_id: String, rotation_deg: int) -> bool:
	if not get_purchase_block_reason(anchor_grid, decor_id, rotation_deg).is_empty():
		return false
	var cost: int = get_decor_cost(decor_id)
	if not place_decor(anchor_grid, decor_id, rotation_deg, cost):
		return false
	spend_money(cost)
	return true

## paid = what the player spent on it (0 for starter/free items); "Put away" refunds part of it.
func place_decor(anchor_grid: Vector2i, decor_id: String, rotation_deg: int, paid: int = 0) -> bool:
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
	decor_instance.scale = get_decor_scale(decor_id)
	decor_layer.add_child(decor_instance)

	var footprint: Array[Vector2i] = _occupied_cells(anchor_grid, mesh_entry, rot)
	var anchor_key: String = _cell_key(anchor_grid)
	var walkable: bool = _is_decor_walkable(decor_id)
	for c in footprint:
		decor_anchor_by_cell[_cell_key(c)] = anchor_key
		if not walkable:
			set_blocked(c, true)

	var slot_ids: Array[int] = _register_decor_slots(anchor_grid, mesh_entry, rot, anchor_key)
	decor_instances[anchor_key] = {
		"node": decor_instance,
		"decor_id": decor_id,
		"anchor": anchor_grid,
		"rotation": rot,
		"walkable": walkable,
		"occupied": footprint,
		"slot_ids": slot_ids,
		"paid": maxi(0, paid)
	}
	decor_changed.emit(decor_id, anchor_grid, true)
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
	decor_changed.emit(String(rec.get("decor_id", "")), rec.get("anchor", any_cell), false)
	return true

## Placed decor in the run-state shape: [{decor_id, anchor:[x,y], rotation}].
func get_placed_decor() -> Array:
	var out: Array = []
	for key in decor_instances.keys():
		var rec: Dictionary = decor_instances[key]
		var a: Vector2i = rec.get("anchor", Vector2i.ZERO)
		out.append({"decor_id": String(rec.get("decor_id", "")), "anchor": [a.x, a.y], "rotation": int(rec.get("rotation", 0)), "paid": int(rec.get("paid", 0))})
	return out

## Ids present in decor.json, decor_ui.json and decor_mesh_map.json.
func get_available_decor_ids() -> Array[String]:
	var out: Array[String] = []
	for key in decor_mesh_by_id.keys():
		var id: String = String(key)
		if id.is_empty():
			continue
		if not decor_data_by_id.is_empty() and not decor_data_by_id.has(id):
			continue
		if not decor_ui_by_id.is_empty() and not decor_ui_by_id.has(id):
			continue
		out.append(id)
	out.sort()
	return out

func get_decor_cost(decor_id: String) -> int:
	return int(decor_data_by_id.get(decor_id, {}).get("cost", 0))

func get_decor_display_name(decor_id: String) -> String:
	var ui: Dictionary = decor_ui_by_id.get(decor_id, {})
	if ui.has("name"):
		return String(ui["name"])
	return String(decor_data_by_id.get(decor_id, {}).get("display_name", decor_id.capitalize()))

func get_decor_scale(decor_id: String) -> Vector3:
	var entry: Dictionary = decor_mesh_by_id.get(decor_id, {})
	var raw = entry.get("scale", null)
	if raw is Array:
		var arr: Array = raw
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
		if arr.size() == 1:
			return Vector3.ONE * float(arr[0])
	elif raw is float or raw is int:
		return Vector3.ONE * float(raw)
	return Vector3.ONE

func get_decor_tint(decor_id: String) -> Color:
	var hex: String = String(decor_ui_by_id.get(decor_id, {}).get("tint", ""))
	if hex.is_empty() or not Color.html_is_valid(hex):
		return Color.WHITE
	return Color.html(hex)

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
		"name": get_decor_display_name(decor_id),
		"color": String(ui.get("color", "Unknown")),
		"tint": get_decor_tint(decor_id),
		"durability": int(ui.get("durability", 100)),
		"cost": get_decor_cost(decor_id),
		"paid": int(rec.get("paid", 0)),
		"refund": get_decor_refund(grid_pos),
		"category": String(decor_data_by_id.get(decor_id, {}).get("category", "")),
		"mesh_scene": String(mesh_map.get("mesh_scene", "")),
		"scale": get_decor_scale(decor_id)
	}

## What putting this decor away gives back: half of what the player actually paid (GP-04).
func get_decor_refund(grid_pos: Vector2i) -> int:
	var anchor_key: String = decor_anchor_by_cell.get(_cell_key(grid_pos), "")
	if anchor_key.is_empty():
		return 0
	var rec: Dictionary = decor_instances.get(anchor_key, {})
	return int(floor(float(rec.get("paid", 0)) * REFUND_RATIO))

func get_decor_blocking_cells(anchor_grid: Vector2i, decor_id: String, rotation_deg: int) -> Array[Vector2i]:
	var mesh_entry: Dictionary = decor_mesh_by_id.get(decor_id, {})
	if mesh_entry.is_empty():
		return []
	return _occupied_cells(anchor_grid, mesh_entry, _normalize_rotation(rotation_deg))

## Slot cells a decor would register at this anchor/rotation: [{kind, cell}].
func get_decor_slot_cells(anchor_grid: Vector2i, decor_id: String, rotation_deg: int) -> Array:
	var mesh_entry: Dictionary = decor_mesh_by_id.get(decor_id, {})
	if mesh_entry.is_empty():
		return []
	return _slot_cells_for(anchor_grid, mesh_entry, _normalize_rotation(rotation_deg))

func get_decor_world_position(anchor_grid: Vector2i, decor_id: String, rotation_deg: int) -> Vector3:
	var mesh_entry: Dictionary = decor_mesh_by_id.get(decor_id, {})
	if mesh_entry.is_empty():
		return map_to_world(anchor_grid)
	var rot: int = _normalize_rotation(rotation_deg)
	var pivot: Vector3 = _array_to_vec3(mesh_entry.get("pivot_offset", [0, 0, 0]))
	var center_offset: Vector3 = _footprint_world_center_offset(mesh_entry, rot)
	return map_to_world(anchor_grid) + center_offset + pivot

# --- Slots -------------------------------------------------------------------

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

# --- Actor queries -----------------------------------------------------------

func get_cat_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if cat_layer == null:
		return out
	for c in cat_layer.get_children():
		if c is Node3D and not c.is_queued_for_deletion():
			out.append(c as Node3D)
	return out

func get_patron_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if patron_layer == null:
		return out
	for p in patron_layer.get_children():
		if p is Node3D and not p.is_queued_for_deletion():
			out.append(p as Node3D)
	return out

## Kept for compatibility: number of patrons within radius.
func get_patrons_near(world_pos: Vector3, radius: float) -> int:
	return int(get_overstim_pressure_near(world_pos, radius).get("count", 0))

## {count, pressure, patrons}; pressure sums patron.overstim_impact, skipping leaving patrons.
func get_overstim_pressure_near(world_pos: Vector3, radius: float) -> Dictionary:
	var fallback_impact: float = float(balance.get("overstim", {}).get("interaction_gain_per_sec", 11.0))
	var count: int = 0
	var pressure: float = 0.0
	var near: Array = []
	for p in get_patron_nodes():
		if _is_patron_leaving(p):
			continue
		var pos: Vector3 = p.global_position
		if Vector2(pos.x, pos.z).distance_to(Vector2(world_pos.x, world_pos.z)) > radius:
			continue
		count += 1
		var impact = p.get("overstim_impact")
		var pp: float = float(impact) if (impact is float or impact is int) else fallback_impact
		# GP-05: a plant partition between patron and cat screens part of the pressure.
		pp *= 1.0 - _line_of_sight_break(world_to_map(pos), world_to_map(world_pos))
		pressure += pp
		near.append(p)
	return {"count": count, "pressure": pressure, "patrons": near}

## Strongest line_of_sight_break buff among decor cells strictly between two cells (0..0.9).
func _line_of_sight_break(a: Vector2i, b: Vector2i) -> float:
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	if steps <= 1:
		return 0.0
	var best: float = 0.0
	for i in range(1, steps):
		var t: float = float(i) / float(steps)
		var c := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		var anchor_key: String = decor_anchor_by_cell.get(_cell_key(c), "")
		if anchor_key.is_empty():
			continue
		var decor_id: String = String(decor_instances.get(anchor_key, {}).get("decor_id", ""))
		var v = decor_data_by_id.get(decor_id, {}).get("buffs", {}).get("line_of_sight_break", 0.0)
		if v is float or v is int:
			best = maxf(best, float(v))
	return clampf(best, 0.0, 0.9)

## Aggregated decor aura effects at a cell, by each decor's aura_radius and stack_rule.
func get_decor_effects_at(grid: Vector2i) -> Dictionary:
	var deltas_by_id: Dictionary = {}
	var factor: int = maxi(1, mini_tiles_per_axis)
	for key in decor_instances.keys():
		var rec: Dictionary = decor_instances[key]
		var decor_id: String = String(rec.get("decor_id", ""))
		var def: Dictionary = decor_data_by_id.get(decor_id, {})
		if def.is_empty():
			continue
		var radius: int = int(round(float(def.get("aura_radius", 0)) * float(factor)))
		var best: int = 1_000_000
		for cell in rec.get("occupied", []):
			var c: Vector2i = cell
			best = mini(best, maxi(absi(c.x - grid.x), absi(c.y - grid.y)))
		if best > radius:
			continue
		var buffs: Dictionary = def.get("buffs", {})
		if not deltas_by_id.has(decor_id):
			deltas_by_id[decor_id] = {}
		var per_buff: Dictionary = deltas_by_id[decor_id]
		for buff_key in buffs.keys():
			var v = buffs[buff_key]
			if not (v is float or v is int):
				continue
			var bk: String = String(buff_key)
			var delta: float = float(v) - 1.0 if bk.ends_with("_mult") else float(v)
			if not per_buff.has(bk):
				per_buff[bk] = []
			(per_buff[bk] as Array).append(delta)

	var totals: Dictionary = {}
	for decor_id in deltas_by_id.keys():
		var rule: String = String(decor_data_by_id.get(decor_id, {}).get("stack_rule", "additive"))
		var per_buff: Dictionary = deltas_by_id[decor_id]
		for bk in per_buff.keys():
			totals[bk] = float(totals.get(bk, 0.0)) + _stack_deltas(per_buff[bk], rule)

	var out: Dictionary = {
		"overstim_decay_mult": 1.0,
		"trust_gain_mult": 1.0,
		"mid_rest_reduction": 0.0,
		"interaction_mult": 1.0,
		"pathing_speed_mult": 1.0
	}
	for bk in totals.keys():
		var k: String = String(bk)
		if k.ends_with("_mult"):
			out[k] = maxf(0.05, 1.0 + float(totals[bk]))
		else:
			out[k] = float(totals[bk])
	return out

func _stack_deltas(values: Array, rule: String) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort_custom(func(a, b): return absf(float(a)) > absf(float(b)))
	match rule:
		"unique":
			return float(sorted[0])
		"diminishing":
			var total: float = 0.0
			var w: float = 1.0
			for v in sorted:
				total += float(v) * w
				w *= 0.5
			return total
		_:
			var sum: float = 0.0
			for v in sorted:
				sum += float(v)
			return sum

func _is_patron_leaving(p: Node) -> bool:
	if p.has_method("is_leaving"):
		return bool(p.call("is_leaving"))
	return StringName(str(p.get("state"))) == &"leaving"

func _is_cat_available(cat: Node) -> bool:
	if cat.has_method("is_available_on_floor"):
		return bool(cat.call("is_available_on_floor"))
	return not UNAVAILABLE_CAT_STATES.has(StringName(str(cat.get("state"))))

func _actor_cells() -> Dictionary:
	var out: Dictionary = {}
	var actors: Array[Node3D] = get_cat_nodes()
	actors.append_array(get_patron_nodes())
	for a in actors:
		out[world_to_map(a.global_position)] = true
		var gp = a.get("grid_position")
		if gp is Vector2i:
			out[gp] = true
		var p = a.get("path")
		if p is Array and not (p as Array).is_empty() and (p as Array)[0] is Vector2i:
			out[(p as Array)[0]] = true
	return out

func _all_slot_cells() -> Dictionary:
	var out: Dictionary = {}
	var slots = slot_manager.get("slots")
	if slots is Dictionary:
		for sid in (slots as Dictionary).keys():
			var g = (slots as Dictionary)[sid].get("grid", null)
			if g is Vector2i:
				out[g] = true
	return out

# --- Run state ----------------------------------------------------------------

func add_money(amount: int, _reason: String = "") -> void:
	if amount == 0:
		return
	money += amount
	economy_changed.emit(money, reputation)

func spend_money(amount: int) -> bool:
	if amount <= 0:
		return true
	if money < amount:
		return false
	money -= amount
	economy_changed.emit(money, reputation)
	return true

func add_reputation(amount: int) -> void:
	if amount == 0:
		return
	reputation += amount
	economy_changed.emit(money, reputation)

## Multiplier from placed decor with adoption_reputation_mult (adoption corner), by stack_rule.
func get_adoption_reputation_mult() -> float:
	var by_id: Dictionary = {}
	for key in decor_instances.keys():
		var decor_id: String = String(decor_instances[key].get("decor_id", ""))
		var v = decor_data_by_id.get(decor_id, {}).get("buffs", {}).get("adoption_reputation_mult", null)
		if v is float or v is int:
			if not by_id.has(decor_id):
				by_id[decor_id] = []
			(by_id[decor_id] as Array).append(float(v) - 1.0)
	var total: float = 0.0
	for decor_id in by_id.keys():
		total += _stack_deltas(by_id[decor_id], String(decor_data_by_id.get(decor_id, {}).get("stack_rule", "additive")))
	return maxf(0.0, 1.0 + total)

func can_adopt_cat(cat: Node) -> bool:
	return cat != null and is_instance_valid(cat) and bool(cat.get("ready_for_adoption"))

## GP-06: a ready cat goes home. Adds reputation, counts the adoption, frees the cat and
## brings in a new rescue (fearful, at a cat spawn cell). Returns the reputation gained, or -1.
func adopt_cat(cat: Node) -> int:
	if not can_adopt_cat(cat):
		return -1
	var econ: Dictionary = balance.get("economy", {})
	var base: float = float(econ.get("adoption_reputation", 1))
	var gain: int = maxi(1, roundi(base * get_adoption_reputation_mult()))
	var cat_name: String = str(cat.get("display_name"))
	release_actor_slot(cat as Node3D)
	cat.queue_free()
	adoptions_total += 1
	add_reputation(gain)
	cat_adopted.emit(cat_name, gain)
	var cell: Vector2i = cat_spawn_cells[cat_rng.randi_range(0, cat_spawn_cells.size() - 1)] if not cat_spawn_cells.is_empty() else random_cafe_cell()
	spawn_cat(cell, generate_cat_def())
	save_run("adoption")
	return gain

func get_cats_on_floor_count() -> int:
	var n: int = 0
	for c in get_cat_nodes():
		if _is_cat_available(c):
			n += 1
	return n

## Snapshot in the SaveSystem run-state shape (B14 writes it).
func get_run_state() -> Dictionary:
	var cats: Array = []
	for c in get_cat_nodes():
		if c.has_method("export_cat_def"):
			cats.append(c.call("export_cat_def"))
		else:
			var d = c.get("cat_def")
			if d is Dictionary:
				cats.append((d as Dictionary).duplicate(true))
	return {
		"day": day,
		"money": money,
		"reputation": reputation,
		"placed_decor": get_placed_decor(),
		"cats": cats,
		"run_seed": run_seed,
		"day_time_sec": day_time_sec,
		"active_cats": cats.size(),
		"active_patrons": get_active_patron_count(),
		# Keys the 3D level does not drive yet; carried over so a save round-trip keeps them.
		"time_of_day": _time_of_day_label(),
		"adoptions_total": adoptions_total,
		"unlocked_content": _saved_unlocked_content()
	}

func _time_of_day_label() -> String:
	var length: float = maxf(1.0, day_length_sec)
	var f: float = clampf(day_time_sec / length, 0.0, 1.0)
	if f < 0.33:
		return "morning"
	if f < 0.66:
		return "afternoon"
	return "evening"

func _saved_unlocked_content() -> Array:
	if _saved_state_loaded:
		var u = _saved_state.get("unlocked_content", null)
		if u is Array:
			return (u as Array).duplicate(true)
	return ["basic_layout"]

func _init_run_state() -> void:
	var econ: Dictionary = balance.get("economy", {})
	money = int(econ.get("starting_money", 100))
	reputation = int(econ.get("starting_reputation", 0))
	day = 1
	day_time_sec = 0.0
	var pop: Dictionary = balance.get("population", {})
	day_length_sec = maxf(10.0, float(pop.get("day_length_sec", balance.get("trust", {}).get("day_length_sec", 180.0))))
	var saved: Dictionary = _get_saved_run_state()
	if not saved.is_empty():
		money = int(saved.get("money", money))
		reputation = int(saved.get("reputation", reputation))
		day = maxi(1, int(saved.get("day", day)))
		day_time_sec = clampf(float(saved.get("day_time_sec", 0.0)), 0.0, day_length_sec * 0.99)
		adoptions_total = maxi(0, int(saved.get("adoptions_total", 0)))

func _update_day_timer(delta: float) -> void:
	day_time_sec += delta
	if day_time_sec >= day_length_sec:
		day_time_sec -= day_length_sec
		day += 1
		save_run("day_end")
		day_changed.emit(day)

func _update_cat_drought() -> void:
	var cats: Array[Node3D] = get_cat_nodes()
	var active: bool = not cats.is_empty()
	for c in cats:
		if _is_cat_available(c):
			active = false
			break
	if active != cat_drought:
		cat_drought = active
		cat_drought_changed.emit(cat_drought)

# --- Save / load (B14) ------------------------------------------------------------

func _get_save_node() -> Node:
	return get_node_or_null("SaveSystem")

func _init_save_flags() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if args.has("--no-save"):
		use_save = false
	if args.has("--save"):
		force_save = true
	if not force_save:
		var is_main: bool = is_inside_tree() and get_tree().current_scene == self
		if DisplayServer.get_name() == "headless" or not is_main:
			use_save = false
	if args.has("--new-game") and use_save:
		clear_save()

## Loaded once per boot and cached (decor, cats and economy all restore from the same snapshot).
func _get_saved_run_state() -> Dictionary:
	if _saved_state_loaded:
		return _saved_state
	_saved_state_loaded = true
	_saved_state = {}
	if not use_save:
		return _saved_state
	var save_node: Node = _get_save_node()
	if save_node == null:
		return _saved_state
	if not save_node.has_method("has_save") or not save_node.has_method("load_run_state"):
		return _saved_state
	if not bool(save_node.call("has_save")):
		return _saved_state
	var state = save_node.call("load_run_state")
	if state is Dictionary:
		_saved_state = state
	if _saved_state.is_empty():
		# CR-3: a save exists but is from a newer build or unreadable. Never overwrite it.
		_save_blocked = true
		push_warning("Save exists but could not be loaded; saving is disabled for this session.")
		if is_inside_tree():
			get_tree().create_timer(1.0).timeout.connect(func():
				_hud_notice("Save is from a newer version or unreadable - progress will not be saved", 8.0))
	return _saved_state

## Writes the current run through SaveSystem.save_run_state. Returns true on success.
func save_run(reason: String = "manual") -> bool:
	if not use_save or _save_blocked:
		return false
	var save_node: Node = _get_save_node()
	if save_node == null or not save_node.has_method("save_run_state"):
		return false
	var state: Dictionary = get_run_state()
	var ok: bool = bool(save_node.call("save_run_state", state))
	run_saved.emit(ok, reason)
	return ok

## Deletes the save slot (and its .bak/.tmp siblings). Never touches it when saving is off
## (headless, probes, --no-save) (CR-4).
func clear_save() -> void:
	if not use_save:
		_saved_state = {}
		_saved_state_loaded = true
		return
	var save_node: Node = _get_save_node()
	var path: String = "user://run_state.json"
	if save_node != null:
		var p = save_node.get("save_path")
		if p is String and not (p as String).is_empty():
			path = p
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	_saved_state = {}
	_saved_state_loaded = true

## F9 (twice): wipe the save and reboot the level with the starter layout.
func start_new_game() -> void:
	clear_save()
	_save_blocked = true
	if is_inside_tree():
		get_tree().reload_current_scene()

func _hud_notice(text: String, seconds: float) -> void:
	var hud: Node = get_node_or_null("HUD3D")
	if hud != null and hud.has_method("show_notice"):
		hud.call("show_notice", text, seconds)

# --- Data -----------------------------------------------------------------------

func _init_seeds() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		var a: String = String(arg)
		if a.begins_with("--seed="):
			run_seed = int(a.get_slice("=", 1))
	var saved: Dictionary = _get_saved_run_state()
	var salt: int = 0
	if not saved.is_empty():
		if run_seed == 0 and int(saved.get("run_seed", 0)) != 0:
			run_seed = int(saved.get("run_seed", 0))
		# Resumed runs must not replay the first session's cat/patron draws.
		salt = int(saved.get("day", 1)) * 1000 + _as_array(saved.get("cats", [])).size()
	if run_seed == 0:
		var r := RandomNumberGenerator.new()
		r.randomize()
		run_seed = maxi(1, r.randi() & 0x7fffffff)
	_seed_salt = salt
	rng.seed = hash([run_seed, "level", salt])
	cat_rng.seed = hash([run_seed, "cats", salt])
	patron_rng.seed = hash([run_seed, "patrons", salt])

## Per-actor deterministic seed.
func get_actor_seed(kind: String, seq: int) -> int:
	if _seed_salt == 0:
		return hash([run_seed, kind, seq])
	return hash([run_seed, kind, seq, _seed_salt])

func _load_data() -> void:
	if data_loader != null and data_loader.has_method("load_all_data"):
		data = data_loader.load_all_data()
	else:
		data = {}
	var bc = data.get("balance_config", {})
	balance = bc if bc is Dictionary else {}
	for d in DataLoaderScript.entries_of(data.get("decor", [])):
		if typeof(d) == TYPE_DICTIONARY:
			decor_data_by_id[String(d.get("id", ""))] = d
	for u in DataLoaderScript.entries_of(data.get("decor_ui", [])):
		if typeof(u) == TYPE_DICTIONARY:
			decor_ui_by_id[String(u.get("id", ""))] = u
	for m in DataLoaderScript.entries_of(data.get("decor_mesh_map", [])):
		if typeof(m) == TYPE_DICTIONARY:
			decor_mesh_by_id[String(m.get("decor_id", ""))] = (m as Dictionary).duplicate(true)
	_init_cat_factory()

func _init_cat_factory() -> void:
	if not ResourceLoader.exists(CAT_FACTORY_PATH):
		return
	var script = load(CAT_FACTORY_PATH)
	if script is Script and (script as Script).can_instantiate():
		cat_factory = (script as Script).new(data)

func _as_array(v) -> Array:
	return v if v is Array else []

## Reads rooms[0] (3D shape, base tiles) before subdivision; falls back to the exports.
func _apply_room_data() -> void:
	var rooms: Array = _as_array(data.get("rooms", []))
	if rooms.is_empty() or typeof(rooms[0]) != TYPE_DICTIONARY:
		return
	var room: Dictionary = rooms[0]
	var unit: int = maxi(1, int(room.get("grid_unit", 1)))
	if room.get("cafe_floor_rect", null) is Dictionary:
		cafe_floor_rect = _dict_to_rect(room["cafe_floor_rect"], unit)
	if room.get("rest_area_rect", null) is Dictionary:
		rest_area_rect = _dict_to_rect(room["rest_area_rect"], unit)
	_room_door_base = _dict_cells(room.get("rest_door_cells", []), unit)
	var ent = room.get("entrance_cell", null)
	if ent is Dictionary:
		_room_entrance_base = Vector2i(int(ent.get("x", 0)), int(ent.get("y", 0))) * unit
	_room_patron_spawns_base = _dict_cells(room.get("patron_spawns", []), unit)
	_room_cat_spawns_base = _dict_cells(room.get("cat_spawns", []), unit)

func _dict_to_rect(d: Dictionary, unit: int) -> Rect2i:
	return Rect2i(Vector2i(int(d.get("x", 0)), int(d.get("y", 0))) * unit, Vector2i(int(d.get("w", 1)), int(d.get("h", 1))) * unit)

func _dict_cells(raw, unit: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for item in _as_array(raw):
		if item is Dictionary:
			out.append(Vector2i(int(item.get("x", 0)), int(item.get("y", 0))) * unit)
		elif item is Array and (item as Array).size() >= 2:
			out.append(Vector2i(int(item[0]), int(item[1])) * unit)
	return out

## Converts room cells from base tiles to level cells and builds the door edges.
func _resolve_room_cells() -> void:
	var f: int = maxi(1, mini_tiles_per_axis)
	var center := Vector2i(f / 2, f / 2)
	var door_candidates: Array[Vector2i] = []
	if not rest_door_cells.is_empty():
		door_candidates = rest_door_cells.duplicate()
	elif not _room_door_base.is_empty():
		for b in _room_door_base:
			for j in range(f):
				for i in range(f):
					door_candidates.append(b * f + Vector2i(i, j))
	else:
		var x: int = rest_area_rect.end.x
		var cy: int = rest_area_rect.position.y + rest_area_rect.size.y / 2
		for y in range(cy - f, cy + f):
			door_candidates.append(Vector2i(x, y))
	_door_cafe_cells.clear()
	_door_rest_cells.clear()
	_door_edges.clear()
	for c in door_candidates:
		if not is_in_cafe_floor(c) or is_in_rest_area(c):
			continue
		for d in DIRS4:
			var r: Vector2i = c + d
			if is_in_rest_area(r):
				_door_edges[_edge_key(c, r)] = true
				if not _door_cafe_cells.has(c):
					_door_cafe_cells.append(c)
				if not _door_rest_cells.has(r):
					_door_rest_cells.append(r)
	if _door_edges.is_empty():
		push_warning("MainLevel3D: no valid rest door cells; rest partition is open on every edge.")

	var floor_max: Vector2i = cafe_floor_rect.end - Vector2i.ONE
	if _room_entrance_base.x >= 0:
		entrance_cell = _clamp_to_floor(_room_entrance_base * f + center)
	else:
		entrance_cell = Vector2i(floor_max.x, cafe_floor_rect.position.y + cafe_floor_rect.size.y / 2)
	patron_spawn_cells.clear()
	for b in _room_patron_spawns_base:
		patron_spawn_cells.append(_clamp_to_floor(b * f + center))
	if patron_spawn_cells.is_empty():
		patron_spawn_cells.append(entrance_cell)
	cat_spawn_cells.clear()
	for b in _room_cat_spawns_base:
		cat_spawn_cells.append(_clamp_to_floor(b * f + center))
	if cat_spawn_cells.is_empty():
		for b in [Vector2i(6, 5), Vector2i(8, 4), Vector2i(7, 7)]:
			cat_spawn_cells.append(_clamp_to_floor(b * f + center))

func _clamp_to_floor(c: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(c.x, cafe_floor_rect.position.x, cafe_floor_rect.end.x - 1),
		clampi(c.y, cafe_floor_rect.position.y, cafe_floor_rect.end.y - 1))

## Expands decor_mesh_map footprints/slots into level cells. Per entry, "grid_unit" is the
## number of level cells per authored unit: 1 = authored in level cells (0.7 m). Missing =
## legacy base tiles, expanded by mini_tiles_per_axis.
func _prepare_decor_mesh_entries() -> void:
	var f: int = maxi(1, mini_tiles_per_axis)
	for key in decor_mesh_by_id.keys():
		var entry: Dictionary = decor_mesh_by_id[key]
		var unit: int = int(entry.get("grid_unit", f))
		unit = maxi(1, unit)
		var cells: Array[Vector2i] = []
		for raw in _as_array(entry.get("footprint", [])):
			var arr: Array = raw
			if arr.size() < 2:
				continue
			var off := Vector2i(int(arr[0]), int(arr[1]))
			for j in range(unit):
				for i in range(unit):
					var c: Vector2i = off * unit + Vector2i(i, j)
					if not cells.has(c):
						cells.append(c)
		if cells.is_empty():
			cells.append(Vector2i.ZERO)
		var slots: Dictionary = {}
		var markers = entry.get("slot_markers", {})
		if markers is Dictionary:
			for kind_key in (markers as Dictionary).keys():
				var list: Array[Vector2i] = []
				for raw in _as_array(markers[kind_key]):
					var arr: Array = raw
					if arr.size() < 2:
						continue
					var off := Vector2i(int(arr[0]), int(arr[1]))
					var sc: Vector2i = off * unit
					if off.x < 0:
						sc.x += unit - 1
					if off.y < 0:
						sc.y += unit - 1
					list.append(sc)
				slots[String(kind_key)] = list
		entry["footprint_cells"] = cells
		entry["slot_cells"] = slots
		decor_mesh_by_id[key] = entry
	if strict_blocking_from_mesh_bounds:
		_apply_mesh_bounds_blocking_footprints()
	_validate_decor_slots()

## Load-time check: warns for every decor/rotation whose slot falls on its own footprint.
func _validate_decor_slots() -> void:
	for key in decor_mesh_by_id.keys():
		var decor_id: String = String(key)
		var entry: Dictionary = decor_mesh_by_id[key]
		var walkable: bool = _is_decor_walkable(decor_id)
		for rot_raw in _as_array(entry.get("rotations", [0])):
			var rot: int = _normalize_rotation(int(rot_raw))
			var occ: Array[Vector2i] = _occupied_cells(Vector2i.ZERO, entry, rot)
			var seen: Dictionary = {}
			for slot in _slot_cells_for(Vector2i.ZERO, entry, rot):
				var sc: Vector2i = slot.get("cell", Vector2i.ZERO)
				if not walkable and occ.has(sc):
					push_warning("decor_mesh_map: %s rot %d slot %s %s is inside its own footprint" % [decor_id, rot, String(slot.get("kind", "")), str(sc)])
				if seen.has(sc):
					push_warning("decor_mesh_map: %s rot %d has two slots on cell %s" % [decor_id, rot, str(sc)])
				seen[sc] = true

func _apply_mesh_bounds_blocking_footprints() -> void:
	for key in decor_mesh_by_id.keys():
		var decor_id: String = String(key)
		var entry: Dictionary = decor_mesh_by_id.get(decor_id, {})
		var scene_path: String = String(entry.get("mesh_scene", ""))
		if scene_path.is_empty():
			continue
		var computed_offsets: Array[Vector2i] = _compute_mesh_scene_blocking_offsets(scene_path, get_decor_scale(decor_id))
		if computed_offsets.is_empty():
			continue
		entry["footprint_cells"] = computed_offsets
		decor_mesh_by_id[decor_id] = entry

func _compute_mesh_scene_blocking_offsets(scene_path: String, scale_v: Vector3 = Vector3.ONE) -> Array[Vector2i]:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return []
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		inst.free()
		return []
	var bounds: Dictionary = _collect_mesh_bounds(inst as Node3D, Transform3D(Basis.from_scale(scale_v), Vector3.ZERO))
	inst.free()
	if not bool(bounds.get("has", false)):
		return []
	var aabb: AABB = bounds.get("aabb", AABB())
	var cells_x: int = maxi(1, int(ceil(aabb.size.x / maxf(cell_width_3d, 0.001) - 0.01)))
	var cells_z: int = maxi(1, int(ceil(aabb.size.z / maxf(cell_depth_3d, 0.001) - 0.01)))
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
			merged = xform * mi.mesh.get_aabb()
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

# --- Starter layout ---------------------------------------------------------------

func _place_starting_decor() -> void:
	var placements: Array = []
	var saved: Dictionary = _get_saved_run_state()
	# A save written by this level (has day_time_sec) is authoritative even when empty;
	# older/template saves with no decor fall back to the starter layout.
	if saved.get("placed_decor", null) is Array and (saved.has("day_time_sec") or not (saved["placed_decor"] as Array).is_empty()):
		placements = saved["placed_decor"]
	else:
		placements = _load_starter_layout()
	for item in placements:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var decor_id: String = String(item.get("decor_id", ""))
		var anchor_raw = item.get("anchor", [])
		var anchor := Vector2i.ZERO
		if anchor_raw is Array and (anchor_raw as Array).size() >= 2:
			anchor = Vector2i(int(anchor_raw[0]), int(anchor_raw[1]))
		elif anchor_raw is Dictionary:
			anchor = Vector2i(int(anchor_raw.get("x", 0)), int(anchor_raw.get("y", 0)))
		else:
			continue
		var rot: int = int(item.get("rotation", 0))
		var reason: String = get_place_block_reason(anchor, decor_id, rot)
		if not reason.is_empty():
			push_warning("Starter decor %s at %s rot %d skipped: %s" % [decor_id, str(anchor), rot, reason])
			continue
		var paid_raw = item.get("paid", 0)
		place_decor(anchor, decor_id, rot, int(paid_raw) if (paid_raw is int or paid_raw is float) else 0)

func _load_starter_layout() -> Array:
	if not FileAccess.file_exists(STARTER_LAYOUT_PATH):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STARTER_LAYOUT_PATH))
	if parsed is Dictionary:
		return _as_array((parsed as Dictionary).get("placed_decor", []))
	if parsed is Array:
		return parsed
	push_warning("Could not parse %s" % STARTER_LAYOUT_PATH)
	return []

# --- Spawning ------------------------------------------------------------------------

func _spawn_actors() -> void:
	var pop: Dictionary = balance.get("population", {})
	var saved_cats: Array = _as_array(_get_saved_run_state().get("cats", []))
	if cats_to_spawn < 0 and not saved_cats.is_empty():
		for def in saved_cats:
			if def is Dictionary:
				spawn_cat(Vector2i(-9999, -9999), _restore_json_ints(def))
	else:
		var n_cats: int = cats_to_spawn if cats_to_spawn >= 0 else int(pop.get("starting_cats", 3))
		for _i in range(n_cats):
			spawn_cat()
	# A couple of patrons are already inside when the cafe opens; the rest arrive through
	# the entrance on the spawn timer (_update_patron_spawning).
	var n_patrons: int = patrons_to_spawn if patrons_to_spawn >= 0 else mini(2, int(pop.get("patron_target_count", 4)))
	for _i in range(n_patrons):
		spawn_patron()
	_patron_spawn_timer = 2.0

## JSON reloads every number as float; turn whole-number floats under integer keys back
## into ints so a restored cat def re-saves identically (seed, genome_version, ...).
const _SAVE_INT_KEYS: Array[String] = ["seed", "genome_version", "seq", "age_days", "visits"]

func _restore_json_ints(value: Variant, key: String = "") -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		for k in (value as Dictionary).keys():
			out[k] = _restore_json_ints(value[k], str(k))
		return out
	if value is Array:
		var arr: Array = []
		for v in value:
			arr.append(_restore_json_ints(v, key))
		return arr
	if typeof(value) == TYPE_FLOAT and _SAVE_INT_KEYS.has(key) and is_equal_approx(float(value), roundf(float(value))):
		return int(value)
	return value

func generate_cat_def(source_id: String = "") -> Dictionary:
	var seq: int = _cat_seq
	if cat_factory == null or not cat_factory.has_method("generate_cat"):
		return {"id": "cat_%04d" % seq, "display_name": "Foster Cat %d" % (seq + 1), "seed": get_actor_seed("cat", seq)}
	var argc: int = _method_arg_count(cat_factory, "generate_cat")
	var def = null
	if argc >= 4:
		def = cat_factory.call("generate_cat", cat_rng, seq, source_id, _cafe_cat_looks())
	elif argc >= 3:
		def = cat_factory.call("generate_cat", cat_rng, seq, source_id)
	else:
		def = cat_factory.call("generate_cat", cat_rng, seq)
	return def if def is Dictionary else {}

## Coats and names of the cats currently in the cafe, so new cats avoid repeats.
func _cafe_cat_looks() -> Dictionary:
	var coats: Array = []
	var names: Array = []
	for c in get_tree().get_nodes_in_group("cats"):
		if c.is_queued_for_deletion():
			continue
		var d: Variant = c.get("cat_def")
		if not (d is Dictionary):
			continue
		var g: Dictionary = d.get("genome", {}) if d.get("genome", {}) is Dictionary else {}
		var v: Dictionary = d.get("visual", {}) if d.get("visual", {}) is Dictionary else {}
		var coat: String = str(g.get("coat", v.get("coat", "")))
		if not coat.is_empty():
			coats.append(coat)
		names.append(str(d.get("display_name", "")))
	return {"coats": coats, "names": names}

func spawn_cat(cell: Vector2i = Vector2i(-9999, -9999), cat_def: Dictionary = {}) -> Node3D:
	var spawn_cell: Vector2i = cell
	if spawn_cell.x == -9999:
		if _cat_seq < cat_spawn_cells.size():
			spawn_cell = cat_spawn_cells[_cat_seq]
		else:
			spawn_cell = random_cafe_cell()
	spawn_cell = nearest_walkable_cell(spawn_cell, false)
	var def: Dictionary = cat_def if not cat_def.is_empty() else generate_cat_def()
	_cat_seq += 1
	var cat: Node3D = Cat3DScene.instantiate()
	cat.name = "Cat3D_%d" % cat_layer.get_child_count()
	# Render mode before _ready so the rig viewport is sized once.
	cat.set("pixel_art", cat_pixel_art)
	cat.set("pixel_density", cat_pixel_density)
	cat_layer.add_child(cat)
	if cat.has_signal("trust_state_changed"):
		cat.connect("trust_state_changed", func(c, o, n): cat_trust_changed.emit(c, o, n))
	if _method_arg_count(cat, "configure") >= 4:
		cat.call("configure", self, spawn_cell, def, balance)
	else:
		cat.set_meta("cat_def", def)
		cat.call("configure", self, spawn_cell)
	_apply_debug_to_cat(cat)
	return cat

## Weighted archetype pick. Placed decor "<prefix>_spawn_bias" buffs (book_nook
## gentle_reader_spawn_bias, quiet_signage hyper_spawn_bias) shift weight toward/away from
## every archetype whose id starts with <prefix>, scaled by the pool's total base weight.
func pick_patron_archetype() -> Dictionary:
	var pool: Array = _as_array(data.get("patron_archetypes", []))
	var weights: Array[float] = get_patron_archetype_weights(pool)
	var total: float = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return {}
	var roll: float = patron_rng.randf() * total
	for i in range(pool.size()):
		roll -= weights[i]
		if roll <= 0.0 and pool[i] is Dictionary:
			return (pool[i] as Dictionary).duplicate(true)
	return {}

func get_patron_archetype_weights(pool: Array = []) -> Array[float]:
	if pool.is_empty():
		pool = _as_array(data.get("patron_archetypes", []))
	var base_total: float = 0.0
	for a in pool:
		if a is Dictionary:
			base_total += maxf(0.0, float(a.get("spawn_weight", 1.0)))
	var biases: Dictionary = {}
	for key in decor_instances.keys():
		var decor_id: String = String(decor_instances[key].get("decor_id", ""))
		var buffs = decor_data_by_id.get(decor_id, {}).get("buffs", {})
		if not (buffs is Dictionary):
			continue
		for bk in (buffs as Dictionary).keys():
			var k: String = String(bk)
			var v = buffs[bk]
			if k.ends_with("_spawn_bias") and (v is float or v is int):
				var prefix: String = k.trim_suffix("_spawn_bias")
				biases[prefix] = float(biases.get(prefix, 0.0)) + float(v)
	var out: Array[float] = []
	for a in pool:
		if not (a is Dictionary):
			out.append(0.0)
			continue
		var w: float = maxf(0.0, float(a.get("spawn_weight", 1.0)))
		var id: String = String(a.get("id", ""))
		for prefix in biases.keys():
			if id.begins_with(String(prefix)):
				w += float(biases[prefix]) * base_total
		out.append(maxf(0.05, w) if w > 0.0 or float(a.get("spawn_weight", 1.0)) > 0.0 else 0.0)
	return out

## Number of patrons inside that are not on their way out.
func get_active_patron_count() -> int:
	var n: int = 0
	for p in get_patron_nodes():
		if not _is_patron_leaving(p):
			n += 1
	return n

## Patron target follows the day: quiet at opening/closing, a lunch rush mid-day.
func get_patron_target_count() -> int:
	var pop: Dictionary = balance.get("population", {})
	var base: int = int(pop.get("patron_target_count", 4))
	var max_n: int = maxi(base, int(pop.get("patron_max_count", 6)))
	var t: float = clampf(day_time_sec / maxf(1.0, day_length_sec), 0.0, 1.0)
	var rush: float = sin(t * PI)
	var target: float = lerpf(float(base) - 1.0, float(max_n), rush * rush)
	return clampi(int(round(target)), 1, max_n)

func _update_patron_spawning(delta: float) -> void:
	if not spawn_patrons_over_time:
		return
	_patron_spawn_timer -= delta
	if _patron_spawn_timer > 0.0:
		return
	var pop: Dictionary = balance.get("population", {})
	var interval: float = maxf(1.0, float(pop.get("patron_spawn_interval_sec", 8.0)))
	_patron_spawn_timer = interval * patron_rng.randf_range(0.7, 1.3)
	var max_n: int = maxi(1, int(pop.get("patron_max_count", 6)))
	if get_active_patron_count() >= get_patron_target_count() or get_patron_nodes().size() >= max_n + 2:
		return
	spawn_patron(true)

## at_entrance=false spawns on a random floor cell (initial crowd); true uses the room spawns.
func spawn_patron(at_entrance: bool = false, archetype: Dictionary = {}) -> Node3D:
	var spawn_cell: Vector2i
	if at_entrance and not patron_spawn_cells.is_empty():
		spawn_cell = patron_spawn_cells[patron_rng.randi_range(0, patron_spawn_cells.size() - 1)]
	else:
		spawn_cell = random_cafe_cell()
	spawn_cell = nearest_walkable_cell(spawn_cell, false)
	var arch: Dictionary = archetype if not archetype.is_empty() else pick_patron_archetype()
	var seq: int = _patron_seq
	_patron_seq += 1
	var patron: Node3D = Human3DScene.instantiate()
	patron.name = "Human3D_%d" % seq
	patron_layer.add_child(patron)
	if patron.has_signal("patron_left"):
		patron.connect("patron_left", _on_patron_left)
	var argc: int = _method_arg_count(patron, "configure")
	if argc >= 4:
		patron.call("configure", self, spawn_cell, arch, get_actor_seed("patron", seq))
	elif argc == 3:
		patron.call("configure", self, spawn_cell, arch)
	else:
		patron.call("configure", self, spawn_cell)
	# Patrons placed inside at boot are mid-visit, so the first tips arrive within the first minute.
	if not at_entrance and patron.get("visit_timer") != null:
		patron.set("visit_timer", float(patron.get("visit_timer")) * patron_rng.randf_range(0.3, 0.6))
	return patron

func _on_patron_left(patron) -> void:
	patron_left.emit(patron)

func _method_arg_count(obj: Object, method: String) -> int:
	if obj == null:
		return -1
	for m in obj.get_method_list():
		if String(m.get("name", "")) == method:
			return (m.get("args", []) as Array).size()
	return -1

# --- Footprint helpers ------------------------------------------------------------------

func _is_decor_walkable(decor_id: String) -> bool:
	return bool(decor_data_by_id.get(decor_id, {}).get("placement", {}).get("walkable", false))

func _occupied_cells(anchor: Vector2i, mesh_entry: Dictionary, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var norm: Dictionary = _normalized_offsets(mesh_entry, rot)
	for off in norm.get("offsets", []):
		out.append(anchor + (off as Vector2i))
	return out

func _slot_cells_for(anchor: Vector2i, mesh_entry: Dictionary, rot: int) -> Array:
	var out: Array = []
	var shift: Vector2i = _normalized_offsets(mesh_entry, rot).get("shift", Vector2i.ZERO)
	var slots: Dictionary = mesh_entry.get("slot_cells", {})
	for kind_key in slots.keys():
		for off in slots[kind_key]:
			out.append({"kind": StringName(kind_key), "cell": anchor + rotate_offset(off as Vector2i, rot) - shift})
	return out

func _register_decor_slots(anchor: Vector2i, mesh_entry: Dictionary, rot: int, owner_key: String) -> Array[int]:
	var out: Array[int] = []
	for slot in _slot_cells_for(anchor, mesh_entry, rot):
		var cell: Vector2i = slot.get("cell", Vector2i.ZERO)
		var id: int = int(slot_manager.call("add_slot", slot.get("kind", &""), cell, map_to_world(cell), owner_key))
		out.append(id)
	return out

func _footprint_world_center_offset(mesh_entry: Dictionary, rot: int) -> Vector3:
	var offsets: Array = _normalized_offsets(mesh_entry, rot).get("offsets", [])
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

## Rotated footprint (level cells) shifted so its min corner is (0,0). The same shift is
## applied to slot cells, so occupancy and slots always agree.
func _normalized_offsets(mesh_entry: Dictionary, rot: int) -> Dictionary:
	var rotated: Array[Vector2i] = []
	for raw in mesh_entry.get("footprint_cells", []):
		rotated.append(rotate_offset(raw as Vector2i, rot))
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
	return Vector2i(rng.randi_range(rect.position.x, rect.end.x - 1), rng.randi_range(rect.position.y, rect.end.y - 1))

func _random_walkable_cell(allow_rest_area: bool, rect: Rect2i) -> Vector2i:
	for _i in range(64):
		var c: Vector2i = _random_cell_in_rect(rect)
		if is_walkable(c, allow_rest_area):
			return c
	var candidates: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if is_walkable(c, allow_rest_area):
				candidates.append(c)
	if not candidates.is_empty():
		return candidates[rng.randi_range(0, candidates.size() - 1)]
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

# --- Camera (orthographic diorama, contract 1.6) ---------------------------------------

var _cam_target: Vector3 = Vector3.ZERO
var _cam_fit_center: Vector3 = Vector3.ZERO
var _cam_fit_size: float = 16.5
var _cam_size_goal: float = 12.0
var _cam_dragging: bool = false
var _build_grid_shown: bool = false
var _build_grid_requested: bool = false

func _frame_camera_to_floor() -> void:
	if camera == null:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.far = camera_distance * 3.0
	_refit_camera()
	_cam_size_goal = clampf(camera_default_size, camera_min_size, _camera_max_zoom_size())
	camera.size = _cam_size_goal
	# Start on the fit center so the entrance and the front of the floor stay on screen (V1).
	_cam_target = _clamp_camera_target(_cam_fit_center, _cam_size_goal)
	_apply_camera_transform()
	var vp: Viewport = get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_camera_viewport_resized):
		vp.size_changed.connect(_on_camera_viewport_resized)

## Direct size fit: projects the room bounds onto the camera plane (x camera_fit_padding).
func _refit_camera() -> void:
	var b: Dictionary = get_floor_world_bounds()
	var center := Vector3((float(b["min_x"]) + float(b["max_x"])) * 0.5, 0.0, (float(b["min_z"]) + float(b["max_z"])) * 0.5)
	var cb: Basis = _camera_basis()
	var min_px: float = INF
	var max_px: float = -INF
	var min_py: float = INF
	var max_py: float = -INF
	for p in _get_floor_bounds_points():
		var rel: Vector3 = p - center
		var px: float = rel.dot(cb.x)
		var py: float = rel.dot(cb.y)
		min_px = minf(min_px, px)
		max_px = maxf(max_px, px)
		min_py = minf(min_py, py)
		max_py = maxf(max_py, py)
	var aspect: float = _viewport_aspect()
	_cam_fit_size = maxf(max_py - min_py, (max_px - min_px) / aspect) * camera_fit_padding
	_cam_fit_center = center + cb.x * ((min_px + max_px) * 0.5) + cb.y * ((min_py + max_py) * 0.5)

func _on_camera_viewport_resized() -> void:
	if camera == null:
		return
	_refit_camera()
	_cam_size_goal = clampf(_cam_size_goal, camera_min_size, _camera_max_zoom_size())
	_cam_target = _clamp_camera_target(_cam_target, _cam_size_goal)

func _camera_max_zoom_size() -> float:
	return maxf(camera_max_size, _cam_fit_size)

func _viewport_aspect() -> float:
	var vp: Viewport = get_viewport()
	if vp == null:
		return 16.0 / 9.0
	var s: Vector2 = vp.get_visible_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return 16.0 / 9.0
	return s.x / s.y

func _camera_basis() -> Basis:
	var yaw: float = deg_to_rad(iso_yaw_degrees)
	var pitch: float = deg_to_rad(iso_pitch_degrees)
	var back := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
	return Basis.looking_at(-back, Vector3.UP)

func _apply_camera_transform() -> void:
	var cb: Basis = _camera_basis()
	camera.global_transform = Transform3D(cb, _cam_target + cb.z * camera_distance)

## Pan range shrinks as the camera zooms out; at the full-room fit it locks to the fit center.
func _clamp_camera_target(t: Vector3, size: float) -> Vector3:
	var b: Dictionary = get_floor_world_bounds()
	var span: float = maxf(0.001, _cam_fit_size - camera_min_size)
	var freedom: float = clampf((_cam_fit_size - size) / span, 0.0, 1.0)
	var half_x: float = (float(b["max_x"]) - float(b["min_x"])) * 0.5 * freedom
	var half_z: float = (float(b["max_z"]) - float(b["min_z"])) * 0.5 * freedom
	var c: Vector3 = _cam_fit_center
	# V2: height follows the fit center as the camera zooms out, so the room re-centres.
	var ty: float = lerpf(c.y, t.y, freedom)
	return Vector3(clampf(t.x, c.x - half_x, c.x + half_x), ty, clampf(t.z, c.z - half_z, c.z + half_z))

func _camera_ground_axes() -> Array[Vector3]:
	var cb: Basis = _camera_basis()
	var right := Vector3(cb.x.x, 0.0, cb.x.z).normalized()
	var forward := Vector3(-cb.z.x, 0.0, -cb.z.z).normalized()
	return [right, forward]

func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var move := Vector2.ZERO
	var focus: Control = get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit):
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y -= 1.0
	if move != Vector2.ZERO:
		var axes: Array[Vector3] = _camera_ground_axes()
		var speed: float = camera_pan_speed * (camera.size / maxf(1.0, camera_default_size))
		_cam_target += (axes[0] * move.x + axes[1] * move.y).normalized() * speed * delta
	var k: float = 1.0 - exp(-12.0 * delta)
	camera.size = lerpf(camera.size, _cam_size_goal, k)
	if absf(camera.size - _cam_size_goal) < 0.001:
		camera.size = _cam_size_goal
	_cam_target = _clamp_camera_target(_cam_target, camera.size)
	_apply_camera_transform()

func _is_holding_decor() -> bool:
	var placement: Node = get_node_or_null("DecorPlacement3D")
	if placement == null:
		return false
	var held = placement.get("holding_decor_id")
	return held != null and not String(held).is_empty()

## Returns true when the camera used the event (wheel zoom, middle-drag pan, Home overview).
func _camera_unhandled_input(event: InputEvent) -> bool:
	if camera == null:
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_cam_dragging = mb.pressed
			return true
		if not mb.pressed or _is_holding_decor():
			return false
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_size_goal = clampf(_cam_size_goal - camera_zoom_step, camera_min_size, _camera_max_zoom_size())
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_size_goal = clampf(_cam_size_goal + camera_zoom_step, camera_min_size, _camera_max_zoom_size())
			return true
	elif event is InputEventMouseMotion and _cam_dragging:
		var mm := event as InputEventMouseMotion
		var vp_h: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
		var world_per_px: float = camera.size / vp_h
		var axes: Array[Vector3] = _camera_ground_axes()
		var pitch_sin: float = maxf(0.2, sin(deg_to_rad(iso_pitch_degrees)))
		_cam_target -= axes[0] * mm.relative.x * world_per_px
		_cam_target += axes[1] * (mm.relative.y * world_per_px / pitch_sin)
		return true
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_HOME:
			if _cam_size_goal >= _cam_fit_size - 0.01:
				_cam_size_goal = clampf(camera_default_size, camera_min_size, _camera_max_zoom_size())
			else:
				_cam_size_goal = _cam_fit_size
				_cam_target = _cam_fit_center
			return true
	return false

## Room bounds for the camera fit: diorama base below the floor up to the wall tops.
func _get_floor_bounds_points() -> Array[Vector3]:
	var b: Dictionary = get_floor_world_bounds()
	var pad: float = 0.25
	var min_x: float = float(b["min_x"]) - pad
	var max_x: float = float(b["max_x"]) + pad
	var min_z: float = float(b["min_z"]) - pad
	var max_z: float = float(b["max_z"]) + pad
	var min_y: float = -0.7
	var max_y: float = 2.2
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

## The build grid is drawn only while holding decor, while the build panel is open, or
## while something (e.g. the HUD) requested it through set_build_grid_visible(true).
func _update_build_grid_visibility() -> void:
	var want: bool = _build_grid_requested or _is_holding_decor()
	if not want:
		var hud: Node = get_node_or_null("HUD3D")
		if hud != null and hud.has_method("is_build_panel_open"):
			want = bool(hud.call("is_build_panel_open"))
	if want == _build_grid_shown:
		return
	_build_grid_shown = want
	if floor_grid != null and floor_grid.has_method("set_grid_visible"):
		floor_grid.call("set_grid_visible", want)

## Public: request the build grid (OR-ed with holding decor / build panel open).
func set_build_grid_visible(on: bool) -> void:
	_build_grid_requested = on
	_update_build_grid_visibility()

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
	_resolve_room_cells()

func _scale_rect(rect: Rect2i, factor: int) -> Rect2i:
	return Rect2i(rect.position * factor, rect.size * factor)
