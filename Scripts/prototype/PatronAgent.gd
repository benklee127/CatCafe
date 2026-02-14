extends Node2D

@export var speed: float = 56.0
@export var interaction_radius: float = 30.0

var archetype_id: String = "gentle_reader"
var overstim_impact: float = 14.0
var spend_rate: float = 1.0
var world_bounds := Rect2(Vector2(180, 180), Vector2(1200, 560))
var _target: Vector2
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	_target = _pick_target()
	queue_redraw()

func configure(source: Dictionary) -> void:
	archetype_id = source.get("id", archetype_id)
	overstim_impact = float(source.get("overstim_impact", overstim_impact))
	spend_rate = float(source.get("spend_rate", spend_rate))

func _process(delta: float) -> void:
	_move_toward(_target, delta)
	if global_position.distance_to(_target) < 10.0:
		_target = _pick_target()
	queue_redraw()

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

func _draw() -> void:
	draw_rect(Rect2(Vector2(-10, -10), Vector2(20, 20)), Color(0.2, 0.95, 0.2))
