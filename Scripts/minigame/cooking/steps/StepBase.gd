extends Node2D

## THE STEP (VERB) CONTRACT for the cooking minigame. Every verb extends this by path:
##   extends "res://Scripts/minigame/cooking/steps/StepBase.gd"
## Full contract + per-verb params: Docs/MINIGAMES.md ("StepBase contract").
##
## CookingGame instantiates the verb (script or .tscn via StepRegistry), adds it under its
## StepLayer at (0,0) in the 320x180 PlayArea space, sets `hold_to_toggle`, then calls
## start(params, leniency, rng). The verb plays, then calls finish(accuracy) exactly once,
## which emits `done(accuracy, time_sec)`. CookingGame frees the node after the pop reaction.
##
## Reserved params injected by CookingGame (all prefixed "_"; recipe params never use "_"):
##   _type: String            verb type id ("pour", ...)
##   _label: String           card label ("Steam milk")
##   _index: int              step index in the recipe
##   _tier: int               recipe tier 1..3
##   _window_mult: float      tier window mult x modifier window mult (Kid size 1.25). Use window_scale().
##   _sweep_sec: float        tier default sweep (2.4 / 2.0 / 1.6). STOP_RING uses it when params lacks sweep_sec.
##   _roll: Dictionary        seeded pre-rolls: pour {target}, stop_ring {sweep_mult}, trace {shape},
##                            keep_zone {zone_center}, place {target_x}, back_burner {cook_sec}
##   _prev: Array[Dictionary] earlier steps' {type, accuracy, time, extra} (e.g. layered pours)
##   _play_scale: int         integer upscale of the PlayArea (screen px per art px), for
##                            screen-space precision rules (TRACE: distance_px * _play_scale).
##   _safe_rect: Rect2        where a card should draw (avoids the burner slot when one is active)
##   _slot_rect: Rect2        top-right burner slot (back_burner draws its ring here)
##   _reduced_motion: bool    Gentle Paws reduced motion: no bounce / shake / particles
##
## Input: raw events, no InputMap. Base _unhandled_input routes them to the hooks below.
##   LMB / Space        -> _on_tap() on every press; _on_hold_begin()/_on_hold_end() for holds
##                         (hold_to_toggle turns a hold into tap-to-start / tap-to-stop)
##   mouse motion       -> _on_pointer_moved(play_pos)
##   O                  -> _on_burner_key()
##   Arrows / WASD      -> read with nudge_vector() (keyboard TRACE steering / PLACE nudge)
## If you override _unhandled_input, call super(event) first or the hooks will not fire.
## Mark events you consume with get_viewport().set_input_as_handled().
## Timing: `elapsed` accumulates process delta from start() (pauses with the game). Do not rely
## on Time.get_ticks_* for gameplay timing; the host freezes the game while the park prompt is up.

signal done(accuracy: float, time_sec: float)

const PixelDraw = preload("res://Scripts/minigame/cooking/PixelDraw.gd")
const PLAY_SIZE := Vector2(320, 180)

var params: Dictionary = {}
## 1.0 Cozy / 1.5 Relaxed / 2.0 Sleepy. Multiplies every window/band and slows sweeps.
var leniency: float = 1.0
## Accessibility: holds become tap-to-start / tap-to-stop.
var hold_to_toggle: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Seconds since start() (game time; frozen while parked/prompted).
var elapsed: float = 0.0
## Optional extra result data later steps can read via params._prev (e.g. {"fill": 0.71}).
var extra: Dictionary = {}

var _started: bool = false
var _finished: bool = false
var _held: bool = false
var _held_by_mouse: bool = false


## Called once by CookingGame. Override _on_start() rather than this (or call super first).
func start(p_params: Dictionary, p_leniency: float, p_rng: RandomNumberGenerator) -> void:
	params = p_params
	leniency = maxf(p_leniency, 0.1)
	if p_rng != null:
		rng = p_rng
	elapsed = 0.0
	_started = true
	_finished = false
	set_process(true)
	set_process_unhandled_input(true)
	_on_start()
	queue_redraw()


## Report the result. Safe to call once; later calls are ignored. time_sec < 0 -> use elapsed.
func finish(accuracy: float, time_sec: float = -1.0) -> void:
	if _finished:
		return
	_finished = true
	_held = false
	var t: float = elapsed if time_sec < 0.0 else time_sec
	done.emit(clampf(accuracy, 0.0, 1.0), t)


func is_running() -> bool:
	return _started and not _finished


func is_finished() -> bool:
	return _finished


## Toggle-aware hold state for hold verbs.
func is_primary_held() -> bool:
	return _held


# --- Tunables helpers ---------------------------------------------------------------------

## Multiply band/window widths by this (tier x modifier x leniency).
func window_scale() -> float:
	return float(params.get("_window_mult", 1.0)) * leniency


## Multiply sweep/cycle durations by this (leniency slows sweeps).
func time_scale() -> float:
	return leniency


func roll(key: String, default_value: Variant = null) -> Variant:
	var r: Variant = params.get("_roll", {})
	if r is Dictionary:
		return (r as Dictionary).get(key, default_value)
	return default_value


func reduced_motion() -> bool:
	return bool(params.get("_reduced_motion", false))


func play_scale() -> int:
	return int(params.get("_play_scale", 1))


func safe_rect() -> Rect2:
	var r: Variant = params.get("_safe_rect", Rect2(Vector2.ZERO, PLAY_SIZE))
	return r if r is Rect2 else Rect2(Vector2.ZERO, PLAY_SIZE)


func slot_rect() -> Rect2:
	var r: Variant = params.get("_slot_rect", Rect2(272, 4, 44, 44))
	return r if r is Rect2 else Rect2(272, 4, 44, 44)


# --- Coordinates -----------------------------------------------------------------------------

## Maps an input event (or the current mouse) to 320x180 PlayArea coordinates. Events reaching
## a step were already transformed by the SubViewportContainer, so this is the viewport-space
## position; for keyboard events it falls back to the current mouse position.
func to_play_coords(event: InputEvent = null) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).position
	return get_viewport().get_mouse_position()


## Same as to_play_coords but in this node's local space (differs only while the card slides in).
func to_local_play(event: InputEvent = null) -> Vector2:
	return get_global_transform().affine_inverse() * to_play_coords(event)


## Arrow keys / WASD as a direction vector (held state, read every frame).
func nudge_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		v.y += 1.0
	return v


# --- Hooks for verbs (override) ---------------------------------------------------------------

func _on_start() -> void:
	pass


func _on_tap(_play_pos: Vector2, _from_mouse: bool) -> void:
	pass


func _on_hold_begin(_play_pos: Vector2, _from_mouse: bool) -> void:
	pass


func _on_hold_end(_play_pos: Vector2) -> void:
	pass


func _on_pointer_moved(_play_pos: Vector2) -> void:
	pass


func _on_burner_key() -> void:
	pass


# --- Engine plumbing ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_PROCESS and _started and not _finished:
		elapsed += get_process_delta_time()
		# A mouse release outside the PlayArea never reaches us: end the hold from device state.
		if _held and not hold_to_toggle:
			if _held_by_mouse and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_set_held(false, get_viewport().get_mouse_position(), true)
			elif not _held_by_mouse and not Input.is_key_pressed(KEY_SPACE):
				_set_held(false, get_viewport().get_mouse_position(), false)


func _unhandled_input(event: InputEvent) -> void:
	if not _started or _finished:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_primary(mb.pressed, to_play_coords(event), true)
	elif event is InputEventMouseMotion:
		_on_pointer_moved(to_play_coords(event))
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.echo:
			return
		if k.keycode == KEY_SPACE:
			_primary(k.pressed, get_viewport().get_mouse_position(), false)
		elif k.keycode == KEY_O and k.pressed:
			_on_burner_key()


func _primary(pressed: bool, pos: Vector2, from_mouse: bool) -> void:
	if pressed:
		_on_tap(pos, from_mouse)
		if _finished:
			return
		if hold_to_toggle:
			_set_held(not _held, pos, from_mouse)
		elif not _held:
			_set_held(true, pos, from_mouse)
	elif not hold_to_toggle and _held and _held_by_mouse == from_mouse:
		_set_held(false, pos, from_mouse)


func _set_held(value: bool, pos: Vector2, from_mouse: bool) -> void:
	if value == _held:
		return
	_held = value
	if value:
		_held_by_mouse = from_mouse
		_on_hold_begin(pos, from_mouse)
	else:
		_on_hold_end(pos)
