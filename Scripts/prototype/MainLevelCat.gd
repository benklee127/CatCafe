extends Node2D

const IDLE := &"idle"
const WANDER := &"wander"
const INTERACTING := &"interacting"
const RETREATING := &"retreating"
const REST := &"rest"
const CAT_TEXTURE: Texture2D = preload("res://Art_Assets/cats/export/cat_placeholder_v001.png")

@export var move_speed: float = 120.0
@export var overstimulation: float = 0.0
@export var interaction_radius: float = 56.0
@export var overstim_gain_per_sec: float = 11.0
@export var overstim_recovery_per_sec: float = 24.0
@export var passive_calm_per_sec: float = 3.5
@export var overstim_threshold: float = 100.0
@export var rest_release_threshold: float = 35.0
@export var idle_duration_min: float = 0.6
@export var idle_duration_max: float = 1.8
@export var slot_seek_interval_min: float = 0.8
@export var slot_seek_interval_max: float = 1.6

var level
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var grid_position: Vector2i = Vector2i.ZERO
var target_grid: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var state: StringName = IDLE
var current_zone: StringName = &"CafeFloor"
var retarget_timer: float = 0.0
var idle_timer: float = 0.0
var slot_seek_timer: float = 0.0
var current_slot_id: int = -1
var _sprite: Sprite2D

func configure(main_level, spawn_grid: Vector2i) -> void:
	level = main_level
	grid_position = spawn_grid
	target_grid = spawn_grid
	global_position = level.map_to_world(spawn_grid)
	current_zone = _zone_name(grid_position)
	state = IDLE
	idle_timer = 1.0

func _ready() -> void:
	rng.randomize()
	retarget_timer = rng.randf_range(0.2, 0.9)
	idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)
	slot_seek_timer = rng.randf_range(slot_seek_interval_min, slot_seek_interval_max)
	_ensure_sprite()
	queue_redraw()

func _process(delta: float) -> void:
	if level == null:
		return

	grid_position = level.world_to_map(global_position)
	current_zone = _zone_name(grid_position)
	var nearby_patrons: int = level.get_patrons_near(global_position, interaction_radius)
	_update_overstimulation(delta, nearby_patrons)
	_update_zone_state(nearby_patrons)
	_update_pathing(delta)
	_follow_path(delta)
	_update_visual_state()
	_update_depth()
	queue_redraw()

func _ensure_sprite() -> void:
	if _sprite != null:
		return
	_sprite = get_node_or_null("Sprite2D")
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		add_child(_sprite)
	_sprite.texture = CAT_TEXTURE
	_sprite.offset = Vector2(0, -12)

func _update_overstimulation(delta: float, nearby_patrons: int) -> void:
	if state == REST:
		overstimulation = maxf(0.0, overstimulation - overstim_recovery_per_sec * delta)
	elif state == INTERACTING:
		var multiplier: float = 1.0 + float(max(nearby_patrons - 1, 0)) * 0.35
		overstimulation = minf(overstim_threshold, overstimulation + overstim_gain_per_sec * multiplier * delta)
	else:
		overstimulation = maxf(0.0, overstimulation - passive_calm_per_sec * delta)

func _update_zone_state(nearby_patrons: int) -> void:
	if state != RETREATING and state != REST and overstimulation >= overstim_threshold:
		_begin_retreat()
		return

	if state == RETREATING and level.is_in_rest_area(grid_position) and path.is_empty():
		state = REST
		_release_slot_claim()
		return

	if state == REST and overstimulation <= rest_release_threshold:
		state = IDLE
		idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)
		return

	if nearby_patrons > 0:
		if state != INTERACTING:
			state = INTERACTING
			path.clear()
		return

	if state == INTERACTING and nearby_patrons <= 0:
		_release_slot_claim()
		state = IDLE
		idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)

func _update_pathing(delta: float) -> void:
	if state == RETREATING:
		if path.is_empty() and not level.is_in_rest_area(grid_position):
			_begin_retreat()
		return

	if state == INTERACTING:
		_update_interacting_pathing(delta)
		return

	if state == IDLE:
		idle_timer -= delta
		if idle_timer <= 0.0:
			state = WANDER
			retarget_timer = 0.0
		return

	if state != WANDER:
		return

	retarget_timer -= delta
	if retarget_timer > 0.0:
		return

	retarget_timer = rng.randf_range(1.2, 2.4)
	target_grid = level.random_cafe_cell()
	if level.is_in_rest_area(target_grid):
		target_grid = Vector2i(level.rest_area_rect.end.x + 1, level.rest_area_rect.end.y + 1)
	path = level.build_path(grid_position, target_grid, false)

func _update_interacting_pathing(delta: float) -> void:
	if current_slot_id != -1:
		if not level.has_slot(current_slot_id):
			current_slot_id = -1
			return
		var slot_grid: Vector2i = level.get_slot_grid(current_slot_id)
		if grid_position != slot_grid and path.is_empty():
			path = level.build_path(grid_position, slot_grid, false)
		return

	slot_seek_timer -= delta
	if slot_seek_timer > 0.0:
		return
	slot_seek_timer = rng.randf_range(slot_seek_interval_min, slot_seek_interval_max)

	var slot_id: int = level.request_best_slot(&"cat", self, grid_position, false)
	if slot_id == -1:
		return
	if not level.claim_slot(slot_id, self):
		return
	current_slot_id = slot_id
	var slot_grid: Vector2i = level.get_slot_grid(current_slot_id)
	path = level.build_path(grid_position, slot_grid, false)
	if path.is_empty() and slot_grid != grid_position:
		_release_slot_claim()

func _follow_path(delta: float) -> void:
	if path.is_empty():
		return

	var next_grid: Vector2i = path[0]
	var next_world: Vector2 = level.map_to_world(next_grid)
	var step: Vector2 = next_world - global_position
	var distance: float = step.length()
	if distance <= 1.5:
		global_position = next_world
		grid_position = next_grid
		path.remove_at(0)
		return

	var dir: Vector2 = step / maxf(distance, 0.001)
	global_position += dir * move_speed * delta

func _begin_retreat() -> void:
	_release_slot_claim()
	state = RETREATING
	target_grid = _best_rest_cell()
	path = level.build_path(grid_position, target_grid, true)

func _best_rest_cell() -> Vector2i:
	var best_cell: Vector2i = level.random_rest_cell()
	var best_cost: int = 1_000_000
	for y in range(level.rest_area_rect.position.y, level.rest_area_rect.end.y):
		for x in range(level.rest_area_rect.position.x, level.rest_area_rect.end.x):
			var cell: Vector2i = Vector2i(x, y)
			if not level.is_walkable(cell, true):
				continue
			var cost: int = 0
			if cell != grid_position:
				var candidate_path: Array[Vector2i] = level.build_path(grid_position, cell, true)
				if candidate_path.is_empty():
					continue
				cost = candidate_path.size()
			if cost < best_cost:
				best_cost = cost
				best_cell = cell
	return best_cell

func _release_slot_claim() -> void:
	if current_slot_id == -1:
		return
	if level != null:
		level.release_actor_slot(self)
	current_slot_id = -1

func _update_depth() -> void:
	z_index = int(global_position.y)

func _update_visual_state() -> void:
	if _sprite == null:
		return
	if state == RETREATING:
		_sprite.modulate = Color(1.0, 0.78, 0.5)
	elif state == REST:
		_sprite.modulate = Color(0.6, 1.0, 0.6)
	elif state == INTERACTING:
		_sprite.modulate = Color(1.0, 0.7, 1.0)
	elif state == IDLE:
		_sprite.modulate = Color(0.8, 0.92, 1.0)
	else:
		_sprite.modulate = Color(1, 1, 1)

func on_slot_invalidated(slot_id: int) -> void:
	if slot_id != current_slot_id:
		return
	current_slot_id = -1
	path.clear()
	if state == INTERACTING:
		state = IDLE
		idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)

func _zone_name(grid_pos: Vector2i) -> StringName:
	if level.is_in_rest_area(grid_pos):
		return &"RestArea"
	if level.is_in_cafe_floor(grid_pos):
		return &"CafeFloor"
	return &"OutOfBounds"

func _draw() -> void:
	var body_color: Color = Color(0.2, 0.6, 1.0)
	if state == RETREATING:
		body_color = Color(1.0, 0.65, 0.2)
	elif state == REST:
		body_color = Color(0.35, 0.9, 0.45)
	elif state == INTERACTING:
		body_color = Color(0.95, 0.35, 0.95)
	elif state == IDLE:
		body_color = Color(0.35, 0.7, 1.0)
	if _sprite == null:
		draw_circle(Vector2.ZERO, 12.0, body_color)

	draw_rect(Rect2(Vector2(-16, -22), Vector2(32, 4)), Color(0.12, 0.12, 0.12))
	var ratio: float = overstimulation / maxf(overstim_threshold, 0.001)
	draw_rect(Rect2(Vector2(-16, -22), Vector2(32.0 * ratio, 4)), Color(1.0, 0.25, 0.25))
