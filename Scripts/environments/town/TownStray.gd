extends Node

## Simple alley-stray controller. Added as a child of a Cat3D instance (MainLevelCat3D
## script) that was NOT configure()d, so the cafe cat AI stays idle (its _physics_process
## returns while `level` is null). This node only uses the public Cat2D API:
## apply_genome, set_pose (idle/walk/sit/sleep), set_facing_left, set_move_speed and
## set_expression (existing expressions only). No new cat art.
##
## Modes:
##   ROAM  wander between random points inside TownLayout.STRAY_AREA, sit / nap / idle.
##   PEEK  hide in a doorstep box and peek out now and then (doorstep event spot).

const L := preload("res://Scripts/environments/town/TownLayout.gd")
const CatGenomeScript := preload("res://Scripts/prototype3d/CatGenome.gd")

enum Mode { ROAM, PEEK }

var body: Node3D
var cat2d: Node
var mode: int = Mode.ROAM
var area: Rect2 = L.STRAY_AREA
var screen_right: Vector3 = Vector3(0.7071, 0.0, -0.7071)
var speed: float = 0.85

var _rng := RandomNumberGenerator.new()
var _state: StringName = &"idle"
var _timer: float = 1.0
var _goal: Vector3 = Vector3.ZERO
var _pose: StringName = &""
var _expr: StringName = &""
var _shy_t: float = 0.0
var _peek_up: bool = false
var _peek_y: float = -0.3
var _anchor: Node3D

func setup(p_body: Node3D, coat: String, seed: int, p_mode: int = Mode.ROAM, facing_left: bool = false) -> void:
	body = p_body
	mode = p_mode
	_rng.seed = seed
	cat2d = body.get_node_or_null("CatViewport/Cat2D")
	_anchor = body.get_node_or_null("BillboardAnchor")
	if cat2d != null and cat2d.has_method("apply_genome"):
		var visual: Dictionary = {"coat": coat}
		cat2d.call("apply_genome", CatGenomeScript.from_visual(visual, seed))
	_set_facing(facing_left)
	if mode == Mode.PEEK:
		var shadow: Node3D = body.get_node_or_null("BlobShadow")
		if shadow != null:
			shadow.visible = false
		_set_pose(&"sit")
		_set_expr(&"worried")
		_timer = _rng.randf_range(1.0, 2.5)
		_peek_up = true
		_peek_y = 0.0
	else:
		_set_pose(&"idle")
		_set_expr(&"open")
		_timer = _rng.randf_range(0.5, 2.0)

## A short "startled" reaction (alley search / doorstep found): surprised face, then shy.
func startle() -> void:
	_shy_t = 2.5
	_set_expr(&"surprised")
	if mode == Mode.PEEK:
		_peek_up = true

func _physics_process(delta: float) -> void:
	if body == null:
		return
	if _shy_t > 0.0:
		_shy_t -= delta
		if _shy_t <= 0.0:
			_set_expr(&"worried" if mode == Mode.PEEK else (&"sleepy" if _state == &"nap" else &"open"))
	if mode == Mode.PEEK:
		_tick_peek(delta)
	else:
		_tick_roam(delta)

func _tick_peek(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_peek_up = not _peek_up
		_timer = _rng.randf_range(2.5, 5.0) if _peek_up else _rng.randf_range(1.5, 3.5)
		if _peek_up and _shy_t <= 0.0:
			_set_expr(&"worried" if _rng.randf() < 0.6 else &"open")
	var want: float = 0.0 if _peek_up else -0.32
	_peek_y = move_toward(_peek_y, want, delta * 0.9)
	if _anchor != null:
		_anchor.position.y = _peek_y

func _tick_roam(delta: float) -> void:
	if _state == &"walk":
		var pos: Vector3 = body.global_position
		var flat := Vector3(_goal.x - pos.x, 0.0, _goal.z - pos.z)
		var dist: float = flat.length()
		var step: float = speed * delta
		if dist <= step:
			pos = Vector3(_goal.x, 0.0, _goal.z)
			_rest()
		else:
			var dir: Vector3 = flat / dist
			pos += dir * step
			var sx: float = dir.dot(screen_right)
			if absf(sx) > 0.15:
				_set_facing(sx < 0.0)
		pos.x = clampf(pos.x, area.position.x, area.end.x)
		pos.z = clampf(pos.z, area.position.y, area.end.y)
		pos.y = 0.0
		body.global_position = pos
		return
	_timer -= delta
	if _timer <= 0.0:
		_pick_goal()

func _pick_goal() -> void:
	_goal = Vector3(_rng.randf_range(area.position.x + 0.2, area.end.x - 0.2), 0.0, _rng.randf_range(area.position.y + 0.2, area.end.y - 0.2))
	_state = &"walk"
	_set_pose(&"walk")
	if cat2d != null and cat2d.has_method("set_move_speed"):
		cat2d.call("set_move_speed", speed)
	if _shy_t <= 0.0:
		_set_expr(&"open")

func _rest() -> void:
	if cat2d != null and cat2d.has_method("set_move_speed"):
		cat2d.call("set_move_speed", 0.0)
	var roll: float = _rng.randf()
	if roll < 0.3:
		_state = &"nap"
		_set_pose(&"sleep")
		if _shy_t <= 0.0:
			_set_expr(&"sleepy")
		_timer = _rng.randf_range(7.0, 12.0)
	elif roll < 0.7:
		_state = &"sit"
		_set_pose(&"sit")
		_timer = _rng.randf_range(3.0, 6.0)
	else:
		_state = &"idle"
		_set_pose(&"idle")
		_timer = _rng.randf_range(1.5, 3.0)

func _set_pose(p: StringName) -> void:
	if p == _pose or cat2d == null or not cat2d.has_method("set_pose"):
		return
	_pose = p
	cat2d.call("set_pose", p)

func _set_expr(e: StringName) -> void:
	if e == _expr or cat2d == null or not cat2d.has_method("set_expression"):
		return
	_expr = e
	cat2d.call("set_expression", e)

func _set_facing(left: bool) -> void:
	if cat2d != null and cat2d.has_method("set_facing_left"):
		cat2d.call("set_facing_left", left)

func get_state() -> StringName:
	return _state
