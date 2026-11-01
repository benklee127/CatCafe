extends CharacterBody3D

## 3D cat actor. Grid path is authoritative; the body moves with velocity + move_and_slide.
## API per PLAN.md §1.3. Level/patron APIs from other tracks are always called behind has_method guards.

signal state_changed(cat, old_state: StringName, new_state: StringName)
signal trust_state_changed(cat, old_id: StringName, new_id: StringName)
signal retreated(cat)

const IDLE := &"idle"
const WANDER := &"wander"
const INTERACTING := &"interacting"
const RETREATING := &"retreating"
const REST := &"rest"
const RETURNING := &"returning"

const TRUST_FEARFUL := &"fearful"
const TRUST_WARMING := &"warming"
const TRUST_BONDED := &"bonded"
const TRUST_ADOPTABLE := &"adoptable"

const REPATH_RETRY_SEC: float = 0.5
## RETREATING with no route this long -> hide in place (GP-03: never a permanent drought).
const RETREAT_STUCK_SEC: float = 4.0
## Fearful cats step away from patrons once overstim passes this share of the threshold.
const SHY_OVERSTIM_RATIO: float = 0.7
const SHY_COOLDOWN_SEC: float = 5.0
const DECOR_REFRESH_SEC: float = 0.25
const FACING_DEADZONE: float = 0.15
const BAR_PX_W: int = 50
const BAR_PX_H: int = 8
const BAR_HIDE_BELOW: float = 15.0
const BAR_COLOR_LOW := Color("#8FBF9F")
const BAR_COLOR_MID := Color("#E8B04B")
const BAR_COLOR_HIGH := Color("#E07A3F")

const DEFAULT_TRUST_STATES: Array = [
	{"id": "fearful", "min": 0.0, "overstim_mult": 1.25, "seeks_slots": false},
	{"id": "warming", "min": 25.0, "overstim_mult": 1.0, "seeks_slots": true},
	{"id": "bonded", "min": 60.0, "overstim_mult": 0.85, "seeks_slots": true},
	{"id": "adoptable", "min": 100.0, "overstim_mult": 0.85, "seeks_slots": true},
]

# Fallback tuning only: balance_config values override these in configure().
@export var move_speed: float = 2.8
@export var interaction_radius: float = 1.8
@export var overstimulation: float = 0.0
@export var overstim_gain_per_sec: float = 11.0
@export var overstim_recovery_per_sec: float = 25.0
@export var passive_calm_per_sec: float = 4.0
@export var overstim_threshold: float = 100.0
@export var rest_release_threshold: float = 35.0
@export var idle_duration_min: float = 0.6
@export var idle_duration_max: float = 1.8
@export var slot_seek_interval_min: float = 0.8
@export var slot_seek_interval_max: float = 1.6

# Rig rendering (viewport/sprite setup only). pixel_art renders Cat2D into a
# pixel_density x pixel_density SubViewport (no MSAA, 1px outlines) and shows it
# with NEAREST filtering; off = the smooth 192px viewport with linear filtering.
# Either way the sprite covers the same RIG_WORLD_SIZE meters with the feet on
# the actor origin. 56 = ~1 art px per screen px vertically and ~1.3 horizontally
# at the default camera size (14.5) on a 1600x900 window.
@export var pixel_art: bool = true
@export_range(32, 192) var pixel_density: int = 56
const RIG_VIEW_UNITS: float = 76.8        # Cat2D units across the viewport
const RIG_FOOT_FRAC: float = 182.0 / 192.0  # feet row as a fraction of the viewport height
const RIG_WORLD_SIZE: float = 1.2         # meters the viewport square covers
const RIG_SMOOTH_PX: int = 192
const CatPixelPipelineScript := preload("res://Scripts/prototype3d/CatPixelPipeline.gd")
var _pixel_pipeline: Node = null   # mask-outline compositor (pixel_art only)
# Debug overrides (MainLevel3D debug panel). Visual only: cat_def is untouched.
var _eye_override: String = ""
var _expr_override: String = ""
var _auto_expr: String = ""

var level
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var grid_position: Vector2i = Vector2i.ZERO
var target_grid: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var state: StringName = IDLE
var retarget_timer: float = 0.0
var idle_timer: float = 0.0
var slot_seek_timer: float = 0.0
var repath_timer: float = 0.0
var current_slot_id: int = -1

# Identity / data
var cat_id: String = ""
var display_name: String = ""
var cat_def: Dictionary = {}
var balance: Dictionary = {}
var trait_ids: Array[String] = []
var trait_display_names: Array[String] = []
var rarity: String = "common"
var adoption_tags: Array[String] = []

# Overstim tuning (resolved from balance)
var crowd_mult: float = 0.35
var trait_overstim_mult: float = 1.0
var trait_trust_mult: float = 1.0
var walk_speed_mult: float = 1.0

# Trust
var trust: float = 10.0
var trust_max: float = 100.0
var trust_state: StringName = TRUST_FEARFUL
var ready_for_adoption: bool = false
var trust_daily_base_gain: float = 6.0
var trust_day_length_sec: float = 180.0
var trust_stress_penalty: float = 4.0
var trust_ready_threshold: float = 100.0
var trust_calm_ratio: float = 0.5
var trust_hysteresis: float = 10.0
var trust_good_company_mult: float = 1.5
var trust_states: Array = []
var trust_calm_interaction_bonus: float = 0.0
var trust_rest_gain_mult: float = 0.0
var trust_penalty_window_sec: float = 0.0
var trust_penalty_isolated_mult: float = 1.0
var min_rest_sec: float = 0.0
var post_rest_grace_sec: float = 0.0
var post_rest_gain_mult: float = 1.0
var _since_last_retreat: float = 1.0e9
var _rest_timer: float = 0.0
var _grace_timer: float = 0.0
var _retreat_stuck_timer: float = 0.0
var _shy_timer: float = 0.0
var hiding_in_place: bool = false
var _embed_goal: Vector2i = Vector2i(-99999, -99999)

# Perception caches
var nearby_count: int = 0
var nearby_pressure: float = 0.0
var nearby_patrons: Array = []
var decor_effects: Dictionary = {}
var _decor_timer: float = 0.0
var _decor_cell: Vector2i = Vector2i(-99999, -99999)

# Visuals
var use_viewport_rig: bool = true
var _is_moving: bool = false
var _last_pose: StringName = &""
var _last_move_speed: float = -1.0
var _facing_left: bool = false
var _bar_texture: ImageTexture

@onready var billboard_anchor: Node3D = get_node_or_null("BillboardAnchor")
@onready var sprite: Sprite3D = get_node_or_null("BillboardAnchor/Sprite3D")
@onready var fallback_sprite: Sprite3D = get_node_or_null("BillboardAnchor/FallbackSprite3D")
@onready var cat_viewport: SubViewport = get_node_or_null("CatViewport")
@onready var cat2d: Node = get_node_or_null("CatViewport/Cat2D")
@onready var state_glyph: Label3D = get_node_or_null("BillboardAnchor/StateGlyph")
@onready var overstim_bar: Node3D = get_node_or_null("BillboardAnchor/OverstimBar")
@onready var bar_back: Sprite3D = get_node_or_null("BillboardAnchor/OverstimBar/Back")
@onready var bar_fill: Sprite3D = get_node_or_null("BillboardAnchor/OverstimBar/Fill")

# ---------------------------------------------------------------- lifecycle

func _ready() -> void:
	add_to_group("cats")
	collision_layer = 2
	collision_mask = 0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	rng.randomize()
	_reset_timers()
	if trust_states.is_empty():
		trust_states = DEFAULT_TRUST_STATES.duplicate(true)
	_setup_rig()
	if level != null:
		_apply_genome_to_rig()
	_setup_overstim_bar()
	if cat_id == "":
		cat_id = String(name)
	if display_name == "":
		display_name = String(name)

func configure(main_level, spawn_grid: Vector2i, p_cat_def: Dictionary = {}, p_balance: Dictionary = {}) -> void:
	level = main_level
	grid_position = spawn_grid
	target_grid = spawn_grid
	path.clear()
	cat_def = p_cat_def.duplicate(true)
	balance = p_balance
	if balance.is_empty() and level != null:
		var level_data = level.get("data")
		if level_data is Dictionary:
			var bc = (level_data as Dictionary).get("balance_config", {})
			if bc is Dictionary:
				balance = bc
	if cat_def.has("seed"):
		rng.seed = int(cat_def["seed"])
	else:
		rng.randomize()
	_apply_balance()
	_apply_cat_def()
	_reset_timers()
	idle_timer = 1.0
	global_position = level.map_to_world(spawn_grid) + Vector3(0, _y_offset(), 0)
	velocity = Vector3.ZERO
	state = IDLE
	_refresh_trust_state(false)
	_restore_saved_state()
	_apply_genome_to_rig()

## GP-07: a cat saved stressed (retreating/rest/returning, or overstim at or above the
## rest release threshold) reloads napping in the rest area instead of idle on the floor.
func _restore_saved_state() -> void:
	var o_d: Dictionary = _dict(cat_def, "overstim")
	var saved_state: String = str(o_d.get("actor_state", ""))
	var stressed: bool = overstimulation >= rest_release_threshold
	if saved_state in ["retreating", "rest", "returning"]:
		stressed = true
	if not stressed or level == null:
		return
	var cell: Vector2i = level.random_rest_cell()
	if not level.is_in_rest_area(cell) or not level.is_walkable(cell, true):
		# No room in the rest area: calm the cat down instead of re-triggering a retreat.
		overstimulation = minf(overstimulation, trust_calm_ratio * overstim_threshold * 0.9)
		return
	grid_position = cell
	target_grid = cell
	global_position = level.map_to_world(cell) + Vector3(0, _y_offset(), 0)
	state = REST
	_rest_timer = 0.0

func _reset_timers() -> void:
	retarget_timer = rng.randf_range(0.2, 0.9)
	idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)
	slot_seek_timer = rng.randf_range(slot_seek_interval_min, slot_seek_interval_max)
	repath_timer = 0.0

func _physics_process(delta: float) -> void:
	if level == null:
		return
	grid_position = level.world_to_map(global_position)
	_tick_timers(delta)
	_resolve_if_embedded()
	_sense(delta)
	_update_overstim(delta)
	_update_trust(delta)
	_update_state()
	_update_pathing(delta)
	_follow_path(delta)
	_update_visual_state()

func _tick_timers(delta: float) -> void:
	_since_last_retreat += delta
	if _grace_timer > 0.0:
		_grace_timer -= delta
	if _shy_timer > 0.0:
		_shy_timer -= delta
	if state == REST:
		_rest_timer += delta
	if state == RETREATING and path.is_empty() and not level.is_in_rest_area(grid_position):
		_retreat_stuck_timer += delta
	else:
		_retreat_stuck_timer = 0.0

# ---------------------------------------------------------------- data

func _dict(src: Dictionary, key: String) -> Dictionary:
	var v = src.get(key, {})
	return v if v is Dictionary else {}

func _num(src: Dictionary, key: String, fallback: float) -> float:
	var v = src.get(key, fallback)
	if v is float or v is int:
		return float(v)
	return fallback

func _apply_balance() -> void:
	var o: Dictionary = _dict(balance, "overstim")
	passive_calm_per_sec = _num(o, "base_decay_per_sec", passive_calm_per_sec)
	overstim_threshold = _num(o, "retreat_threshold", overstim_threshold)
	overstim_recovery_per_sec = _num(o, "rest_recovery_per_sec", overstim_recovery_per_sec)
	rest_release_threshold = _num(o, "rest_release_threshold", rest_release_threshold)
	overstim_gain_per_sec = _num(o, "interaction_gain_per_sec", overstim_gain_per_sec)
	crowd_mult = _num(o, "crowd_mult", crowd_mult)
	min_rest_sec = maxf(0.0, _num(o, "min_rest_sec", min_rest_sec))
	post_rest_grace_sec = maxf(0.0, _num(o, "post_rest_grace_sec", post_rest_grace_sec))
	post_rest_gain_mult = clampf(_num(o, "post_rest_gain_mult", post_rest_gain_mult), 0.0, 1.0)
	var t: Dictionary = _dict(balance, "trust")
	trust_daily_base_gain = _num(t, "daily_base_gain", trust_daily_base_gain)
	trust_day_length_sec = maxf(1.0, _num(t, "day_length_sec", _num(_dict(balance, "population"), "day_length_sec", trust_day_length_sec)))
	trust_stress_penalty = _num(t, "stress_penalty", trust_stress_penalty)
	trust_ready_threshold = _num(t, "ready_threshold", trust_ready_threshold)
	trust_calm_ratio = _num(t, "calm_overstim_ratio", trust_calm_ratio)
	trust_hysteresis = _num(t, "adoptable_hysteresis", trust_hysteresis)
	trust_good_company_mult = _num(t, "good_company_mult", trust_good_company_mult)
	trust_calm_interaction_bonus = maxf(0.0, _num(t, "calm_interaction_bonus_per_sec", trust_calm_interaction_bonus))
	trust_rest_gain_mult = maxf(0.0, _num(t, "rest_gain_mult", trust_rest_gain_mult))
	trust_penalty_window_sec = maxf(0.0, _num(t, "stress_repeat_window_sec", trust_penalty_window_sec))
	trust_penalty_isolated_mult = clampf(_num(t, "stress_isolated_mult", trust_penalty_isolated_mult), 0.0, 1.0)
	trust = _num(t, "start", trust)
	var raw_states = t.get("states", [])
	if raw_states is Array and not (raw_states as Array).is_empty():
		var parsed: Array = []
		for s in raw_states:
			if s is Dictionary and (s as Dictionary).has("id"):
				parsed.append(s)
		if not parsed.is_empty():
			parsed.sort_custom(func(a, b): return _num(a, "min", 0.0) < _num(b, "min", 0.0))
			trust_states = parsed

func _apply_cat_def() -> void:
	if cat_def.is_empty():
		return
	cat_id = str(cat_def.get("id", cat_id if cat_id != "" else String(name)))
	display_name = str(cat_def.get("display_name", display_name if display_name != "" else cat_id))
	rarity = str(cat_def.get("rarity", "common"))
	var trust_d: Dictionary = _dict(cat_def, "trust")
	trust = _num(trust_d, "current", trust)
	trust_max = maxf(1.0, _num(trust_d, "max", trust_max))
	ready_for_adoption = bool(trust_d.get("ready_for_adoption", false))
	var o_d: Dictionary = _dict(cat_def, "overstim")
	overstimulation = _num(o_d, "current", overstimulation)

	# Traits: prefer embedded dicts, else resolve ids against level data.
	var trait_dicts: Array = []
	var raw_traits = cat_def.get("traits", [])
	if raw_traits is Array:
		for t in raw_traits:
			if t is Dictionary:
				trait_dicts.append(t)
	var raw_ids = cat_def.get("trait_ids", [])
	if trait_dicts.is_empty() and raw_ids is Array and not (raw_ids as Array).is_empty():
		var lookup: Dictionary = {}
		var level_data = level.get("data") if level != null else null
		if level_data is Dictionary:
			for t in (level_data as Dictionary).get("traits", []):
				if t is Dictionary:
					lookup[str(t.get("id", ""))] = t
		for tid in raw_ids:
			if lookup.has(str(tid)):
				trait_dicts.append(lookup[str(tid)])
			else:
				trait_dicts.append({"id": str(tid), "display_name": str(tid).capitalize()})

	trait_ids.clear()
	trait_display_names.clear()
	adoption_tags.clear()
	var o_mult: float = 1.0
	var t_mult: float = 1.0
	for t in trait_dicts:
		var tid: String = str(t.get("id", ""))
		if tid != "" and not trait_ids.has(tid):
			trait_ids.append(tid)
		trait_display_names.append(str(t.get("display_name", tid.capitalize())))
		o_mult *= _num(t, "overstim_rate_mult", 1.0)
		t_mult *= _num(t, "trust_gain_mult", 1.0)
		for tag in t.get("adoption_match_tags", []):
			if not adoption_tags.has(str(tag)):
				adoption_tags.append(str(tag))
	if trait_ids.is_empty() and raw_ids is Array:
		for tid in raw_ids:
			trait_ids.append(str(tid))
	var o: Dictionary = _dict(balance, "overstim")
	var lo: float = _num(o, "trait_mult_min", 0.5)
	var hi: float = _num(o, "trait_mult_max", 2.0)
	trait_overstim_mult = clampf(o_mult, lo, hi)
	trait_trust_mult = clampf(t_mult, lo, hi)

	var genome: Dictionary = _dict(cat_def, "genome")
	walk_speed_mult = clampf(_num(genome, "walk_speed_mult", 1.0), 0.5, 2.0)

func _apply_genome_to_rig() -> void:
	if cat2d == null or not cat2d.has_method("apply_genome"):
		return
	if cat_def.is_empty():
		return
	var genome: Dictionary = _dict(cat_def, "genome")
	if genome.is_empty():
		genome = _dict(cat_def, "visual")
	if genome.is_empty():
		return
	if _eye_override != "":
		genome = genome.duplicate()
		genome["eye_shape"] = _eye_override
	cat2d.call("apply_genome", genome)
	if _expr_override != "" and cat2d.has_method("set_expression"):
		cat2d.call("set_expression", _expr_override)

## Debug: show this eye shape instead of the genome's ("" = genome shape).
func set_eye_shape_override(shape: String) -> void:
	if shape == _eye_override:
		return
	_eye_override = shape
	_apply_genome_to_rig()

## Debug: force a face expression ("" = auto: the state-driven face from
## _update_expression).
func set_expression_override(expr: String) -> void:
	_expr_override = expr
	_auto_expr = ""
	if cat2d != null and cat2d.has_method("set_expression"):
		cat2d.call("set_expression", expr if expr != "" else "open")
	_update_expression()

# Visual only: the face follows the cat's existing state / overstim values
# (no gameplay effect). The debug override wins while set.
func _update_expression() -> void:
	if cat2d == null or _expr_override != "" or not cat2d.has_method("set_expression"):
		return
	var ratio: float = overstimulation / maxf(overstim_threshold, 0.001)
	var want: String = "open"
	if state == REST:
		want = "sleepy"
	elif state == RETREATING:
		want = "stressed"
	elif ratio >= 0.85:
		want = "angry"
	elif ratio >= 0.6:
		want = "worried"
	elif ready_for_adoption:
		want = "happy"
	if want != _auto_expr:
		_auto_expr = want
		cat2d.call("set_expression", want)

func _y_offset() -> float:
	if level == null:
		return 0.0
	var v = level.get("actor_y_offset")
	return float(v) if (v is float or v is int) else 0.0

# ---------------------------------------------------------------- perception

func _sense(delta: float) -> void:
	nearby_patrons = []
	if level.has_method("get_overstim_pressure_near"):
		var info = level.get_overstim_pressure_near(global_position, interaction_radius)
		if info is Dictionary:
			nearby_count = int(info.get("count", 0))
			nearby_pressure = float(info.get("pressure", 0.0))
			var ps = info.get("patrons", [])
			if ps is Array:
				nearby_patrons = ps
		else:
			nearby_count = 0
			nearby_pressure = 0.0
	else:
		nearby_count = int(level.get_patrons_near(global_position, interaction_radius))
		nearby_pressure = -1.0
	_decor_timer -= delta
	if _decor_timer <= 0.0 or _decor_cell != grid_position:
		_decor_timer = DECOR_REFRESH_SEC
		_decor_cell = grid_position
		if level.has_method("get_decor_effects_at"):
			var fx = level.get_decor_effects_at(grid_position)
			decor_effects = fx if fx is Dictionary else {}
		else:
			decor_effects = {}

func _decor(key: String, fallback: float) -> float:
	return _num(decor_effects, key, fallback)

# ---------------------------------------------------------------- overstim

func _current_trust_entry() -> Dictionary:
	for s in trust_states:
		if StringName(str(s.get("id", ""))) == trust_state:
			return s
	return {}

func _update_overstim(delta: float) -> void:
	if state == REST:
		var rec: float = overstim_recovery_per_sec * _decor("overstim_decay_mult", 1.0)
		overstimulation = maxf(0.0, overstimulation - rec * delta)
		return
	if state == INTERACTING:
		var gain: float
		if nearby_pressure >= 0.0:
			gain = nearby_pressure
		else:
			var n: int = nearby_count
			gain = float(n) * overstim_gain_per_sec * (1.0 + crowd_mult * float(maxi(n - 1, 0)))
		gain *= trait_overstim_mult
		gain *= _num(_current_trust_entry(), "overstim_mult", 1.0)
		gain *= _decor("interaction_mult", 1.0)
		if _grace_timer > 0.0:
			gain *= post_rest_gain_mult
		var relief: float = 0.0
		if current_slot_id != -1 and level.has_slot(current_slot_id) and grid_position == level.get_slot_grid(current_slot_id):
			relief = _decor("mid_rest_reduction", 0.0)
		overstimulation = clampf(overstimulation + (gain - relief) * delta, 0.0, overstim_threshold)
		return
	# IDLE, WANDER, RETREATING, RETURNING: passive calm only.
	var decay: float = passive_calm_per_sec * _decor("overstim_decay_mult", 1.0)
	overstimulation = maxf(0.0, overstimulation - decay * delta)

# ---------------------------------------------------------------- trust

func _update_trust(delta: float) -> void:
	if state == RETREATING or state == RETURNING:
		return
	if state != REST and overstimulation >= trust_calm_ratio * overstim_threshold:
		return
	var rate: float = trust_daily_base_gain / trust_day_length_sec
	if state == REST:
		# A safe nap still builds a little trust (GP-01).
		rate *= trust_rest_gain_mult
	elif state == INTERACTING:
		# Calm time with people is what builds trust fastest (GP-01).
		rate += trust_calm_interaction_bonus
		if _has_good_company():
			rate *= trust_good_company_mult
	rate *= trait_trust_mult * _decor("trust_gain_mult", 1.0)
	if rate > 0.0:
		_set_trust(trust + rate * delta)

func _has_good_company() -> bool:
	if nearby_patrons.size() != 1 or adoption_tags.is_empty():
		return false
	var p = nearby_patrons[0]
	if not is_instance_valid(p):
		return false
	var tags = p.get("tags")
	if not (tags is Array):
		return false
	for tag in tags:
		if adoption_tags.has(str(tag)):
			return true
	return false

func add_trust(amount: float) -> void:
	_set_trust(trust + amount)

func _set_trust(value: float) -> void:
	trust = clampf(value, 0.0, trust_max)
	_refresh_trust_state(true)

func _refresh_trust_state(emit: bool) -> void:
	if trust >= trust_ready_threshold:
		ready_for_adoption = true
	elif trust < trust_ready_threshold - trust_hysteresis:
		ready_for_adoption = false
	var new_id: StringName = TRUST_FEARFUL
	if not trust_states.is_empty():
		new_id = StringName(str(trust_states[0].get("id", "fearful")))
	for s in trust_states:
		if trust >= _num(s, "min", 0.0):
			new_id = StringName(str(s.get("id", "")))
	if ready_for_adoption and not trust_states.is_empty():
		new_id = StringName(str(trust_states[trust_states.size() - 1].get("id", "adoptable")))
	if new_id != trust_state:
		var old_id: StringName = trust_state
		trust_state = new_id
		if emit:
			trust_state_changed.emit(self, old_id, new_id)

func _seeks_slots() -> bool:
	var entry: Dictionary = _current_trust_entry()
	if entry.has("seeks_slots"):
		return bool(entry["seeks_slots"])
	return trust_state != TRUST_FEARFUL

# ---------------------------------------------------------------- state machine

func _set_state(new_state: StringName) -> void:
	if new_state == state:
		return
	var old: StringName = state
	state = new_state
	state_changed.emit(self, old, new_state)

func _to_idle() -> void:
	_set_state(IDLE)
	idle_timer = rng.randf_range(idle_duration_min, idle_duration_max)

func _update_state() -> void:
	if state != RETREATING and state != REST and overstimulation >= overstim_threshold:
		_begin_retreat()
		return
	if state == RETREATING and level.is_in_rest_area(grid_position) and path.is_empty():
		_release_slot()
		hiding_in_place = false
		_rest_timer = 0.0
		_set_state(REST)
		return
	if state == RETREATING and _retreat_stuck_timer >= RETREAT_STUCK_SEC:
		# GP-03: rest area unreachable -> hide and recover on the spot.
		_release_slot()
		path.clear()
		_stop_moving()
		hiding_in_place = true
		_rest_timer = 0.0
		_set_state(REST)
		return
	if state == REST and overstimulation <= rest_release_threshold and _rest_timer >= min_rest_sec:
		if hiding_in_place or not level.is_in_rest_area(grid_position):
			hiding_in_place = false
			_grace_timer = post_rest_grace_sec
			_to_idle()
		else:
			_begin_return()
		return
	if state == RETURNING and not level.is_in_rest_area(grid_position):
		path.clear()
		_grace_timer = post_rest_grace_sec
		_to_idle()
		return
	if state == RETREATING or state == REST or state == RETURNING:
		return
	if state == INTERACTING and not _seeks_slots() and overstimulation >= SHY_OVERSTIM_RATIO * overstim_threshold:
		_begin_shy_away()
		return
	if nearby_count > 0 and _shy_timer > 0.0:
		return
	if nearby_count > 0:
		if state != INTERACTING:
			_set_state(INTERACTING)
			path.clear()
		return
	if state == INTERACTING:
		_release_slot()
		_to_idle()

func _update_pathing(delta: float) -> void:
	if repath_timer > 0.0:
		repath_timer -= delta
	if state == RETREATING:
		if path.is_empty() and not level.is_in_rest_area(grid_position) and repath_timer <= 0.0:
			_plan_retreat_path()
		return
	if state == RETURNING:
		if path.is_empty() and repath_timer <= 0.0:
			_plan_return_path()
		return
	if state == INTERACTING:
		_update_interacting(delta)
		return
	if state == IDLE:
		idle_timer -= delta
		if idle_timer <= 0.0:
			_set_state(WANDER)
			retarget_timer = 0.0
		return
	if state != WANDER:
		return
	retarget_timer -= delta
	if retarget_timer > 0.0:
		return
	retarget_timer = rng.randf_range(1.2, 2.4)
	target_grid = level.random_cafe_cell()
	path = level.build_path(grid_position, target_grid, false)

func _update_interacting(delta: float) -> void:
	if current_slot_id != -1:
		if not level.has_slot(current_slot_id):
			current_slot_id = -1
			return
		var slot_grid: Vector2i = level.get_slot_grid(current_slot_id)
		if grid_position != slot_grid and path.is_empty() and repath_timer <= 0.0:
			path = level.build_path(grid_position, slot_grid, false)
			if path.is_empty():
				repath_timer = REPATH_RETRY_SEC
		return
	if not _seeks_slots():
		return
	slot_seek_timer -= delta
	if slot_seek_timer > 0.0:
		return
	slot_seek_timer = rng.randf_range(slot_seek_interval_min, slot_seek_interval_max)
	var slot_id: int = level.request_best_slot(&"cat", self, grid_position, false)
	if slot_id == -1:
		return
	if not level.claim_slot(slot_id, self):
		return
	current_slot_id = slot_id
	var slot_grid: Vector2i = level.get_slot_grid(current_slot_id)
	path = level.build_path(grid_position, slot_grid, false)
	if path.is_empty() and slot_grid != grid_position:
		_release_slot()

## GP-01: a fearful cat that is getting overwhelmed walks away from the patrons around it
## instead of sitting there until it bolts for the rest area.
func _begin_shy_away() -> void:
	_release_slot()
	_shy_timer = SHY_COOLDOWN_SEC
	_set_state(WANDER)
	retarget_timer = rng.randf_range(2.0, 3.0)
	var best: Vector2i = grid_position
	var best_score: float = -1.0
	for _i in range(8):
		var c: Vector2i = level.random_cafe_cell()
		var w: Vector3 = level.map_to_world(c)
		var score: float = 1.0e9
		for p in nearby_patrons:
			if is_instance_valid(p):
				var pp: Vector3 = (p as Node3D).global_position
				score = minf(score, Vector2(pp.x, pp.z).distance_to(Vector2(w.x, w.z)))
		if score > best_score:
			best_score = score
			best = c
	target_grid = best
	path = level.build_path(grid_position, best, false)

func _path_allows_rest() -> bool:
	return state == RETREATING or state == REST or state == RETURNING or level.is_in_rest_area(grid_position)

func _follow_path(delta: float) -> void:
	if path.is_empty():
		_stop_moving()
		return
	var next_grid: Vector2i = path[0]
	if not level.is_walkable(next_grid, _path_allows_rest()):
		path.clear()
		_stop_moving()
		if state == INTERACTING:
			_release_slot()
			_to_idle()
		elif state == WANDER:
			retarget_timer = 0.0
		elif state == RETREATING or state == RETURNING:
			repath_timer = REPATH_RETRY_SEC
		return
	var next_world: Vector3 = level.map_to_world(next_grid) + Vector3(0, _y_offset(), 0)
	var step: Vector3 = next_world - global_position
	step.y = 0.0
	var distance: float = step.length()
	if distance <= 0.06:
		global_position = Vector3(next_world.x, next_world.y, next_world.z)
		grid_position = next_grid
		path.remove_at(0)
		if path.is_empty():
			_stop_moving()
		return
	var speed: float = move_speed * walk_speed_mult * _decor("pathing_speed_mult", 1.0)
	var dir: Vector3 = step / distance
	velocity = dir * minf(speed, distance / maxf(delta, 0.0001))
	move_and_slide()
	global_position.y = next_world.y
	_is_moving = true
	_update_facing(dir)

func _stop_moving() -> void:
	velocity = Vector3.ZERO
	_is_moving = false

func _resolve_if_embedded() -> void:
	var allow_rest: bool = _path_allows_rest()
	if level.is_walkable(grid_position, allow_rest):
		_embed_goal = Vector2i(-99999, -99999)
		return
	# CR-5: a walk-out path is already active; don't BFS again every frame.
	if _embed_goal.x != -99999 and not path.is_empty() and path.back() == _embed_goal:
		return
	var here_rest: bool = level.is_in_rest_area(grid_position)
	var candidate: Vector2i = grid_position
	var found: bool = false
	if level.has_method("nearest_walkable_cell"):
		var c = level.nearest_walkable_cell(grid_position, allow_rest)
		if c is Vector2i and c != grid_position and level.is_walkable(c, allow_rest):
			candidate = c
			found = true
	if not found or level.is_in_rest_area(candidate) != here_rest:
		# Local ring search, preferring the same side of the partition.
		var other_side: Vector2i = candidate
		var have_other: bool = found
		found = false
		for r in range(1, 5):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var cell: Vector2i = grid_position + Vector2i(dx, dy)
					if not level.is_walkable(cell, allow_rest):
						continue
					if level.is_in_rest_area(cell) == here_rest:
						candidate = cell
						found = true
						break
					elif not have_other:
						other_side = cell
						have_other = true
				if found:
					break
			if found:
				break
		if not found:
			if not have_other:
				return
			# Never teleport across the partition: walk there instead.
			if path.is_empty() or path.back() != other_side:
				var p: Array[Vector2i] = level.build_path(grid_position, other_side, true)
				if p.is_empty():
					p.append(other_side)
				path = p
			_embed_goal = other_side
			return
	grid_position = candidate
	global_position = level.map_to_world(candidate) + Vector3(0, _y_offset(), 0)
	path.clear()
	_stop_moving()
	if state == INTERACTING:
		_release_slot()
		_to_idle()

func _begin_retreat() -> void:
	_release_slot()
	var from_overstim: bool = overstimulation >= overstim_threshold
	_set_state(RETREATING)
	if from_overstim:
		# GP-01: a one-off retreat costs little; repeated retreats within the window cost
		# the full penalty.
		var penalty: float = trust_stress_penalty
		if trust_penalty_window_sec > 0.0 and _since_last_retreat > trust_penalty_window_sec:
			penalty *= trust_penalty_isolated_mult
		_since_last_retreat = 0.0
		_set_trust(trust - penalty)
		retreated.emit(self)
	repath_timer = 0.0
	_plan_retreat_path()

func _plan_retreat_path() -> void:
	repath_timer = REPATH_RETRY_SEC
	path.clear()
	var inner: Vector2i = level.random_rest_cell()
	if level.has_method("get_rest_entry_cell"):
		var entry = level.get_rest_entry_cell(grid_position)
		if entry is Vector2i:
			var to_entry: Array[Vector2i] = []
			if entry != grid_position:
				to_entry = level.build_path(grid_position, entry, true)
			if not to_entry.is_empty() or entry == grid_position:
				var deeper: Array[Vector2i] = []
				if level.is_walkable(inner, true) and inner != entry:
					deeper = level.build_path(entry, inner, true)
				to_entry.append_array(deeper)
				target_grid = inner if not deeper.is_empty() else entry
				path = to_entry
				if not path.is_empty():
					return
	target_grid = inner
	path = level.build_path(grid_position, target_grid, true)

func _begin_return() -> void:
	_set_state(RETURNING)
	repath_timer = 0.0
	_plan_return_path()

func _plan_return_path() -> void:
	repath_timer = REPATH_RETRY_SEC
	var goal: Vector2i = Vector2i(-99999, -99999)
	if level.has_method("get_rest_exit_cell"):
		var c = level.get_rest_exit_cell(grid_position)
		if c is Vector2i:
			goal = c
	if goal.x == -99999 or not level.is_walkable(goal, false):
		goal = level.random_cafe_cell()
	target_grid = goal
	path = level.build_path(grid_position, goal, true)

func _release_slot() -> void:
	if current_slot_id == -1:
		return
	level.release_actor_slot(self)
	current_slot_id = -1

func on_slot_invalidated(slot_id: int) -> void:
	if slot_id != current_slot_id:
		return
	current_slot_id = -1
	path.clear()
	if state == INTERACTING:
		_to_idle()

# ---------------------------------------------------------------- public API

func is_available_on_floor() -> bool:
	return not (state == RETREATING or state == REST or state == RETURNING)

func get_hud_info() -> Dictionary:
	return {
		"id": cat_id,
		"name": display_name,
		"state": String(state),
		"overstim": overstimulation,
		"overstim_max": overstim_threshold,
		"trust": trust,
		"trust_max": trust_max,
		"trust_state": String(trust_state),
		"ready": ready_for_adoption,
		"traits": trait_display_names.duplicate(),
		"rarity": rarity,
	}

func export_cat_def() -> Dictionary:
	var out: Dictionary = cat_def.duplicate(true)
	if not out.has("id"):
		out["id"] = cat_id
	if not out.has("display_name"):
		out["display_name"] = display_name
	if not out.has("trait_ids"):
		out["trait_ids"] = trait_ids.duplicate()
	out["trust"] = {
		"current": trust,
		"max": trust_max,
		"ready_for_adoption": ready_for_adoption,
		"state": String(trust_state),
	}
	out["overstim"] = {"current": overstimulation, "max": overstim_threshold, "actor_state": String(state)}
	return out

func set_use_viewport_rig(on: bool) -> void:
	use_viewport_rig = on and cat2d != null and cat_viewport != null and sprite != null
	if sprite != null:
		sprite.visible = use_viewport_rig
	if fallback_sprite != null:
		fallback_sprite.visible = not use_viewport_rig
	if cat_viewport != null:
		cat_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if use_viewport_rig else SubViewport.UPDATE_DISABLED
	if _pixel_pipeline != null:
		_pixel_pipeline.call("set_active", use_viewport_rig)
	if cat2d != null:
		cat2d.set_process(use_viewport_rig)

# ---------------------------------------------------------------- visuals

func _setup_rig() -> void:
	if sprite != null and cat_viewport != null and cat2d != null:
		configure_rig_rendering(pixel_art, pixel_density)
		set_use_viewport_rig(true)
	else:
		set_use_viewport_rig(false)

## Sizes the Cat2D SubViewport and the billboard so world size and feet-on-floor
## stay identical in pixel and smooth modes.
func configure_rig_rendering(pixel: bool, density: int = 56) -> void:
	pixel_art = pixel
	pixel_density = clampi(density, 32, 192)
	if sprite == null or cat_viewport == null or cat2d == null:
		return
	var n: int = pixel_density if pixel_art else RIG_SMOOTH_PX
	n += n % 2
	var foot_y: float = roundf(float(n) * RIG_FOOT_FRAC)
	cat_viewport.size = Vector2i(n, n)
	cat_viewport.msaa_2d = Viewport.MSAA_DISABLED if pixel_art else Viewport.MSAA_4X
	cat_viewport.snap_2d_transforms_to_pixel = pixel_art
	cat2d.position = Vector2(float(n / 2), foot_y)
	cat2d.scale = Vector2.ONE * (float(n) / RIG_VIEW_UNITS)
	sprite.pixel_size = RIG_WORLD_SIZE / float(n)
	sprite.offset = Vector2(0.0, foot_y - float(n) * 0.5)
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if pixel_art else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if cat2d.has_method("set_pixel_art"):
		cat2d.set_pixel_art(pixel_art)
	# Pixel mode shows the outlined composite (CatPixelPipeline), smooth mode
	# the Cat2D viewport itself.
	if pixel_art and _pixel_pipeline == null:
		_pixel_pipeline = CatPixelPipelineScript.new()
		_pixel_pipeline.set("out_update_mode", SubViewport.UPDATE_WHEN_VISIBLE)
		_pixel_pipeline.set("source_update_mode", SubViewport.UPDATE_WHEN_VISIBLE)
		_pixel_pipeline.call("setup", self, cat_viewport, cat2d)
	if _pixel_pipeline != null:
		_pixel_pipeline.call("set_pixel", pixel_art)
		_pixel_pipeline.call("set_active", use_viewport_rig)
		sprite.texture = _pixel_pipeline.call("get_texture")
	else:
		sprite.texture = cat_viewport.get_texture()

func _setup_overstim_bar() -> void:
	if bar_back == null or bar_fill == null:
		return
	var img: Image = Image.create(BAR_PX_W, BAR_PX_H, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_bar_texture = ImageTexture.create_from_image(img)
	bar_back.texture = _bar_texture
	bar_fill.texture = _bar_texture
	bar_fill.region_enabled = true
	bar_fill.region_rect = Rect2(0, 0, 0, BAR_PX_H)

func _update_facing(dir: Vector3) -> void:
	if cat2d == null or not cat2d.has_method("set_facing_left"):
		return
	var cam: Camera3D = level.get_active_camera() if level.has_method("get_active_camera") else null
	var right: Vector3 = Vector3.RIGHT
	if cam != null:
		right = cam.global_basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return
	var sx: float = dir.dot(right.normalized())
	if absf(sx) < FACING_DEADZONE:
		return
	var left: bool = sx < 0.0
	if left != _facing_left:
		_facing_left = left
		cat2d.call("set_facing_left", left)

func _update_visual_state() -> void:
	if sprite != null:
		sprite.modulate = Color.WHITE
	if fallback_sprite != null:
		fallback_sprite.modulate = Color.WHITE
	_update_rig_pose()
	_update_expression()
	_update_glyph()
	_update_bar()

func _update_rig_pose() -> void:
	if cat2d == null:
		return
	var speed: float = velocity.length() if _is_moving else 0.0
	if absf(speed - _last_move_speed) > 0.05 and cat2d.has_method("set_move_speed"):
		_last_move_speed = speed
		cat2d.call("set_move_speed", speed)
	var pose: StringName = &"idle"
	if state == REST:
		pose = &"sleep"
	elif _is_moving:
		pose = &"walk"
	elif state == INTERACTING:
		pose = &"sit"
	if pose != _last_pose and cat2d.has_method("set_pose"):
		_last_pose = pose
		cat2d.call("set_pose", pose)

func _update_glyph() -> void:
	if state_glyph == null:
		return
	var text: String = ""
	if state == REST:
		text = "Zz"
	elif state == RETREATING:
		text = "!"
	elif ready_for_adoption:
		text = "♥"
	state_glyph.visible = text != ""
	if text != "" and state_glyph.text != text:
		state_glyph.text = text

func _update_bar() -> void:
	if overstim_bar == null or bar_fill == null:
		return
	var ratio: float = clampf(overstimulation / maxf(overstim_threshold, 0.001), 0.0, 1.0)
	overstim_bar.visible = overstimulation >= BAR_HIDE_BELOW
	if not overstim_bar.visible:
		return
	var w: float = float(BAR_PX_W) * ratio
	bar_fill.region_rect = Rect2(0, 0, maxf(w, 1.0), BAR_PX_H)
	bar_fill.offset = Vector2(-(float(BAR_PX_W) - w) * 0.5, 0.0)
	var c: Color
	if ratio < 0.5:
		c = BAR_COLOR_LOW.lerp(BAR_COLOR_MID, ratio / 0.5)
	else:
		c = BAR_COLOR_MID.lerp(BAR_COLOR_HIGH, (ratio - 0.5) / 0.5)
	bar_fill.modulate = c
