extends Node3D

const WANDER := &"wander"
const USING_SLOT := &"using_slot"

@export var move_speed: float = 2.5
@export var slot_seek_chance: float = 0.65
@export var dwell_time_min: float = 2.5
@export var dwell_time_max: float = 5.0

var level
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var grid_position: Vector2i = Vector2i.ZERO
var target_grid: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var state: StringName = WANDER
var retarget_timer: float = 0.0
var dwell_timer: float = 0.0
var current_slot_id: int = -1

func configure(main_level, spawn_grid: Vector2i) -> void:
	level = main_level
	grid_position = spawn_grid
	target_grid = spawn_grid
	global_position = level.map_to_world(spawn_grid) + Vector3(0, level.actor_y_offset, 0)

func _ready() -> void:
	rng.randomize()
	retarget_timer = rng.randf_range(0.4, 1.2)

func _process(delta: float) -> void:
	if level == null:
		return
	grid_position = level.world_to_map(global_position)
	_update_state(delta)
	_follow_path(delta)
	_face_camera()

func _update_state(delta: float) -> void:
	if state == USING_SLOT:
		_process_slot(delta)
		return
	retarget_timer -= delta
	if retarget_timer > 0.0:
		return
	retarget_timer = rng.randf_range(1.0, 2.2)
	if rng.randf() <= slot_seek_chance and _try_claim_slot():
		return
	_set_wander_target(level.random_cafe_cell())

func _process_slot(delta: float) -> void:
	if current_slot_id == -1 or not level.has_slot(current_slot_id):
		_release_slot()
		state = WANDER
		return
	var slot_grid: Vector2i = level.get_slot_grid(current_slot_id)
	if grid_position != slot_grid:
		if path.is_empty():
			path = level.build_path(grid_position, slot_grid, false)
			if path.is_empty():
				_release_slot()
				state = WANDER
		return
	dwell_timer -= delta
	if dwell_timer <= 0.0:
		_release_slot()
		state = WANDER
		retarget_timer = rng.randf_range(0.3, 1.0)

func _try_claim_slot() -> bool:
	var slot_id: int = level.request_best_slot(&"patron", self, grid_position, false)
	if slot_id == -1:
		return false
	if not level.claim_slot(slot_id, self):
		return false
	current_slot_id = slot_id
	state = USING_SLOT
	dwell_timer = rng.randf_range(dwell_time_min, dwell_time_max)
	var slot_grid: Vector2i = level.get_slot_grid(current_slot_id)
	path = level.build_path(grid_position, slot_grid, false)
	if path.is_empty() and slot_grid != grid_position:
		_release_slot()
		state = WANDER
		return false
	return true

func _set_wander_target(next_grid: Vector2i) -> void:
	target_grid = next_grid
	path = level.build_path(grid_position, target_grid, false)

func _follow_path(delta: float) -> void:
	if path.is_empty():
		return
	var next_grid: Vector2i = path[0]
	var next_world: Vector3 = level.map_to_world(next_grid) + Vector3(0, level.actor_y_offset, 0)
	var step: Vector3 = next_world - global_position
	step.y = 0.0
	var dist: float = step.length()
	if dist <= 0.06:
		global_position = next_world
		grid_position = next_grid
		path.remove_at(0)
		return
	global_position += step.normalized() * move_speed * delta

func _release_slot() -> void:
	if level != null:
		level.release_actor_slot(self)
	current_slot_id = -1

func _face_camera() -> void:
	var cam: Camera3D = level.get_active_camera()
	if cam == null:
		return
	look_at(Vector3(cam.global_position.x, global_position.y, cam.global_position.z), Vector3.UP)

func on_slot_invalidated(slot_id: int) -> void:
	if slot_id != current_slot_id:
		return
	current_slot_id = -1
	state = WANDER
	retarget_timer = 0.0
	path.clear()
