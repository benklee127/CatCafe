extends Node3D

## Reusable orthographic isometric diorama camera (same look and controls as MainLevel3D):
## yaw 45 / pitch 40, fit-to-room framing, WASD / arrow pan, middle-drag pan, wheel zoom,
## Home toggles the full-room overview. Pan range shrinks as you zoom out.
##
## Usage: add as a child, call set_room_bounds(min_xz, max_xz) once the room exists.
## Owned by the apartment environment (apt_ prefix: other environment agents keep their own).

@export var iso_yaw_degrees: float = 45.0
@export var iso_pitch_degrees: float = 40.0
## Preferred starting size (clamped to [min_size, fit size]).
@export var default_size: float = 10.5
@export var min_size: float = 5.5
@export var max_size: float = 14.5
@export var fit_padding: float = 1.08
@export var distance: float = 40.0
@export var pan_speed: float = 7.0
@export var zoom_step: float = 0.8
## Vertical extent of the diorama used for the fit (plinth bottom .. wall top).
@export var min_y: float = -0.7
@export var max_y: float = 2.2
@export var input_enabled: bool = true

var camera: Camera3D
var _min := Vector2(-5, -4)
var _max := Vector2(5, 4)
var _target := Vector3.ZERO
var _fit_center := Vector3.ZERO
var _fit_size: float = 12.0
var _size_goal: float = 10.0
var _dragging: bool = false

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.far = distance * 3.0
	camera.current = true
	add_child(camera)
	var vp: Viewport = get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_resized):
		vp.size_changed.connect(_on_resized)
	_refit()
	_size_goal = clampf(default_size, min_size, _max_zoom())
	camera.size = _size_goal
	_target = _fit_center
	_apply()

## Floor rectangle in world XZ the camera frames and pans within.
func set_room_bounds(min_xz: Vector2, max_xz: Vector2) -> void:
	_min = min_xz
	_max = max_xz
	if camera == null:
		return
	_refit()
	_size_goal = clampf(default_size, min_size, _max_zoom())
	camera.size = _size_goal
	_target = _clamp_target(_fit_center, _size_goal)
	_apply()

## Instantly frame a world point at a given size (screenshots, cutscenes).
func focus_on(world_pos: Vector3, size: float) -> void:
	_size_goal = clampf(size, min_size, _max_zoom())
	camera.size = _size_goal
	_target = _clamp_target(world_pos, _size_goal)
	_apply()

func show_overview() -> void:
	_size_goal = _fit_size
	_target = _fit_center

func get_fit_size() -> float:
	return _fit_size

func get_size_goal() -> float:
	return _size_goal

func _basis() -> Basis:
	var yaw: float = deg_to_rad(iso_yaw_degrees)
	var pitch: float = deg_to_rad(iso_pitch_degrees)
	var back := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
	return Basis.looking_at(-back, Vector3.UP)

func _apply() -> void:
	var cb: Basis = _basis()
	camera.global_transform = Transform3D(cb, _target + cb.z * distance)

func _aspect() -> float:
	var vp: Viewport = get_viewport()
	if vp == null:
		return 16.0 / 9.0
	var s: Vector2 = vp.get_visible_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return 16.0 / 9.0
	return s.x / s.y

func _refit() -> void:
	var pad: float = 0.25
	var pts: Array[Vector3] = []
	for x in [_min.x - pad, _max.x + pad]:
		for z in [_min.y - pad, _max.y + pad]:
			for y in [min_y, max_y]:
				pts.append(Vector3(x, y, z))
	var center := Vector3((_min.x + _max.x) * 0.5, 0.0, (_min.y + _max.y) * 0.5)
	var cb: Basis = _basis()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var rel: Vector3 = p - center
		var q := Vector2(rel.dot(cb.x), rel.dot(cb.y))
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	_fit_size = maxf(hi.y - lo.y, (hi.x - lo.x) / _aspect()) * fit_padding
	_fit_center = center + cb.x * ((lo.x + hi.x) * 0.5) + cb.y * ((lo.y + hi.y) * 0.5)

func _max_zoom() -> float:
	return maxf(max_size, _fit_size)

func _on_resized() -> void:
	if camera == null:
		return
	_refit()
	_size_goal = clampf(_size_goal, min_size, _max_zoom())
	_target = _clamp_target(_target, _size_goal)

func _clamp_target(t: Vector3, size: float) -> Vector3:
	var span: float = maxf(0.001, _fit_size - min_size)
	var freedom: float = clampf((_fit_size - size) / span, 0.0, 1.0)
	var hx: float = (_max.x - _min.x) * 0.5 * freedom
	var hz: float = (_max.y - _min.y) * 0.5 * freedom
	var c: Vector3 = _fit_center
	return Vector3(clampf(t.x, c.x - hx, c.x + hx), lerpf(c.y, t.y, freedom), clampf(t.z, c.z - hz, c.z + hz))

func _ground_axes() -> Array[Vector3]:
	var cb: Basis = _basis()
	return [Vector3(cb.x.x, 0.0, cb.x.z).normalized(), Vector3(-cb.z.x, 0.0, -cb.z.z).normalized()]

func _process(delta: float) -> void:
	if camera == null:
		return
	var move := Vector2.ZERO
	if input_enabled:
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
		var axes: Array[Vector3] = _ground_axes()
		var speed: float = pan_speed * (camera.size / maxf(1.0, default_size))
		_target += (axes[0] * move.x + axes[1] * move.y).normalized() * speed * delta
	var k: float = 1.0 - exp(-12.0 * delta)
	camera.size = lerpf(camera.size, _size_goal, k)
	if absf(camera.size - _size_goal) < 0.001:
		camera.size = _size_goal
	_target = _clamp_target(_target, camera.size)
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			get_viewport().set_input_as_handled()
			return
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_size_goal = clampf(_size_goal - zoom_step, min_size, _max_zoom())
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_size_goal = clampf(_size_goal + zoom_step, min_size, _max_zoom())
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var vp_h: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
		var wpp: float = camera.size / vp_h
		var axes: Array[Vector3] = _ground_axes()
		var ps: float = maxf(0.2, sin(deg_to_rad(iso_pitch_degrees)))
		_target -= axes[0] * mm.relative.x * wpp
		_target += axes[1] * (mm.relative.y * wpp / ps)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_HOME:
			if _size_goal >= _fit_size - 0.01:
				_size_goal = clampf(default_size, min_size, _max_zoom())
			else:
				show_overview()
			get_viewport().set_input_as_handled()
