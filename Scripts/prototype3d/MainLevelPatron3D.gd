extends CharacterBody3D

## Cafe patron (contract 1.5). Archetype-driven visit lifecycle:
## enter at the entrance -> wander / use patron slots -> visit timer runs out -> LEAVING:
## release slot, tip, walk back to the entrance, fade out, emit patron_left, queue_free.
## The billboard is a procedurally drawn 2D figure rendered once per pose into a SubViewport.

signal patron_left(patron)

const WANDER := &"wander"
const USING_SLOT := &"using_slot"
const LEAVING := &"leaving"

const CANVAS_W: int = 192
const CANVAS_H: int = 320
const CANVAS_METERS: float = 1.6
const WALK_FRAMES: int = 8
const DEFAULT_IMPACT: float = 11.0
const EFFECTS_REFRESH_SEC: float = 0.5
const LEAVE_GIVE_UP_SEC: float = 25.0
const FADE_SEC: float = 0.6

const ARCHETYPE_TINTS: Dictionary = {
	"gentle_reader": Color("#8FA88A"),
	"busy_remote_worker": Color("#6F8FB8"),
	"hyper_toddler": Color("#F2A65A"),
}
const SKIN_TONES: Array[Color] = [Color("#F6D7C3"), Color("#EBC1A2"), Color("#D49E7A"), Color("#A86F4E"), Color("#7A4E36")]
const HAIR_COLORS: Array[Color] = [Color("#3B2A24"), Color("#6B4430"), Color("#A9713F"), Color("#E0B26A"), Color("#1F1A1C"), Color("#B5523B"), Color("#8E8A86")]
const PANTS_COLORS: Array[Color] = [Color("#4F5A73"), Color("#6B5446"), Color("#3E4A45"), Color("#7A6A8C"), Color("#5A6E8A")]

@export var move_speed: float = 1.6
@export var slot_seek_chance: float = 0.7
@export var dwell_time_min: float = 8.0
@export var dwell_time_max: float = 16.0

var level
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var grid_position: Vector2i = Vector2i.ZERO
var target_grid: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var state: StringName = WANDER
var retarget_timer: float = 0.0
var dwell_timer: float = 0.0
var current_slot_id: int = -1

var archetype: Dictionary = {}
var archetype_id: String = ""
var display_name: String = "Patron"
var overstim_impact: float = DEFAULT_IMPACT
var spend_rate: float = 1.0
var visit_duration_sec: float = 75.0
var visit_timer: float = 75.0
var tags: Array = []
var tint: Color = Color("#C9A27A")
var tip_paid: int = 0

var _effects: Dictionary = {}
var _effects_timer: float = 0.0
var _best_tip_mult: float = 1.0
var _leave_timer: float = 0.0
var _fading: bool = false
var _fade_t: float = 0.0
var _walk_phase: float = 0.0
var _walk_frame: int = -1
var _is_moving: bool = false
var _facing_left: bool = false
var _idle_t: float = 0.0
var _left_emitted: bool = false

@onready var anchor: Node3D = get_node_or_null("BillboardAnchor")
@onready var sprite: Sprite3D = get_node_or_null("BillboardAnchor/Sprite3D")
@onready var fallback_sprite: Sprite3D = get_node_or_null("BillboardAnchor/FallbackSprite3D")
@onready var tip_label: Label3D = get_node_or_null("BillboardAnchor/TipLabel")
@onready var blob_shadow: MeshInstance3D = get_node_or_null("BlobShadow")
@onready var art_viewport: SubViewport = get_node_or_null("ArtViewport")

var _art: PatronArt

func _ready() -> void:
	add_to_group("patrons")
	retarget_timer = rng.randf_range(0.2, 0.8)
	_setup_art()

func configure(main_level, spawn_grid: Vector2i, p_archetype: Dictionary = {}, p_seed: int = 0) -> void:
	level = main_level
	grid_position = spawn_grid
	target_grid = spawn_grid
	path.clear()
	if p_seed != 0:
		rng.seed = p_seed
	else:
		rng.randomize()
	_apply_archetype(p_archetype)
	global_position = level.map_to_world(spawn_grid) + Vector3(0, _y_offset(), 0)
	velocity = Vector3.ZERO
	state = WANDER
	retarget_timer = rng.randf_range(0.1, 0.6)
	_setup_art()

func is_leaving() -> bool:
	return state == LEAVING

func get_hud_info() -> Dictionary:
	return {
		"name": display_name,
		"archetype_id": archetype_id,
		"state": String(state),
		"overstim_impact": overstim_impact,
		"visit_left": maxf(0.0, visit_timer),
		"visit_total": visit_duration_sec,
		"tags": tags.duplicate(),
	}

# ---------------------------------------------------------------- data

func _apply_archetype(a: Dictionary) -> void:
	archetype = a.duplicate(true)
	archetype_id = String(archetype.get("id", ""))
	display_name = String(archetype.get("display_name", archetype_id.capitalize() if not archetype_id.is_empty() else "Patron"))
	overstim_impact = _num(archetype, "overstim_impact", DEFAULT_IMPACT)
	spend_rate = _num(archetype, "spend_rate", 1.0)
	visit_duration_sec = maxf(10.0, _num(archetype, "visit_duration_sec", 75.0))
	var raw_tags = archetype.get("tags", [])
	tags = (raw_tags as Array).duplicate() if raw_tags is Array else []
	# The visit clock runs slower near stay-boosting decor (velvet armchair patron_stay_mult)
	# and faster near turnover decor (espresso bar); see _visit_drain_rate().
	visit_timer = visit_duration_sec * rng.randf_range(0.85, 1.15)
	if ARCHETYPE_TINTS.has(archetype_id):
		tint = ARCHETYPE_TINTS[archetype_id]
	elif not archetype_id.is_empty():
		tint = Color.from_hsv(float(hash(archetype_id) % 360) / 360.0, 0.35, 0.8)
	if archetype_id == "hyper_toddler" or tags.has("active"):
		move_speed = 2.1

func _num(src: Dictionary, key: String, fallback: float) -> float:
	var v = src.get(key, fallback)
	if v is float or v is int:
		return float(v)
	return fallback

func _y_offset() -> float:
	if level == null:
		return 0.0
	var v = level.get("actor_y_offset")
	return float(v) if (v is float or v is int) else 0.0

func _refresh_effects(delta: float) -> void:
	_effects_timer -= delta
	if _effects_timer > 0.0:
		return
	_effects_timer = EFFECTS_REFRESH_SEC
	if level != null and level.has_method("get_decor_effects_at"):
		var e = level.call("get_decor_effects_at", grid_position)
		_effects = e if e is Dictionary else {}
	else:
		_effects = {}
	if state == USING_SLOT:
		_best_tip_mult = maxf(_best_tip_mult, float(_effects.get("tip_mult", 1.0)))

func _visit_drain_rate() -> float:
	var stay: float = maxf(0.25, float(_effects.get("patron_stay_mult", 1.0)))
	var turnover: float = maxf(0.25, float(_effects.get("patron_turnover_mult", 1.0)))
	return turnover / stay

# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if level == null:
		return
	if _fading:
		_update_fade(delta)
		return
	grid_position = level.world_to_map(global_position)
	_resolve_if_embedded()
	_refresh_effects(delta)
	if state != LEAVING:
		visit_timer -= delta * _visit_drain_rate()
		if visit_timer <= 0.0:
			_begin_leave()
	_update_state(delta)
	_follow_path(delta)
	_update_visuals(delta)

func _update_state(delta: float) -> void:
	match state:
		LEAVING:
			_process_leaving(delta)
		USING_SLOT:
			_process_slot(delta)
		_:
			retarget_timer -= delta
			if retarget_timer > 0.0 or not path.is_empty():
				return
			retarget_timer = rng.randf_range(1.5, 3.5)
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
		retarget_timer = rng.randf_range(0.5, 1.5)

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

func _exit_cell() -> Vector2i:
	var e = level.get("entrance_cell")
	if e is Vector2i and (e as Vector2i).x >= 0:
		return e
	return grid_position

func _begin_leave() -> void:
	if state == LEAVING:
		return
	_release_slot()
	state = LEAVING
	_leave_timer = 0.0
	_pay_tip()
	var goal: Vector2i = _exit_cell()
	if level.has_method("nearest_walkable_cell"):
		goal = level.nearest_walkable_cell(goal, false)
	target_grid = goal
	path = level.build_path(grid_position, goal, false)

func _process_leaving(delta: float) -> void:
	_leave_timer += delta
	if grid_position == target_grid or _leave_timer > LEAVE_GIVE_UP_SEC:
		_start_fade()
		return
	if path.is_empty():
		path = level.build_path(grid_position, target_grid, false)
		if path.is_empty() and _leave_timer > 3.0:
			_start_fade()

func _pay_tip() -> void:
	if tip_paid > 0 or level == null:
		return
	var econ: Dictionary = {}
	var bal = level.get("balance")
	if bal is Dictionary:
		var ec = (bal as Dictionary).get("economy", {})
		econ = ec if ec is Dictionary else {}
	var base_tip: float = _num(econ, "base_tip", 3.0)
	var tip_mult: float = maxf(_best_tip_mult, float(_effects.get("tip_mult", 1.0)))
	tip_paid = maxi(1, int(round(base_tip * spend_rate * tip_mult)))
	if level.has_method("add_money"):
		level.call("add_money", tip_paid, "tip")
	_show_tip(tip_paid)

func _show_tip(amount: int) -> void:
	if tip_label == null:
		return
	tip_label.text = "+$%d" % amount
	tip_label.visible = true
	tip_label.modulate.a = 1.0
	tip_label.outline_modulate.a = 1.0
	tip_label.position = Vector3(0, CANVAS_METERS * _figure_height_ratio() + 0.15, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(tip_label, "position:y", tip_label.position.y + 0.55, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(tip_label, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.tween_property(tip_label, "outline_modulate:a", 0.0, 1.6).set_delay(0.6)

func _start_fade() -> void:
	if _fading:
		return
	_fading = true
	_fade_t = 0.0
	path.clear()
	velocity = Vector3.ZERO
	_release_slot()

func _update_fade(delta: float) -> void:
	_fade_t += delta
	var a: float = clampf(1.0 - _fade_t / FADE_SEC, 0.0, 1.0)
	if sprite != null:
		sprite.modulate.a = a
	if fallback_sprite != null:
		fallback_sprite.modulate.a = a
	if blob_shadow != null:
		blob_shadow.transparency = 1.0 - a
	if _fade_t >= FADE_SEC and not _left_emitted:
		_left_emitted = true
		patron_left.emit(self)
		queue_free()

# ---------------------------------------------------------------- movement

func _follow_path(delta: float) -> void:
	_is_moving = false
	if path.is_empty():
		velocity = Vector3.ZERO
		return
	var next_grid: Vector2i = path[0]
	if not level.is_walkable(next_grid, false):
		path.clear()
		velocity = Vector3.ZERO
		if state == USING_SLOT:
			_release_slot()
			state = WANDER
		retarget_timer = 0.0
		return
	var next_world: Vector3 = level.map_to_world(next_grid) + Vector3(0, _y_offset(), 0)
	var step: Vector3 = next_world - global_position
	step.y = 0.0
	var dist: float = step.length()
	if dist <= 0.06:
		global_position = next_world
		grid_position = next_grid
		path.remove_at(0)
		velocity = Vector3.ZERO
		return
	var speed: float = move_speed * clampf(float(_effects.get("pathing_speed_mult", 1.0)), 0.5, 1.5)
	if delta > 0.0 and dist < speed * delta:
		speed = dist / delta
	velocity = step.normalized() * speed
	move_and_slide()
	_is_moving = true
	_walk_phase += speed * delta * 3.2
	_update_facing(step)

func _update_facing(dir: Vector3) -> void:
	var cam: Camera3D = level.get_active_camera() if level.has_method("get_active_camera") else null
	var right: Vector3 = cam.global_basis.x if cam != null else Vector3.RIGHT
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return
	var sx: float = dir.normalized().dot(right.normalized())
	if absf(sx) < 0.15:
		return
	var left: bool = sx < 0.0
	if left != _facing_left:
		_facing_left = left
		if sprite != null:
			sprite.flip_h = left

func _resolve_if_embedded() -> void:
	if level.is_walkable(grid_position, false):
		return
	var target: Vector2i = grid_position
	if level.has_method("nearest_walkable_cell"):
		target = level.nearest_walkable_cell(grid_position, false)
	else:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if level.is_walkable(grid_position + d, false):
				target = grid_position + d
				break
	if target == grid_position:
		return
	# Walk out instead of teleporting when the cell is adjacent; snap only as a last resort.
	if absi(target.x - grid_position.x) + absi(target.y - grid_position.y) <= 1:
		if path.is_empty() or path[0] != target:
			path = [target]
		return
	grid_position = target
	global_position = level.map_to_world(target) + Vector3(0, _y_offset(), 0)
	path.clear()
	if state == USING_SLOT:
		_release_slot()
		state = WANDER
	retarget_timer = 0.0

func _release_slot() -> void:
	if level != null and current_slot_id != -1:
		level.release_actor_slot(self)
	current_slot_id = -1

func on_slot_invalidated(slot_id: int) -> void:
	if slot_id != current_slot_id:
		return
	current_slot_id = -1
	if state == USING_SLOT:
		state = WANDER
	retarget_timer = 0.0
	path.clear()

# ---------------------------------------------------------------- visuals

func _figure_height_ratio() -> float:
	return 0.62 if _is_toddler() else 0.96

func _is_toddler() -> bool:
	return archetype_id == "hyper_toddler" or tags.has("playful") and tags.has("active")

func _setup_art() -> void:
	if art_viewport == null or sprite == null:
		return
	if _art == null:
		_art = PatronArt.new()
		_art.name = "PatronArt"
		art_viewport.add_child(_art)
		sprite.texture = art_viewport.get_texture()
		sprite.pixel_size = CANVAS_METERS / float(CANVAS_H)
		sprite.offset = Vector2(0, CANVAS_H * 0.5)
		if fallback_sprite != null:
			fallback_sprite.visible = false
		sprite.visible = true
	_art.configure_look(_build_look())
	_walk_frame = -1
	_redraw_art(0)

func _build_look() -> Dictionary:
	var look_rng := RandomNumberGenerator.new()
	look_rng.seed = rng.seed ^ 0x5eed
	var shirt: Color = tint
	shirt = shirt.lightened(look_rng.randf_range(-0.06, 0.08))
	return {
		"archetype": archetype_id,
		"toddler": _is_toddler(),
		"skin": SKIN_TONES[look_rng.randi_range(0, SKIN_TONES.size() - 1)],
		"hair": HAIR_COLORS[look_rng.randi_range(0, HAIR_COLORS.size() - 1)],
		"hair_style": look_rng.randi_range(0, 3),
		"shirt": shirt,
		"pants": PANTS_COLORS[look_rng.randi_range(0, PANTS_COLORS.size() - 1)],
		"accent": Color.from_hsv(look_rng.randf(), 0.45, 0.85),
	}

func _redraw_art(frame: int) -> void:
	if _art == null or art_viewport == null:
		return
	if frame == _walk_frame:
		return
	_walk_frame = frame
	_art.walk_frame = frame
	_art.queue_redraw()
	art_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _update_visuals(delta: float) -> void:
	_idle_t += delta
	var frame: int = 0
	if _is_moving:
		frame = 1 + (int(floor(_walk_phase / TAU * float(WALK_FRAMES))) % WALK_FRAMES)
	_redraw_art(frame)
	if anchor != null:
		var bob: float = 0.0
		var squash: float = 1.0
		if _is_moving:
			bob = absf(sin(_walk_phase)) * 0.035
		else:
			squash = 1.0 + sin(_idle_t * 2.2 + float(rng.seed % 7)) * 0.012
		anchor.position.y = bob
		anchor.scale = Vector3(1.0, squash, 1.0)


## Procedural 2D patron figure, drawn into the SubViewport (origin at the feet).
class PatronArt extends Node2D:
	const OUTLINE_W: float = 1.6
	const OUTLINE := Color("#3A2622")
	var look: Dictionary = {}
	var walk_frame: int = 0

	func configure_look(l: Dictionary) -> void:
		look = l
		position = Vector2(96, 312)
		scale = Vector2(2.0, 2.0)
		queue_redraw()

	func _col(key: String, fallback: Color) -> Color:
		var v = look.get(key, fallback)
		return v if v is Color else fallback

	func _ellipse(c: Vector2, rx: float, ry: float, n: int = 24) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in range(n):
			var a: float = TAU * float(i) / float(n)
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		return pts

	func _rrect(r: Rect2, rad: float, n: int = 5) -> PackedVector2Array:
		var pts := PackedVector2Array()
		rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
		var corners: Array = [
			[r.position + Vector2(r.size.x - rad, rad), -PI * 0.5],
			[r.position + Vector2(r.size.x - rad, r.size.y - rad), 0.0],
			[r.position + Vector2(rad, r.size.y - rad), PI * 0.5],
			[r.position + Vector2(rad, rad), PI],
		]
		for c in corners:
			for i in range(n + 1):
				var a: float = float(c[1]) + PI * 0.5 * float(i) / float(n)
				pts.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * rad)
		return pts

	func _capsule(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
		var d: Vector2 = (b - a)
		var ang: float = d.angle()
		var pts := PackedVector2Array()
		for i in range(9):
			var t: float = ang + PI * 0.5 + PI * float(i) / 8.0
			pts.append(a + Vector2(cos(t), sin(t)) * r)
		for i in range(9):
			var t: float = ang - PI * 0.5 + PI * float(i) / 8.0
			pts.append(b + Vector2(cos(t), sin(t)) * r)
		return pts

	func _outline_of(poly: PackedVector2Array, w: float = OUTLINE_W) -> PackedVector2Array:
		var res: Array = Geometry2D.offset_polygon(poly, w, Geometry2D.JOIN_ROUND)
		if res.is_empty():
			return poly
		var best: PackedVector2Array = res[0]
		for r in res:
			if (r as PackedVector2Array).size() > best.size():
				best = r
		return best

	func _poly(pts: PackedVector2Array, col: Color) -> void:
		if pts.size() >= 3:
			draw_colored_polygon(pts, col)

	func _shape(poly: PackedVector2Array, fill: Color) -> void:
		_poly(_outline_of(poly), OUTLINE)
		_poly(poly, fill)

	func _draw() -> void:
		if look.is_empty():
			return
		var toddler: bool = bool(look.get("toddler", false))
		var s: float = 0.62 if toddler else 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
		var skin: Color = _col("skin", Color("#EBC1A2"))
		var hair: Color = _col("hair", Color("#6B4430"))
		var shirt: Color = _col("shirt", Color("#8FA88A"))
		var pants: Color = _col("pants", Color("#4F5A73"))
		var accent: Color = _col("accent", Color("#E07A3F"))
		var arch: String = String(look.get("archetype", ""))
		var moving: bool = walk_frame > 0
		var ph: float = TAU * float(walk_frame - 1) / 8.0 if moving else 0.0
		var swing: float = sin(ph) if moving else 0.0
		var lift_l: float = maxf(0.0, sin(ph)) * 4.0 if moving else 0.0
		var lift_r: float = maxf(0.0, -sin(ph)) * 4.0 if moving else 0.0
		var head_r: float = 25.0 if toddler else 21.0
		var torso_top: float = -92.0 if not toddler else -78.0
		var hip_y: float = -46.0 if not toddler else -40.0
		var head_c := Vector2(0, torso_top - head_r + 4.0)

		# Toddler balloon (behind everything).
		if toddler:
			var hand := Vector2(26, hip_y - 8.0 + swing * 2.0)
			var bc := Vector2(30, head_c.y - 58.0)
			draw_line(hand, bc + Vector2(0, 17), Color(OUTLINE, 0.7), 1.2, true)
			_shape(_ellipse(bc, 14.0, 17.0), accent)
			_poly(_ellipse(bc + Vector2(-5, -6), 3.5, 5.0, 12), Color(1, 1, 1, 0.45))

		# Shoes and legs.
		var shoe := Color("#4A3426")
		for side in [-1, 1]:
			var lift: float = lift_l if side < 0 else lift_r
			var lx: float = float(side) * 8.0 + (swing * float(side) * 1.5)
			_shape(_capsule(Vector2(lx, hip_y + 2.0), Vector2(lx, -7.0 - lift), 6.5), pants)
			_shape(_ellipse(Vector2(lx + float(side) * 1.5, -4.0 - lift), 8.5, 4.5, 16), shoe)

		# Arms behind torso edges.
		var shoulder_y: float = torso_top + 8.0
		var hand_y: float = hip_y - 6.0
		var arm_w: float = 6.0
		var l_hand := Vector2(-23.0, hand_y - swing * 4.0)
		var r_hand := Vector2(23.0, hand_y + swing * 4.0)
		if arch == "gentle_reader" and not moving:
			l_hand = Vector2(-10.0, hip_y - 20.0)
			r_hand = Vector2(10.0, hip_y - 20.0)
		_shape(_capsule(Vector2(-18.0, shoulder_y), l_hand, arm_w), shirt.darkened(0.12))
		_shape(_capsule(Vector2(18.0, shoulder_y), r_hand, arm_w), shirt.darkened(0.12))

		# Torso.
		var torso := PackedVector2Array([
			Vector2(-17, torso_top + 2), Vector2(17, torso_top + 2),
			Vector2(21, torso_top + 10), Vector2(20, hip_y + 4), Vector2(-20, hip_y + 4), Vector2(-21, torso_top + 10)
		])
		var torso_r: PackedVector2Array = _outline_of(torso, 3.0)
		_shape(torso_r, shirt)
		# Archetype details on the torso.
		match arch:
			"gentle_reader":
				# Cardigan opening and buttons.
				_poly(PackedVector2Array([Vector2(-4, torso_top + 3), Vector2(4, torso_top + 3), Vector2(2, hip_y + 6), Vector2(-2, hip_y + 6)]), Color("#F3E6D3"))
				for i in range(3):
					draw_circle(Vector2(-4.5, torso_top + 14.0 + float(i) * 10.0), 1.4, shirt.darkened(0.4), true, -1.0, true)
			"busy_remote_worker":
				# Bag strap across the chest + collar.
				draw_line(Vector2(-16, torso_top + 4), Vector2(17, hip_y + 2), Color("#5A3E2E"), 3.5, true)
				_poly(PackedVector2Array([Vector2(-7, torso_top + 2), Vector2(0, torso_top + 9), Vector2(7, torso_top + 2)]), Color("#F3E6D3"))
			"hyper_toddler":
				# Overalls bib with buttons.
				_poly(_rrect(Rect2(-12, torso_top + 12, 24, hip_y - torso_top - 6), 4.0), pants.lightened(0.15))
				draw_line(Vector2(-12, torso_top + 13), Vector2(-15, torso_top + 3), pants.lightened(0.15), 3.0, true)
				draw_line(Vector2(12, torso_top + 13), Vector2(15, torso_top + 3), pants.lightened(0.15), 3.0, true)
				draw_circle(Vector2(-7, torso_top + 16), 1.6, Color("#F2D16B"), true, -1.0, true)
				draw_circle(Vector2(7, torso_top + 16), 1.6, Color("#F2D16B"), true, -1.0, true)
			_:
				pass

		# Hands and held props.
		if arch == "gentle_reader" and not moving:
			var book := Rect2(-13, hip_y - 30.0, 26, 18)
			_shape(_rrect(book, 2.0), Color("#B86F6F"))
			draw_line(Vector2(0, book.position.y + 1), Vector2(0, book.end.y - 1), Color("#F3E6D3"), 1.5, true)
		if arch == "busy_remote_worker":
			var mug_c := r_hand + Vector2(4, -4)
			_shape(_rrect(Rect2(mug_c - Vector2(5, 6), Vector2(10, 11)), 2.0), Color("#F3E6D3"))
			draw_arc(mug_c + Vector2(6, 0), 3.0, -PI * 0.5, PI * 0.5, 8, OUTLINE, 1.4, true)
		_shape(_ellipse(l_hand, 5.0, 5.0, 14), skin)
		_shape(_ellipse(r_hand, 5.0, 5.0, 14), skin)

		# Neck + head.
		_poly(_rrect(Rect2(-5, torso_top - 6, 10, 10), 3.0), skin.darkened(0.08))
		var style: int = int(look.get("hair_style", 0))
		if style == 2 and not toddler:
			# Long hair behind the head.
			_shape(_rrect(Rect2(head_c.x - head_r - 2, head_c.y - 4, head_r * 2 + 4, head_r + 16), 8.0), hair.darkened(0.08))
		if style == 3:
			_shape(_ellipse(head_c + Vector2(0, -head_r - 3), 9.0, 8.0, 16), hair)
		_shape(_ellipse(head_c, head_r, head_r * 0.98, 32), skin)
		# Hair cap.
		var cap := PackedVector2Array()
		var fringe_y: float = head_c.y - head_r * (0.15 if style != 1 else 0.3)
		var hr: float = head_r + 1.5
		var side_y: float = maxf(fringe_y + 4.0, head_c.y + 0.5)
		cap.append(Vector2(head_c.x - hr, side_y))
		for i in range(17):
			var a: float = PI + 0.12 + (PI - 0.24) * float(i) / 16.0
			cap.append(head_c + Vector2(cos(a) * hr, sin(a) * hr))
		cap.append(Vector2(head_c.x + hr, side_y))
		cap.append(Vector2(head_c.x + head_r * 0.35, fringe_y - 3.0))
		cap.append(Vector2(head_c.x - head_r * 0.1, fringe_y + 1.0))
		cap.append(Vector2(head_c.x - head_r * 0.6, fringe_y - 2.0))
		_poly(cap, hair)
		if style == 1:
			# Curly bumps.
			for i in range(5):
				var a: float = PI + PI * (0.1 + 0.8 * float(i) / 4.0)
				draw_circle(head_c + Vector2(cos(a), sin(a)) * (head_r + 1.0), 5.0, hair, true, -1.0, true)
		# Face.
		var eye_y: float = head_c.y + head_r * 0.12
		var eye_dx: float = head_r * 0.36
		for side in [-1, 1]:
			_poly(_ellipse(Vector2(head_c.x + float(side) * eye_dx, eye_y), 2.2, 3.0, 12), Color("#2A1C1E"))
			draw_circle(Vector2(head_c.x + float(side) * eye_dx + 0.7, eye_y - 1.2), 0.8, Color(1, 1, 1, 0.9), true, -1.0, true)
			_poly(_ellipse(Vector2(head_c.x + float(side) * (eye_dx + 4.5), eye_y + 6.0), 3.6, 2.0, 12), Color(0.93, 0.5, 0.5, 0.45))
		draw_arc(Vector2(head_c.x, eye_y + 5.5), 3.2, 0.35, PI - 0.35, 10, Color("#5A2E2A"), 1.3, true)
		if arch == "gentle_reader":
			for side in [-1, 1]:
				draw_arc(Vector2(head_c.x + float(side) * eye_dx, eye_y), 5.0, 0.0, TAU, 18, Color("#5A3E2E"), 1.2, true)
			draw_line(Vector2(head_c.x - eye_dx + 5.0, eye_y), Vector2(head_c.x + eye_dx - 5.0, eye_y), Color("#5A3E2E"), 1.2, true)
		if arch == "busy_remote_worker":
			# Headphones band.
			draw_arc(head_c, head_r + 3.0, PI * 1.05, PI * 1.95, 18, Color("#3E4A45"), 3.0, true)
			for side in [-1, 1]:
				_shape(_rrect(Rect2(head_c.x + float(side) * (head_r + 1.0) - 4.0, head_c.y - 6.0, 8.0, 12.0), 3.0), Color("#3E4A45"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
