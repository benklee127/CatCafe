extends Node2D

enum CatState { WANDER, RETREAT, REST }

@export var speed: float = 70.0
@export var overstim_max: float = 100.0
@export var rest_duration: float = 4.0

var definition: Dictionary = {}
var world_bounds := Rect2(Vector2(180, 180), Vector2(1200, 560))
var rest_point: Vector2 = Vector2(1280, 180)
var overstim: float = 0.0
var trust: float = 10.0
var state: CatState = CatState.WANDER
var _target: Vector2
var _rest_timer: float = 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	_target = _pick_target()
	queue_redraw()

func _process(delta: float) -> void:
	match state:
		CatState.WANDER:
			_move_toward(_target, delta)
			if global_position.distance_to(_target) < 10.0:
				_target = _pick_target()
		CatState.RETREAT:
			_move_toward(rest_point, delta)
			if global_position.distance_to(rest_point) < 12.0:
				state = CatState.REST
				_rest_timer = rest_duration
		CatState.REST:
			_rest_timer -= delta
			overstim = max(0.0, overstim - 25.0 * delta)
			if _rest_timer <= 0.0:
				state = CatState.WANDER
				_target = _pick_target()
	queue_redraw()

func apply_stimulation(amount: float, patron_archetype_id: String) -> void:
	if state == CatState.REST:
		return
	var trait_mult := _trait_overstim_mult()
	var adjusted := amount * trait_mult
	overstim = clamp(overstim + adjusted, 0.0, overstim_max)
	if overstim >= overstim_max:
		state = CatState.RETREAT

func _move_toward(target: Vector2, delta: float) -> void:
	var dir := (target - global_position).normalized()
	global_position += dir * speed * delta
	global_position.x = clamp(global_position.x, world_bounds.position.x, world_bounds.end.x)
	global_position.y = clamp(global_position.y, world_bounds.position.y, world_bounds.end.y)

func _pick_target() -> Vector2:
	return Vector2(
		rng.randf_range(world_bounds.position.x, world_bounds.end.x),
		rng.randf_range(world_bounds.position.y, world_bounds.end.y)
	)

func _trait_overstim_mult() -> float:
	var m := 1.0
	for t in definition.get("traits", []):
		m *= float(t.get("overstim_rate_mult", 1.0))
	return clamp(m, 0.5, 2.0)

func _draw() -> void:
	var color := Color(0.2, 0.55, 1.0)
	if state == CatState.RETREAT:
		color = Color(0.95, 0.65, 0.2)
	elif state == CatState.REST:
		color = Color(0.4, 0.9, 0.4)
	draw_circle(Vector2.ZERO, 14.0, color)
	var ratio := overstim / overstim_max
	draw_rect(Rect2(Vector2(-16, -24), Vector2(32, 4)), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(Vector2(-16, -24), Vector2(32 * ratio, 4)), Color(1.0, 0.3, 0.3))
