extends Node2D

const WANDER := &"wander"
const USING_SLOT := &"using_slot"
const PATRON_TEXTURE: Texture2D = preload("res://Art_Assets/patrons/export/patron_placeholder_v001.png")

@export var move_speed: float = 100.0
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
var _sprite: Sprite2D

func configure(main_level, spawn_grid: Vector2i) -> void:
	level = main_level
	grid_position = spawn_grid
	target_grid = spawn_grid
	global_position = level.map_to_world(spawn_grid)

func _ready() -> void:
	rng.randomize()
	retarget_timer = rng.randf_range(0.4, 1.2)
	_ensure_sprite()
	queue_redraw()

func _process(delta: float) -> void:
	if level == null:
		return
	grid_position = level.world_to_map(global_position)
	_update_state(delta)
	_follow_path(delta)
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
	_sprite.texture = PATRON_TEXTURE
	_sprite.offset = Vector2(0, -12)

func _update_state(delta: float) -> void:
	if state == USING_SLOT:
		_process_using_slot(delta)
		return

	retarget_timer -= delta
	if retarget_timer > 0.0:
		return

	retarget_timer = rng.randf_range(1.0, 2.2)
	if rng.randf() <= slot_seek_chance and _try_claim_patron_slot():
		return
	_set_wander_target(level.random_cafe_cell())

func _process_using_slot(delta: float) -> void:
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

func _try_claim_patron_slot() -> bool:
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

func _release_slot() -> void:
	if level != null:
		level.release_actor_slot(self)
	current_slot_id = -1

func _update_depth() -> void:
	z_index = int(global_position.y)

func on_slot_invalidated(slot_id: int) -> void:
	if slot_id != current_slot_id:
		return
	current_slot_id = -1
	state = WANDER
	retarget_timer = 0.0
	path.clear()

func _draw() -> void:
	if _sprite == null:
		draw_rect(Rect2(Vector2(-9, -9), Vector2(18, 18)), Color(0.2, 0.95, 0.25))
	if state == USING_SLOT:
		draw_rect(Rect2(Vector2(-10, -22), Vector2(20, 4)), Color(0.15, 0.15, 0.15))
		var ratio: float = clamp(dwell_timer / maxf(dwell_time_max, 0.001), 0.0, 1.0)
		draw_rect(Rect2(Vector2(-10, -22), Vector2(20.0 * ratio, 4)), Color(0.65, 0.9, 0.3))
