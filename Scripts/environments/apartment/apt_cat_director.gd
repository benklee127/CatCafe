extends Node

## Gentle home behaviours layered on top of the real cat state machine (MainLevelCat3D).
## The cats wander on their own (idle / wander via apt_nav_grid). The director only
## sends a cat somewhere with a path and then lets the state machine render it:
##   feed_all()  every cat walks to a bowl cell and eats a while (idle pose, "nom" glyph)
##   bond(cat)   a cat walks to the bonding nest and sits there (INTERACTING via the nav
##               grid's calm company point; trust ticks up through the cat's own rules)
##   nap(cat)    a cat walks to the nap bed and sleeps (REST state: sleep pose, Zz)
##   all_sleep() every cat naps where it is (end of day)
## Every cat now and then takes a nap by itself.
##
## Nothing here edits the cat scripts; it uses their public fields (path, state,
## retarget_timer, overstimulation...) and methods (_set_state is called by name).

signal cat_arrived(cat, activity: String)
signal cat_finished(cat, activity: String)

const ST_IDLE := &"idle"
const ST_WANDER := &"wander"
const ST_REST := &"rest"
const EAT_SEC: float = 7.0
const BOND_SEC: float = 14.0
const NAP_SEC: float = 16.0
const AUTO_NAP_MIN: float = 30.0
const AUTO_NAP_MAX: float = 55.0
const BOND_TRUST_BONUS: float = 3.0

var nav: Node = null
var cats: Array = []
var bowl_cells: Array[Vector2i] = []
var nap_cells: Array[Vector2i] = []
var bond_cell := Vector2i(-1, -1)
var auto_naps: bool = true

## Per cat instance id: {"mode": String, "goal": Vector2i, "timer": float}
var _jobs: Dictionary = {}
var _auto_nap_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 777
	_auto_nap_timer = _rng.randf_range(AUTO_NAP_MIN * 0.5, AUTO_NAP_MAX * 0.5)

func register_cat(cat: Node3D) -> void:
	cats.append(cat)
	_jobs[cat.get_instance_id()] = {"mode": "free", "goal": Vector2i.ZERO, "timer": 0.0}

func get_mode(cat: Node) -> String:
	var j: Dictionary = _jobs.get(cat.get_instance_id(), {})
	return str(j.get("mode", "free"))

# --- commands --------------------------------------------------------------------------

func feed_all() -> void:
	var i: int = 0
	for cat in cats:
		if not is_instance_valid(cat) or bowl_cells.is_empty():
			continue
		_wake(cat)
		_send(cat, bowl_cells[i % bowl_cells.size()], "to_bowl")
		i += 1

## Picks the shyest free cat when cat is null.
func bond(cat: Node3D = null) -> Node3D:
	if bond_cell.x < 0:
		return null
	if cat == null:
		var best: Node3D = null
		var best_trust: float = INF
		for c in cats:
			if not is_instance_valid(c):
				continue
			var t: float = float(c.get("trust"))
			if t < best_trust:
				best_trust = t
				best = c
		cat = best
	if cat == null:
		return null
	# Only one cat on the nest at a time.
	for c in cats:
		if c != cat and is_instance_valid(c) and get_mode(c) in ["to_bond", "bonding"]:
			_release(c)
	_wake(cat)
	_send(cat, bond_cell, "to_bond")
	return cat

func nap(cat: Node3D) -> void:
	if nap_cells.is_empty():
		return
	_wake(cat)
	_send(cat, nap_cells[_rng.randi_range(0, nap_cells.size() - 1)], "to_nap")

## End of day: every cat curls up where it is.
func all_sleep() -> void:
	for cat in cats:
		if is_instance_valid(cat):
			_release(cat)
			var empty: Array[Vector2i] = []
			cat.set("path", empty)
			cat.call("_stop_moving")
			_start_rest(cat, NAP_SEC)
			_jobs[cat.get_instance_id()] = {"mode": "napping", "goal": nav.world_to_map(cat.global_position), "timer": NAP_SEC}

# --- tick ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if nav == null:
		return
	for cat in cats:
		if not is_instance_valid(cat):
			continue
		_tick_cat(cat, delta)
	if auto_naps:
		_auto_nap_timer -= delta
		if _auto_nap_timer <= 0.0:
			_auto_nap_timer = _rng.randf_range(AUTO_NAP_MIN, AUTO_NAP_MAX)
			var free: Array = cats.filter(func(c): return is_instance_valid(c) and get_mode(c) == "free" and c.get("state") in [ST_IDLE, ST_WANDER])
			if not free.is_empty():
				nap(free[_rng.randi_range(0, free.size() - 1)])

func _tick_cat(cat: Node3D, delta: float) -> void:
	var id: int = cat.get_instance_id()
	var j: Dictionary = _jobs.get(id, {})
	var mode: String = str(j.get("mode", "free"))
	if mode == "free":
		return
	var goal: Vector2i = j.get("goal", Vector2i.ZERO)
	var here: Vector2i = nav.world_to_map(cat.global_position)
	var path: Array = cat.get("path")
	match mode:
		"to_bowl", "to_bond", "to_nap":
			# Keep the wander retarget from overriding our path.
			cat.set("retarget_timer", 999.0)
			if cat.get("state") == ST_IDLE:
				cat.call("_set_state", ST_WANDER)
			var at_goal: bool = here == goal and path.is_empty() and _close_to(cat, goal)
			if at_goal:
				_arrive(cat, mode, goal)
			elif path.is_empty():
				var p: Array[Vector2i] = nav.build_path(here, goal)
				if p.is_empty() and here != goal:
					_release(cat)
				else:
					cat.set("path", p)
			j["timer"] = float(j.get("timer", 0.0)) + delta
			if float(j["timer"]) > 25.0:
				_release(cat)
		"eating":
			cat.set("retarget_timer", 999.0)
			j["timer"] = float(j["timer"]) - delta
			if float(j["timer"]) <= 0.0:
				cat_finished.emit(cat, "eat")
				_release(cat)
		"bonding":
			j["timer"] = float(j["timer"]) - delta
			if float(j["timer"]) <= 0.0:
				nav.company_points.clear()
				cat_finished.emit(cat, "bond")
				_release(cat)
		"napping":
			# MainLevelCat3D leaves REST by itself once its overstim value has drained.
			j["timer"] = float(j["timer"]) - delta
			if cat.get("state") != ST_REST or float(j["timer"]) < -10.0:
				cat_finished.emit(cat, "nap")
				_release(cat)

func _arrive(cat: Node3D, mode: String, goal: Vector2i) -> void:
	var id: int = cat.get_instance_id()
	match mode:
		"to_bowl":
			_jobs[id] = {"mode": "eating", "goal": goal, "timer": EAT_SEC}
			_face_towards(cat, Vector3(0, 0, -1))
			cat_arrived.emit(cat, "eat")
			_float_glyph(cat, "nom", Color("FFE3A8"))
		"to_bond":
			_jobs[id] = {"mode": "bonding", "goal": goal, "timer": BOND_SEC}
			nav.company_points.clear()
			nav.company_points.append(nav.map_to_world(goal))
			if cat.has_method("add_trust"):
				cat.call("add_trust", BOND_TRUST_BONUS)
			cat_arrived.emit(cat, "bond")
			_float_glyph(cat, "♥", Color("F2A0AA"))
		"to_nap":
			_jobs[id] = {"mode": "napping", "goal": goal, "timer": NAP_SEC}
			_start_rest(cat, NAP_SEC)
			cat_arrived.emit(cat, "nap")

## REST makes the rig curl up (sleep pose, sleepy face, Zz glyph). The cat's own rule ends
## REST once overstimulation drains under rest_release_threshold, so set both so the nap
## lasts about `seconds`.
func _start_rest(cat: Node3D, seconds: float) -> void:
	var release: float = float(cat.get("rest_release_threshold"))
	var extra: float = 30.0
	cat.set("overstimulation", release + extra)
	cat.set("overstim_recovery_per_sec", extra / maxf(1.0, seconds))
	cat.call("_set_state", ST_REST)
	cat.set("_rest_timer", 0.0)
	cat.set("hiding_in_place", false)

func _send(cat: Node3D, goal: Vector2i, mode: String) -> void:
	var here: Vector2i = nav.world_to_map(cat.global_position)
	cat.call("_set_state", ST_WANDER)
	cat.set("retarget_timer", 999.0)
	cat.set("path", nav.build_path(here, goal))
	_jobs[cat.get_instance_id()] = {"mode": mode, "goal": goal, "timer": 0.0}

func _wake(cat: Node3D) -> void:
	if cat.get("state") == ST_REST:
		cat.set("overstimulation", 0.0)
		cat.call("_set_state", ST_IDLE)

func _release(cat: Node3D) -> void:
	var id: int = cat.get_instance_id()
	var j: Dictionary = _jobs.get(id, {})
	if str(j.get("mode", "")) == "bonding":
		nav.company_points.clear()
	_jobs[id] = {"mode": "free", "goal": Vector2i.ZERO, "timer": 0.0}
	cat.set("retarget_timer", _rng.randf_range(0.5, 1.5))
	if cat.get("state") == ST_WANDER and (cat.get("path") as Array).is_empty():
		cat.call("_set_state", ST_IDLE)
		cat.set("idle_timer", _rng.randf_range(1.0, 3.0))

func _close_to(cat: Node3D, goal: Vector2i) -> bool:
	var w: Vector3 = nav.map_to_world(goal)
	return Vector2(w.x, w.z).distance_to(Vector2(cat.global_position.x, cat.global_position.z)) < 0.1

func _face_towards(cat: Node3D, dir: Vector3) -> void:
	var cat2d = cat.get("cat2d")
	var cam: Camera3D = nav.get_active_camera()
	if cat2d == null or cam == null or not cat2d.has_method("set_facing_left"):
		return
	var right: Vector3 = cam.global_basis.x
	right.y = 0.0
	cat2d.call("set_facing_left", dir.dot(right.normalized()) < 0.0)

## Little rising, fading label above a cat (feedback only).
func _float_glyph(cat: Node3D, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 44
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 3
	l.outline_render_priority = 2
	l.modulate = color
	l.outline_modulate = Color("4A3426")
	l.outline_size = 10
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var th = load("res://UI/cozy_theme.tres")
	if th is Theme and (th as Theme).default_font != null:
		l.font = (th as Theme).default_font
	l.position = Vector3(0, 0.75, 0)
	cat.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", 1.15, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.6).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)
