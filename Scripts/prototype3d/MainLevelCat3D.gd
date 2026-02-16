extends Node3D

const IDLE := &"idle"
const WANDER := &"wander"
const INTERACTING := &"interacting"
const RETREATING := &"retreating"
const REST := &"rest"

@export var move_speed: float = 2.8
@export var interaction_radius: float = 1.8
@export var overstimulation: float = 0.0
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
var retarget_timer: float = 0.0
var idle_timer: float = 0.0
var slot_seek_timer: float = 0.0
var current_slot_id: int = -1

@onready var sprite: Sprite3D = $Sprite3D

func configure(main_level, spawn_grid: Vector2i) -> void:
	level = main_level
	grid_position = spawn_grid
	target_grid = spawn_grid
	global_position = level.map_to_world(spawn_grid) + Vector3(0, level.actor_y_offset, 0)
	state = IDLE
	idle_timer = 1.0

func _ready() -> void:
	rng.randomize()
	retarget_timer = rng.randf_range(0.2, 0.9)
	idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)
	slot_seek_timer = rng.randf_range(slot_seek_interval_min, slot_seek_interval_max)

func _process(delta: float) -> void:
	if level == null:
		return
	grid_position = level.world_to_map(global_position)
	_resolve_if_embedded()
	var nearby: int = level.get_patrons_near(global_position, interaction_radius)
	_update_overstim(delta, nearby)
	_update_state(nearby)
	_update_pathing(delta)
	_follow_path(delta)
	_face_camera()
	_update_visual_state()

func _update_overstim(delta: float, nearby: int) -> void:
	if state == REST:
		overstimulation = maxf(0.0, overstimulation - overstim_recovery_per_sec * delta)
	elif state == INTERACTING:
		var mult: float = 1.0 + float(max(nearby - 1, 0)) * 0.35
		overstimulation = minf(overstim_threshold, overstimulation + overstim_gain_per_sec * mult * delta)
	else:
		overstimulation = maxf(0.0, overstimulation - passive_calm_per_sec * delta)

func _update_state(nearby: int) -> void:
	if state != RETREATING and state != REST and overstimulation >= overstim_threshold:
		_begin_retreat()
		return
	if state == RETREATING and level.is_in_rest_area(grid_position) and path.is_empty():
		state = REST
		_release_slot()
		return
	if state == REST and overstimulation <= rest_release_threshold:
		state = IDLE
		idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)
		return
	if nearby > 0:
		if state != INTERACTING:
			state = INTERACTING
			path.clear()
		return
	if state == INTERACTING and nearby <= 0:
		_release_slot()
		state = IDLE
		idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)

func _update_pathing(delta: float) -> void:
	if state == RETREATING:
		if path.is_empty() and not level.is_in_rest_area(grid_position):
			_begin_retreat()
		return
	if state == INTERACTING:
		_update_interacting(delta)
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
	path = level.build_path(grid_position, target_grid, false)

func _update_interacting(delta: float) -> void:
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
		_release_slot()

func _follow_path(delta: float) -> void:
	if path.is_empty():
		return
	var next_grid: Vector2i = path[0]
	var allow_rest: bool = state == RETREATING or state == REST
	if not level.is_walkable(next_grid, allow_rest):
		path.clear()
		if state == INTERACTING:
			_release_slot()
			state = IDLE
			idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)
		elif state == WANDER:
			retarget_timer = 0.0
		elif state == RETREATING:
			_begin_retreat()
		return
	var next_world: Vector3 = level.map_to_world(next_grid) + Vector3(0, level.actor_y_offset, 0)
	var step: Vector3 = next_world - global_position
	step.y = 0.0
	var distance: float = step.length()
	if distance <= 0.06:
		global_position = next_world
		grid_position = next_grid
		path.remove_at(0)
		return
	var travel: float = minf(distance, move_speed * delta)
	global_position += step.normalized() * travel

func _resolve_if_embedded() -> void:
	var allow_rest: bool = state == RETREATING or state == REST
	if level.is_walkable(grid_position, allow_rest):
		return
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		var candidate: Vector2i = grid_position + d
		if level.is_walkable(candidate, allow_rest):
			grid_position = candidate
			global_position = level.map_to_world(candidate) + Vector3(0, level.actor_y_offset, 0)
			path.clear()
			if state == INTERACTING:
				_release_slot()
				state = IDLE
				idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)
			return

func _begin_retreat() -> void:
	_release_slot()
	state = RETREATING
	target_grid = level.random_rest_cell()
	path = level.build_path(grid_position, target_grid, true)

func _release_slot() -> void:
	if current_slot_id == -1:
		return
	level.release_actor_slot(self)
	current_slot_id = -1

func _face_camera() -> void:
	var cam: Camera3D = level.get_active_camera()
	if cam == null:
		return
	look_at(Vector3(cam.global_position.x, global_position.y, cam.global_position.z), Vector3.UP)

func _update_visual_state() -> void:
	if state == RETREATING:
		sprite.modulate = Color(1.0, 0.75, 0.5)
	elif state == REST:
		sprite.modulate = Color(0.6, 1.0, 0.6)
	elif state == INTERACTING:
		sprite.modulate = Color(1.0, 0.72, 1.0)
	elif state == IDLE:
		sprite.modulate = Color(0.84, 0.94, 1.0)
	else:
		sprite.modulate = Color(1, 1, 1)

func on_slot_invalidated(slot_id: int) -> void:
	if slot_id != current_slot_id:
		return
	current_slot_id = -1
	path.clear()
	if state == INTERACTING:
		state = IDLE
		idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)
