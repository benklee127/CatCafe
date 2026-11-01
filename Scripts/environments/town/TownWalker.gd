extends Node

## Simple townsfolk controller. Added as a child of a Human3D instance (MainLevelPatron3D
## script) that was NOT configure()d, so the patron's own cafe AI stays idle
## (its _physics_process returns while `level` is null). This node ping-pongs the body
## along a sidewalk route, pauses now and then (window shopping) and drives the patron
## art through the existing visual hooks (_is_moving / _walk_phase / _update_visuals,
## sprite.flip_h). Human3D / MainLevelPatron3D are not modified.

const L := preload("res://Scripts/environments/town/TownLayout.gd")

var body: Node3D
var route: Array = []
var speed: float = 1.1
var screen_right: Vector3 = Vector3(0.7071, 0.0, -0.7071)

var _idx: int = 1
var _dir: int = 1
var _pause: float = 0.0
var _rng := RandomNumberGenerator.new()
var _facing_left: bool = false

## look: optional archetype dict (gentle_reader / busy_remote_worker / hyper_toddler ...).
func setup(p_body: Node3D, p_route: Array, seed: int, start_t: float = 0.0, look: Dictionary = {}) -> void:
	body = p_body
	route = p_route
	_rng.seed = seed
	speed = _rng.randf_range(0.85, 1.25)
	if body.get("rng") is RandomNumberGenerator:
		(body.get("rng") as RandomNumberGenerator).seed = seed
	if body.has_method("_apply_archetype") and not look.is_empty():
		body.call("_apply_archetype", look)
		if bool(look.get("tags", []).has("active")):
			speed = 1.5
	if body.has_method("_setup_art"):
		body.call("_setup_art")
	# Start part-way along the first segment.
	_idx = 1
	var a: Vector3 = route[0]
	var b: Vector3 = route[1]
	var p: Vector3 = a.lerp(b, clampf(start_t, 0.0, 1.0))
	body.global_position = Vector3(p.x, L.surface_y(p.x, p.z), p.z)
	_pause = _rng.randf_range(0.0, 1.5)

func _physics_process(delta: float) -> void:
	if body == null or route.size() < 2:
		return
	var moving: bool = false
	if _pause > 0.0:
		_pause -= delta
	else:
		var goal: Vector3 = route[_idx]
		var pos: Vector3 = body.global_position
		var flat := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
		var dist: float = flat.length()
		var step: float = speed * delta
		if dist <= step:
			pos.x = goal.x
			pos.z = goal.z
			_advance()
		else:
			var dir: Vector3 = flat / dist
			pos.x += dir.x * step
			pos.z += dir.z * step
			_face(dir)
			moving = true
		pos.y = L.surface_y(pos.x, pos.z)
		body.global_position = pos
		if moving:
			var ph = body.get("_walk_phase")
			if ph is float:
				body.set("_walk_phase", float(ph) + speed * delta * 3.2)
	if "_is_moving" in body:
		body.set("_is_moving", moving)
	if body.has_method("_update_visuals"):
		body.call("_update_visuals", delta)

func _advance() -> void:
	var nxt: int = _idx + _dir
	if nxt < 0 or nxt >= route.size():
		_dir = -_dir
		nxt = _idx + _dir
		_pause = _rng.randf_range(1.5, 4.0)
	elif _rng.randf() < 0.35:
		_pause = _rng.randf_range(0.8, 2.5)
	_idx = nxt

func _face(dir: Vector3) -> void:
	var sx: float = dir.dot(screen_right)
	if absf(sx) < 0.15:
		return
	var left: bool = sx < 0.0
	if left == _facing_left:
		return
	_facing_left = left
	if "_facing_left" in body:
		body.set("_facing_left", left)
	var spr = body.get_node_or_null("BillboardAnchor/Sprite3D")
	if spr is Sprite3D:
		(spr as Sprite3D).flip_h = left

func is_moving() -> bool:
	return _pause <= 0.0
