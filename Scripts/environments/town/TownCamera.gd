extends Node3D

## Orthographic iso camera rig for the Town (same contract as MainLevel3D: yaw 45, pitch 40),
## zoomed out further. WASD / arrows pan, middle-drag pans, wheel zooms, Home toggles the
## full-town overview. The look-at target is clamped to the town ground; the pan range
## shrinks as the camera zooms out and locks to the fit centre at the overview size.

@export var iso_yaw_degrees: float = 45.0
@export var iso_pitch_degrees: float = 40.0
@export var default_size: float = 17.0
@export var min_size: float = 8.0
@export var max_size: float = 30.0
@export var distance: float = 60.0
@export var pan_speed: float = 11.0
@export var zoom_step: float = 1.5
@export var fit_padding: float = 1.04

## Ground rect (x, z, w, d) and the height range used for the overview fit.
var bounds: Rect2 = Rect2(-10, -10, 20, 20)
var height_range: Vector2 = Vector2(-0.8, 8.0)

var camera: Camera3D
var target: Vector3 = Vector3.ZERO
var size_goal: float = 17.0
var fit_size: float = 28.0
var fit_center: Vector3 = Vector3.ZERO
var _dragging: bool = false

func _ready() -> void:
	camera = get_node_or_null("Camera3D")
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.far = distance * 3.0
	camera.current = true
	var vp: Viewport = get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_resized):
		vp.size_changed.connect(_on_resized)

func setup(ground: Rect2, start_target: Vector3, start_size: float = -1.0) -> void:
	bounds = ground
	_refit()
	size_goal = clampf(default_size if start_size <= 0.0 else start_size, min_size, _max_zoom())
	camera.size = size_goal
	target = _clamp_target(start_target, size_goal)
	_apply()

## Jump (no smoothing) to a framing; used by the screenshot script and hotspot focus.
func snap_to(p: Vector3, size: float) -> void:
	size_goal = clampf(size, min_size, _max_zoom())
	camera.size = size_goal
	target = _clamp_target(p, size_goal)
	_apply()

func overview() -> void:
	snap_to(fit_center, fit_size)

func is_overview() -> bool:
	return size_goal >= fit_size - 0.01

func basis_iso() -> Basis:
	var yaw: float = deg_to_rad(iso_yaw_degrees)
	var pitch: float = deg_to_rad(iso_pitch_degrees)
	var back := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
	return Basis.looking_at(-back, Vector3.UP)

## Screen-right direction on the ground (for actor facing).
func screen_right() -> Vector3:
	var b: Basis = basis_iso()
	return Vector3(b.x.x, 0.0, b.x.z).normalized()

func _ground_axes() -> Array[Vector3]:
	var b: Basis = basis_iso()
	return [Vector3(b.x.x, 0.0, b.x.z).normalized(), Vector3(-b.z.x, 0.0, -b.z.z).normalized()]

func _aspect() -> float:
	var vp: Viewport = get_viewport()
	if vp == null:
		return 16.0 / 9.0
	var s: Vector2 = vp.get_visible_rect().size
	return s.x / s.y if s.x > 0.0 and s.y > 0.0 else 16.0 / 9.0

func _refit() -> void:
	var cb: Basis = basis_iso()
	var c := Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
	var min_px: float = INF
	var max_px: float = -INF
	var min_py: float = INF
	var max_py: float = -INF
	for x in [bounds.position.x, bounds.end.x]:
		for z in [bounds.position.y, bounds.end.y]:
			for y in [height_range.x, height_range.y]:
				var rel: Vector3 = Vector3(x, y, z) - c
				min_px = minf(min_px, rel.dot(cb.x))
				max_px = maxf(max_px, rel.dot(cb.x))
				min_py = minf(min_py, rel.dot(cb.y))
				max_py = maxf(max_py, rel.dot(cb.y))
	fit_size = maxf(max_py - min_py, (max_px - min_px) / _aspect()) * fit_padding
	fit_center = c + cb.x * ((min_px + max_px) * 0.5) + cb.y * ((min_py + max_py) * 0.5)

func _max_zoom() -> float:
	return maxf(max_size, fit_size)

func _on_resized() -> void:
	_refit()
	size_goal = clampf(size_goal, min_size, _max_zoom())
	target = _clamp_target(target, size_goal)

func _clamp_target(t: Vector3, size: float) -> Vector3:
	var span: float = maxf(0.001, fit_size - min_size)
	var freedom: float = clampf((fit_size - size) / span, 0.0, 1.0)
	var c: Vector3 = fit_center
	# Pan box around the fit centre grows as the camera zooms in (idempotent clamp).
	var half_x: float = bounds.size.x * 0.5 * freedom
	var half_z: float = bounds.size.y * 0.5 * freedom
	var ty: float = lerpf(c.y, t.y, freedom)
	return Vector3(clampf(t.x, c.x - half_x, c.x + half_x), ty, clampf(t.z, c.z - half_z, c.z + half_z))

func _apply() -> void:
	var cb: Basis = basis_iso()
	camera.global_transform = Transform3D(cb, target + cb.z * distance)

func _process(delta: float) -> void:
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
		var axes: Array[Vector3] = _ground_axes()
		var speed: float = pan_speed * (camera.size / maxf(1.0, default_size))
		target += (axes[0] * move.x + axes[1] * move.y).normalized() * speed * delta
	var k: float = 1.0 - exp(-12.0 * delta)
	camera.size = lerpf(camera.size, size_goal, k)
	if absf(camera.size - size_goal) < 0.001:
		camera.size = size_goal
	target = _clamp_target(target, camera.size)
	_apply()

## Returns true when the camera used the event.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			return true
		if not mb.pressed:
			return false
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			size_goal = clampf(size_goal - zoom_step, min_size, _max_zoom())
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			size_goal = clampf(size_goal + zoom_step, min_size, _max_zoom())
			return true
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var vp_h: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
		var wpp: float = camera.size / vp_h
		var axes: Array[Vector3] = _ground_axes()
		var ps: float = maxf(0.2, sin(deg_to_rad(iso_pitch_degrees)))
		target -= axes[0] * mm.relative.x * wpp
		target += axes[1] * (mm.relative.y * wpp / ps)
		return true
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_HOME:
			if is_overview():
				size_goal = clampf(default_size, min_size, _max_zoom())
			else:
				size_goal = fit_size
				target = fit_center
			return true
	return false
