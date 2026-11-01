extends "res://Scripts/minigame/MinigameBase.gd"

## "Paw & Pour: Station Kitchen" - runs one recipe inside MinigameHost's 320x180 PlayArea.
## Design: COOKING_MINIGAME_DESIGN.md (sections 2.4-2.7). API + hook points: Docs/MINIGAMES.md.
##
## context keys (only `recipe` is required):
##   recipe: Dictionary            one entry of Data/recipes.json
##   seed: int                     rolled-target seed; written back if missing so parking keeps it
##   modifier: String              "to_go" | "take_your_time" | "kid_size" | "" (see MODIFIERS)
##   archetype: String             used for the modifier when `modifier` is absent
##   patron_name: String           shown on ticket/header
##   settings: Dictionary          {leniency: 1.0|1.5|2.0, hold_to_toggle, no_clock, reduced_motion}
##   balance: Dictionary           overrides DEFAULT_BALANCE (future balance_config "cooking" block)
##   mastery_mult: float           pay mult from mastery (default 1.0)
##   allow_stand_ins: bool         missing verbs -> DebugInstantStep stand-in (default true)
##   step_override: Dictionary     tests: {script: path|Script, accuracy: float|Array, time: float|Array, delay: float}
##   skip_intro: bool              skip the ticket (tests)
##   pace: float                   multiplies ticket / hint / pop durations (tests, screenshots; default 1)
##   start_step: int               demo/screenshots: skip to step k (earlier steps = perfect at par)
##   resume: Dictionary            written by get_park_state() when an order is parked; setup()
##                                 restores finished steps + clock and continues (see get_park_state)

signal step_finished(index: int, info: Dictionary)

const PixelDraw = preload("res://Scripts/minigame/cooking/PixelDraw.gd")
const StepRegistry = preload("res://Scripts/minigame/cooking/StepRegistry.gd")
const KitchenArt = preload("res://Scripts/minigame/cooking/KitchenArt.gd")
const DEBUG_STEP_PATH := "res://Scripts/minigame/cooking/steps/DebugInstantStep.gd"

## Ticket read time: TICKET_BASE_SEC + TICKET_PER_STEP_SEC x steps (3.2 s for 4 steps, 4.4 s for 8).
## Click / Space starts sooner.
const TICKET_BASE_SEC := 2.0
const TICKET_PER_STEP_SEC := 0.3
const BURNER_DONE_SEC := 1.5
const HINT_SEC := 1.0
const POP_SEC := 0.5
const SLIDE_SEC := 0.22

const DEFAULT_BALANCE: Dictionary = {
	"grade_thresholds": {"S": 0.90, "A": 0.75, "B": 0.55},
	"grade_money_mult": {"S": 1.5, "A": 1.2, "B": 1.0, "C": 0.7},
	"grade_rep": {"S": 1.0, "A": 0.5, "B": 0.0, "C": 0.0},
	"precision_weight": 0.70,
	"speed_weight": 0.30,
	"speed_floor": 0.4,
	"speed_slope": 0.6,
	"hot_streak_step": 0.03,
	"hot_streak_cap": 0.09,
	"hot_streak_min_accuracy": 0.85,
	"trace_weight": 1.5,
	"default_par_bonus_sec": 3.0,
	"tier_window_mult": [1.0, 0.85, 0.7],
	"tier_sweep_sec": [2.4, 2.0, 1.6],
}

const MODIFIERS: Dictionary = {
	"to_go": {"label": "To go!", "par_mult": 0.85, "pay_mult": 1.2, "window_mult": 1.0, "drop_steps": 0},
	"take_your_time": {"label": "Take your time", "par_mult": 1.3, "pay_mult": 1.0, "window_mult": 1.0, "drop_steps": 0},
	"kid_size": {"label": "Kid size", "par_mult": 1.0, "pay_mult": 1.0, "window_mult": 1.25, "drop_steps": 1},
}
const ARCHETYPE_MODIFIERS: Dictionary = {
	"busy_remote_worker": "to_go",
	"gentle_reader": "take_your_time",
	"hyper_toddler": "kid_size",
}

const VERB_HINTS: Dictionary = {
	"pour": "Hold to pour - let go on the paw line!",
	"keep_zone": "Hold to rise, let go to fall. Stay in the paw zone!",
	"stop_ring": "Tap when the ring glows golden!",
	"trace": "Hold and drag along the dotted path!",
	"place": "Tap to drop it right on the marker!",
	"place_drag": "Drag it onto the marker (or arrows + Space). RMB / Bksp: undo",
	"back_burner": "It cooks while you work. Collect it when it glows! (O)",
}
const GRADE_TEXT: Dictionary = {"S": "PURR-FECT!", "A": "Great!", "B": "Yummy!", "C": "Still tasty!"}
const POP_TEXT: Array[String] = ["", "Still tasty!", "Nice!", "Purr-fect!"]

enum Phase { TICKET, HINT, ACTIVE, POP, WAIT_BURNER, SERVE, DONE }

const SLOT_RECT := Rect2(272, 4, 44, 44)
const BELL_RECT := Rect2(236, 86, 44, 40)

var recipe: Dictionary = {}
var steps: Array = []
var results: Array = []
var balance: Dictionary = {}
var modifier_id: String = ""
var modifier: Dictionary = {}
var par_sec: float = 0.0
var clock: float = 0.0
var hot_count: int = 0
var leniency: float = 1.0
var hold_to_toggle: bool = false
var no_clock: bool = false
var reduced_motion: bool = false
var play_scale: int = 1

var phase: int = Phase.TICKET
var phase_t: float = 0.0
var cur: int = -1
var seed_value: int = 0

var _step_layer: Node2D
var _burner_layer: Node2D
var _fx: Node2D
var _active: Node2D = null
var _active_index: int = -1
var _burner: Node2D = null
var _burner_index: int = -1
var _has_burner: bool = false
var _banner: Dictionary = {}
var _banner_until: float = -1.0
var _pop_stars: int = 0
var _burner_pop_t: float = -1.0
var _stand_in_types: Array[String] = []
var _scored_once: bool = false
var _time: float = 0.0
var _pace: float = 1.0
var _burner_done_t: float = -1.0
const _PHASE_NAMES: Array[String] = ["TICKET", "HINT", "ACTIVE", "POP", "WAIT_BURNER", "SERVE", "DONE"]


# --- Setup ----------------------------------------------------------------------------------

func setup(ctx: Dictionary) -> void:
	super(ctx)
	recipe = ctx.get("recipe", {}) if ctx.get("recipe", {}) is Dictionary else {}
	balance = DEFAULT_BALANCE.duplicate(true)
	var bal: Variant = ctx.get("balance", {})
	if bal is Dictionary:
		for k in (bal as Dictionary).keys():
			balance[k] = (bal as Dictionary)[k]
	var settings: Dictionary = ctx.get("settings", {}) if ctx.get("settings", {}) is Dictionary else {}
	leniency = float(settings.get("leniency", 1.0))
	hold_to_toggle = bool(settings.get("hold_to_toggle", false))
	no_clock = bool(settings.get("no_clock", false))
	reduced_motion = bool(settings.get("reduced_motion", false))
	play_scale = int(ctx.get("_play_scale", 1))
	modifier_id = String(ctx.get("modifier", ARCHETYPE_MODIFIERS.get(String(ctx.get("archetype", "")), "")))
	modifier = MODIFIERS.get(modifier_id, {})
	if not ctx.has("seed"):
		ctx["seed"] = randi()
	seed_value = int(ctx["seed"])
	_pace = clampf(float(ctx.get("pace", 1.0)), 0.01, 4.0)

	if recipe.is_empty() or not (recipe.get("steps", []) is Array) or (recipe.get("steps", []) as Array).is_empty():
		push_error("CookingGame: context.recipe is missing or has no steps")
		_banner = {"visible": true, "title": "Oops", "text": "No recipe on this ticket."}
		phase = Phase.DONE
		return

	steps = build_step_list(recipe, modifier)
	results.resize(steps.size())
	results.fill(null)
	par_sec = compute_par(steps, float(recipe.get("par_bonus_sec", balance["default_par_bonus_sec"])), float(modifier.get("par_mult", 1.0)))
	for s in steps:
		if StepRegistry.is_parallel(String((s as Dictionary).get("type", ""))):
			_has_burner = true

	_step_layer = Node2D.new()
	_step_layer.name = "StepLayer"
	add_child(_step_layer)
	_burner_layer = Node2D.new()
	_burner_layer.name = "BurnerLayer"
	add_child(_burner_layer)
	_fx = Node2D.new()
	_fx.name = "FX"
	add_child(_fx)
	_fx.draw.connect(_draw_fx)
	if not PixelDraw.legacy():
		apply_art_style()

	var start_step: int = clampi(int(ctx.get("start_step", 0)), 0, steps.size())
	var resume: Variant = ctx.get("resume", null)
	if resume is Dictionary and _apply_resume(resume as Dictionary):
		pass
	elif start_step > 0:
		# Demo / screenshot jump: earlier steps count as perfect at par (no extras).
		for j in range(start_step):
			_record_result(j, 1.0, float((steps[j] as Dictionary).get("par_sec", 3.0)), {})
		_begin_step(start_step)
	elif bool(ctx.get("skip_intro", false)):
		_begin_step(0)
	else:
		_set_phase(Phase.TICKET)
	queue_redraw()


## Applies the modifier's step drop (Kid size): removes the first `kid_skip` step, else the last
## non-parallel step; never below 2 steps.
static func build_step_list(p_recipe: Dictionary, p_modifier: Dictionary) -> Array:
	var out: Array = []
	for s in p_recipe.get("steps", []):
		if s is Dictionary:
			out.append((s as Dictionary).duplicate(true))
	var drops: int = int(p_modifier.get("drop_steps", 0))
	while drops > 0 and out.size() > 2:
		var idx: int = -1
		for i in range(out.size()):
			if bool((out[i] as Dictionary).get("kid_skip", false)):
				idx = i
				break
		if idx < 0:
			for i in range(out.size() - 1, -1, -1):
				if not StepRegistry.is_parallel(String((out[i] as Dictionary).get("type", ""))):
					idx = i
					break
		if idx < 0:
			break
		out.remove_at(idx)
		drops -= 1
	return out


## Par = (sum of step pars + par bonus) x modifier par mult.
static func compute_par(p_steps: Array, par_bonus_sec: float, par_mult: float) -> float:
	var total: float = par_bonus_sec
	for s in p_steps:
		total += float((s as Dictionary).get("par_sec", 3.0))
	return total * par_mult


static func hot_bonus_for(count: int, p_balance: Dictionary = DEFAULT_BALANCE) -> float:
	return minf(float(count) * float(p_balance.get("hot_streak_step", 0.03)), float(p_balance.get("hot_streak_cap", 0.09)))


static func step_weight(step_result: Dictionary, p_balance: Dictionary = DEFAULT_BALANCE) -> float:
	if step_result.has("weight"):
		return float(step_result["weight"])
	return float(p_balance.get("trace_weight", 1.5)) if String(step_result.get("type", "")) == "trace" else 1.0


## Score math (design 2.7). step_results: [{type, accuracy, weight?}].
## Returns {precision, speed, score, grade}.
static func compute_score(step_results: Array, time_sec: float, p_par_sec: float, hot_bonus: float, p_balance: Dictionary = DEFAULT_BALANCE, p_no_clock: bool = false) -> Dictionary:
	var wsum: float = 0.0
	var asum: float = 0.0
	for r in step_results:
		var d: Dictionary = r
		var w: float = step_weight(d, p_balance)
		wsum += w
		asum += w * clampf(float(d.get("accuracy", 0.0)), 0.0, 1.0)
	var precision: float = asum / wsum if wsum > 0.0 else 0.0
	var speed: float = 1.0
	if not p_no_clock and p_par_sec > 0.0 and time_sec > p_par_sec:
		speed = clampf(1.0 - float(p_balance.get("speed_slope", 0.6)) * (time_sec - p_par_sec) / p_par_sec, float(p_balance.get("speed_floor", 0.4)), 1.0)
	var score: float = clampf(float(p_balance.get("precision_weight", 0.7)) * precision + float(p_balance.get("speed_weight", 0.3)) * speed + hot_bonus, 0.0, 1.0)
	var thresholds: Variant = p_balance.get("grade_thresholds", DEFAULT_THRESHOLDS)
	return {"precision": precision, "speed": speed, "score": score, "grade": grade_for(score, thresholds if thresholds is Dictionary else DEFAULT_THRESHOLDS)}


## money = round(base_price x grade_mult x modifier_mult x mastery_mult)
static func compute_money(base_price: float, grade: String, pay_mult: float = 1.0, mastery_mult: float = 1.0, p_balance: Dictionary = DEFAULT_BALANCE) -> int:
	var gm: Dictionary = p_balance.get("grade_money_mult", DEFAULT_BALANCE["grade_money_mult"])
	return int(roundf(base_price * float(gm.get(grade, 1.0)) * pay_mult * mastery_mult))


static func stars_for(accuracy: float) -> int:
	if accuracy >= 0.9:
		return 3
	if accuracy >= 0.65:
		return 2
	return 1


# --- Public controls (also used by tests / integration) -----------------------------------

## Rings the serve bell if the dish is ready. Returns true when it served.
func press_serve() -> bool:
	if phase != Phase.SERVE:
		return false
	_serve()
	return true


func skip_intro() -> void:
	if phase == Phase.TICKET:
		_begin_step(0)
	elif phase == Phase.HINT:
		_end_hint()


func is_ready_to_serve() -> bool:
	return phase == Phase.SERVE


func can_park() -> bool:
	return phase != Phase.DONE


## Parking keeps the seed AND the finished work: every finished step from the start up to the
## first unfinished one (a back-burner pot that was still simmering restarts, and steps after it
## are redone), plus the clock and hot streak. A dish waiting at the Serve bell comes back ready to
## serve. The host merges this into the context; setup() reads context.resume.
func get_park_state() -> Dictionary:
	var done: Array = []
	for i in range(results.size()):
		if results[i] == null:
			break
		done.append((results[i] as Dictionary).duplicate(true))
	var st: Dictionary = {"seed": seed_value}
	if not done.is_empty():
		var hot: int = 0
		for d in done:
			if bool((d as Dictionary).get("hot", false)):
				hot += 1
		st["resume"] = {"results": done, "clock": clock, "hot_count": hot, "recipe_id": String(recipe.get("id", ""))}
	return st


## Number of finished steps a parked context will resume with (0 = starts from the ticket).
static func resume_step_count(ctx: Dictionary) -> int:
	var r: Variant = ctx.get("resume", null)
	if r is Dictionary and (r as Dictionary).get("results", []) is Array:
		return ((r as Dictionary)["results"] as Array).size()
	return 0


func _apply_resume(r: Dictionary) -> bool:
	if String(r.get("recipe_id", recipe.get("id", ""))) != String(recipe.get("id", "")):
		return false
	var done: Array = r.get("results", []) if r.get("results", []) is Array else []
	if done.is_empty() or done.size() > steps.size():
		return false
	for i in range(done.size()):
		if not (done[i] is Dictionary):
			return false
		results[i] = (done[i] as Dictionary).duplicate(true)
	clock = float(r.get("clock", 0.0))
	hot_count = int(r.get("hot_count", 0))
	_begin_step(done.size())
	return true


# --- Step runner ----------------------------------------------------------------------------

func _set_phase(p: int) -> void:
	phase = p
	phase_t = 0.0
	if _fx != null:
		_fx.queue_redraw()
	queue_redraw()


func _begin_step(i: int) -> void:
	cur = i
	if i >= steps.size():
		if _burner != null and results[_burner_index] == null:
			_set_phase(Phase.WAIT_BURNER)
			_banner = {"visible": true, "title": "ALMOST!", "text": "Collect the back burner - click its ring or press O", "style": "hint"}
			_banner_until = -1.0
		else:
			_enter_serve()
		return
	var step: Dictionary = steps[i]
	var type: String = String(step.get("type", ""))
	var node: Node2D = _make_step_node(type, i)
	if node == null:
		push_error("CookingGame: could not create step %d (%s); skipping it as 'still tasty'" % [i, type])
		_record_result(i, 0.4, 0.0, {})
		_begin_step(i + 1)
		return
	var parallel: bool = StepRegistry.is_parallel(type) and _burner == null
	var p: Dictionary = _params_for(i)
	node.set("hold_to_toggle", hold_to_toggle)
	node.name = "Step%d_%s" % [i, type]
	if parallel:
		_burner = node
		_burner_index = i
		_burner_layer.add_child(node)
	else:
		_active = node
		_active_index = i
		_step_layer.add_child(node)
		_step_layer.position = Vector2.ZERO if reduced_motion else Vector2(56, 0)
		if not reduced_motion:
			var tw: Tween = create_tween()
			tw.tween_property(_step_layer, "position", Vector2.ZERO, SLIDE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	node.connect("done", _on_step_done.bind(i))
	# Frozen during the 1 s verb hint (visible but not running).
	node.process_mode = Node.PROCESS_MODE_DISABLED
	var step_rng := RandomNumberGenerator.new()
	step_rng.seed = hash([seed_value, i, "verb"])
	node.call("start", p, leniency, step_rng)
	var hint: String = hint_for(step)
	var title: String = "STEP %d/%d  %s" % [i + 1, steps.size(), String(step.get("label", type)).to_upper()]
	if parallel:
		title = "BACK BURNER: %s" % String(step.get("label", type))
	_banner = {"visible": true, "title": title, "text": hint, "style": "hint"}
	_banner_until = -1.0
	_set_phase(Phase.HINT)


## Footer / banner hint for a step: its own `hint`, else the verb's (drag-mode PLACE has its own).
static func hint_for(step: Dictionary) -> String:
	if step.has("hint"):
		return String(step["hint"])
	var type: String = String(step.get("type", ""))
	var p: Variant = step.get("params", {})
	if type == "place" and p is Dictionary and String((p as Dictionary).get("mode", "swing")) == "drag":
		return String(VERB_HINTS["place_drag"])
	return String(VERB_HINTS.get(type, ""))


func ticket_sec() -> float:
	return TICKET_BASE_SEC + TICKET_PER_STEP_SEC * float(steps.size())


func _end_hint() -> void:
	var step_node: Node2D = _burner if cur == _burner_index else _active
	if step_node != null and is_instance_valid(step_node):
		step_node.process_mode = Node.PROCESS_MODE_INHERIT
	_banner = {}
	if cur == _burner_index:
		# Parallel step: it keeps running in the burner slot; move on right away.
		_begin_step(cur + 1)
	else:
		_set_phase(Phase.ACTIVE)


func _make_step_node(type: String, _i: int) -> Node2D:
	var ov: Variant = context.get("step_override", null)
	if ov is Dictionary and (ov as Dictionary).has("script"):
		return StepRegistry.create_step(type, (ov as Dictionary)["script"])
	if StepRegistry.has_verb(type):
		return StepRegistry.create_step(type)
	if bool(context.get("allow_stand_ins", true)):
		if not _stand_in_types.has(type):
			_stand_in_types.append(type)
			print("CookingGame: verb '%s' is not built yet - using the stand-in card" % type)
		return StepRegistry.create_step(type, DEBUG_STEP_PATH)
	return StepRegistry.create_step(type)


func _params_for(i: int) -> Dictionary:
	var step: Dictionary = steps[i]
	var type: String = String(step.get("type", ""))
	var p: Dictionary = (step.get("params", {}) as Dictionary).duplicate(true) if step.get("params", {}) is Dictionary else {}
	var tier: int = clampi(int(recipe.get("tier", 1)), 1, 3)
	var twm: Array = balance.get("tier_window_mult", [1.0, 0.85, 0.7])
	var tss: Array = balance.get("tier_sweep_sec", [2.4, 2.0, 1.6])
	p["_type"] = type
	p["_label"] = String(step.get("label", type))
	p["_index"] = i
	p["_tier"] = tier
	p["_window_mult"] = float(twm[mini(tier - 1, twm.size() - 1)]) * float(modifier.get("window_mult", 1.0))
	p["_sweep_sec"] = float(tss[mini(tier - 1, tss.size() - 1)])
	p["_roll"] = roll_targets(type, p, seed_value, i)
	var prev: Array = []
	for j in range(i):
		if results[j] != null:
			prev.append(results[j])
	p["_prev"] = prev
	p["_play_scale"] = play_scale
	p["_reduced_motion"] = reduced_motion
	p["_slot_rect"] = SLOT_RECT
	p["_safe_rect"] = Rect2(8, 8, 256, 164) if _has_burner else Rect2(8, 8, 304, 164)
	var ov: Variant = context.get("step_override", null)
	if ov is Dictionary:
		var od: Dictionary = ov
		if od.has("accuracy"):
			p["debug_accuracy"] = _pick(od["accuracy"], i, 1.0)
		if od.has("time"):
			p["debug_time"] = _pick(od["time"], i, -1.0)
		if od.has("delay"):
			p["debug_delay"] = _pick(od["delay"], i, 0.0)
	return p


static func _pick(v: Variant, i: int, fallback: float) -> float:
	if v is Array:
		var a: Array = v
		return float(a[i]) if i < a.size() else fallback
	return float(v)


## Seeded per-step target rolls (design 2.5 "Variety"). Deterministic for (seed, index).
static func roll_targets(type: String, p: Dictionary, p_seed: int, index: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash([p_seed, index, type, "roll"])
	var out: Dictionary = {}
	match type:
		"pour":
			var tr: Array = p.get("target_range", [0.55, 0.85])
			out["target"] = r.randf_range(float(tr[0]), float(tr[1]))
		"keep_zone":
			if p.has("zone_range"):
				var zr: Array = p["zone_range"]
				out["zone_center"] = r.randf_range(float(zr[0]), float(zr[1]))
			else:
				out["zone_center"] = float(p.get("zone_center", 0.6))
		"stop_ring":
			out["sweep_mult"] = r.randf_range(0.9, 1.1)
		"trace":
			var pool: Array = p.get("path_pool", ["paw"])
			out["shape"] = String(pool[r.randi() % maxi(pool.size(), 1)]) if not pool.is_empty() else "paw"
		"place":
			out["target_x"] = r.randf_range(-0.15, 0.15)
		"back_burner":
			if p.has("cook_sec"):
				out["cook_sec"] = float(p["cook_sec"])
			else:
				var cr: Array = p.get("cook_range", [6.0, 12.0])
				out["cook_sec"] = r.randf_range(float(cr[0]), float(cr[1]))
	return out


func _on_step_done(accuracy: float, time_sec: float, index: int) -> void:
	if index < 0 or index >= results.size() or results[index] != null:
		return
	var node: Node2D = _burner if index == _burner_index else _active
	var ex: Dictionary = {}
	if node != null and is_instance_valid(node):
		var e: Variant = node.get("extra")
		if e is Dictionary:
			ex = (e as Dictionary).duplicate(true)
	_record_result(index, accuracy, time_sec, ex)
	if index == _burner_index:
		_burner_pop_t = 0.0
		_burner_done_t = 0.0
		queue_redraw()
		if node != null and is_instance_valid(node):
			node.queue_free()
		_burner = null
		if phase == Phase.WAIT_BURNER:
			_banner = {}
			_enter_serve()
		return
	_pop_stars = stars_for(accuracy)
	_banner = {"visible": true, "title": POP_TEXT[_pop_stars], "text": "", "style": "pop", "stars": _pop_stars}
	_set_phase(Phase.POP)


func _record_result(index: int, accuracy: float, time_sec: float, ex: Dictionary) -> void:
	var step: Dictionary = steps[index]
	var info: Dictionary = {
		"type": String(step.get("type", "")),
		"label": String(step.get("label", "")),
		"accuracy": clampf(accuracy, 0.0, 1.0),
		"time": maxf(time_sec, 0.0),
		"par_sec": float(step.get("par_sec", 3.0)),
		"weight": float(step.get("weight", 1.5 if String(step.get("type", "")) == "trace" else 1.0)),
		"stars": stars_for(accuracy),
		"extra": ex,
	}
	var step_par: float = info["par_sec"] * float(modifier.get("par_mult", 1.0))
	info["hot"] = info["time"] <= step_par and info["accuracy"] >= float(balance.get("hot_streak_min_accuracy", 0.85))
	if info["hot"]:
		hot_count += 1
	results[index] = info
	step_finished.emit(index, info)


func _enter_serve() -> void:
	_banner = {"visible": true, "title": "ORDER UP!", "text": "Ring the bell to serve  (click / Enter)", "style": "hint"}
	_banner_until = -1.0
	_set_phase(Phase.SERVE)


func _serve() -> void:
	if _scored_once:
		return
	_scored_once = true
	var result: Dictionary = build_result()
	_banner = {}
	_set_phase(Phase.DONE)
	scored.emit(result)


func build_result() -> Dictionary:
	var step_list: Array = []
	for r in results:
		if r != null:
			var d: Dictionary = (r as Dictionary).duplicate(true)
			step_list.append(d)
	var hb: float = hot_bonus_for(hot_count, balance)
	var sc: Dictionary = compute_score(step_list, clock, par_sec, hb, balance, no_clock)
	var grade: String = String(sc["grade"])
	var pay_mult: float = float(modifier.get("pay_mult", 1.0))
	var mastery: float = float(context.get("mastery_mult", 1.0))
	var money: int = compute_money(float(recipe.get("base_price", 0)), grade, pay_mult, mastery, balance)
	var rep_table: Dictionary = balance.get("grade_rep", DEFAULT_BALANCE["grade_rep"])
	return {
		"kind": "cooking",
		"recipe_id": String(recipe.get("id", "")),
		"display_name": String(recipe.get("display_name", "")),
		"grade": grade,
		"grade_text": String(GRADE_TEXT.get(grade, "")),
		"score": float(sc["score"]),
		"precision": float(sc["precision"]),
		"speed": float(sc["speed"]),
		"steps": step_list,
		"time_sec": clock,
		"par_sec": par_sec,
		"no_clock": no_clock,
		"hot_streak": hot_count,
		"hot_streak_bonus": hb,
		"money": money,
		"rep": float(rep_table.get(grade, 0.0)),
		"base_price": float(recipe.get("base_price", 0)),
		"modifier": modifier_id,
		"modifier_label": String(modifier.get("label", "")),
		"pay_mult": pay_mult,
		"seed": seed_value,
		"effects": recipe.get("effects", {}),
		"dish": recipe.get("dish", {}),
	}


# --- Frame loop -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	phase_t += delta
	if _burner_pop_t >= 0.0:
		_burner_pop_t += delta
		if _burner_pop_t > 0.6:
			_burner_pop_t = -1.0
	if _burner_done_t >= 0.0:
		_burner_done_t += delta
		if _burner_done_t > BURNER_DONE_SEC or phase == Phase.SERVE or phase == Phase.DONE:
			_burner_done_t = -1.0
	match phase:
		Phase.TICKET:
			if phase_t >= ticket_sec() * _pace:
				_begin_step(0)
		Phase.HINT:
			if phase_t >= HINT_SEC * _pace:
				_end_hint()
		Phase.ACTIVE:
			clock += delta
		Phase.WAIT_BURNER:
			clock += delta
		Phase.POP:
			if phase_t >= POP_SEC * _pace:
				if _active != null and is_instance_valid(_active):
					_active.queue_free()
				_active = null
				_banner = {}
				_begin_step(cur + 1)
	if _banner_until >= 0.0 and _time >= _banner_until:
		_banner = {}
		_banner_until = -1.0
	if _fx != null:
		_fx.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var primary: bool = false
	var enter: bool = false
	var click_pos := Vector2(-1, -1)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			primary = true
			click_pos = mb.position
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_SPACE:
			primary = true
		elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			enter = true
		elif k.keycode == KEY_F1:
			_reshow_hint()
			get_viewport().set_input_as_handled()
			return
	if not primary and not enter:
		return
	match phase:
		Phase.TICKET:
			skip_intro()
			get_viewport().set_input_as_handled()
		Phase.HINT:
			if primary:
				_end_hint()
				get_viewport().set_input_as_handled()
		Phase.SERVE:
			if enter or (primary and click_pos.x < 0.0) or BELL_RECT.grow(4).has_point(click_pos) or Rect2(110, 60, 110, 90).has_point(click_pos):
				_serve()
				get_viewport().set_input_as_handled()


func _reshow_hint() -> void:
	if phase != Phase.ACTIVE or cur < 0 or cur >= steps.size():
		return
	var step: Dictionary = steps[cur]
	_banner = {"visible": true, "title": String(step.get("label", "")).to_upper(), "text": hint_for(step), "style": "hint"}
	_banner_until = _time + 1.5


# --- HUD info for MinigameHost ----------------------------------------------------------

func get_hud_info() -> Dictionary:
	var stations: Array = []
	for i in range(steps.size()):
		var s: Dictionary = steps[i]
		var state: String = "todo"
		var stars: int = 0
		if results[i] != null:
			state = "done"
			stars = int((results[i] as Dictionary)["stars"])
		elif i == _burner_index and _burner != null:
			state = "burner"
		elif i == cur and (phase == Phase.HINT or phase == Phase.ACTIVE or phase == Phase.POP):
			state = "active"
		stations.append({"label": String(s.get("label", "")), "type": String(s.get("type", "")), "state": state, "stars": stars})
	var burner: Dictionary = {"visible": _has_burner}
	if _burner != null and is_instance_valid(_burner):
		var info: Variant = _burner.call("get_burner_info") if _burner.has_method("get_burner_info") else null
		if info is Dictionary:
			burner.merge(info as Dictionary, true)
		else:
			burner["state"] = "cooking"
			burner["progress"] = clampf(float(_burner.get("elapsed")) / maxf(float((_burner.get("params") as Dictionary).get("_roll", {}).get("cook_sec", 8.0)), 0.1), 0.0, 1.0)
		burner["label"] = String((steps[_burner_index] as Dictionary).get("label", "Burner"))
	elif _burner_index >= 0 and results[_burner_index] != null:
		burner["state"] = "done"
		burner["progress"] = 1.0
		burner["stars"] = int((results[_burner_index] as Dictionary)["stars"])
	else:
		burner["state"] = "idle"
		burner["progress"] = 0.0
	var subtitle: String = ""
	var patron: String = String(context.get("patron_name", ""))
	if patron != "":
		subtitle = "for: %s" % patron
	if not modifier.is_empty():
		var mod_txt: String = "\"%s\"" % String(modifier.get("label", ""))
		if float(modifier.get("pay_mult", 1.0)) > 1.0:
			mod_txt += " (+%d%%)" % int(roundf((float(modifier["pay_mult"]) - 1.0) * 100.0))
		subtitle = (subtitle + "  " + mod_txt).strip_edges()
	var hint: String = ""
	if phase == Phase.ACTIVE and cur >= 0 and cur < steps.size():
		hint = hint_for(steps[cur] as Dictionary)
	elif phase == Phase.SERVE:
		hint = "Ring the bell: click it or press Enter"
	elif phase == Phase.TICKET:
		hint = "Read the ticket - it starts by itself, or click / Space to start now"
	elif phase == Phase.WAIT_BURNER:
		hint = "Click the burner ring or press O"
	return {
		"title": String(recipe.get("display_name", "Kitchen")),
		"subtitle": subtitle,
		"par_sec": par_sec,
		"elapsed_sec": clock,
		"show_clock": not no_clock,
		"hot_streak": hot_count,
		"burner": burner,
		"stations": stations,
		"hint": hint,
		"banner": _banner,
		"phase": _PHASE_NAMES[phase],
	}


# --- Art style (A..F) -------------------------------------------------------------------------

var _fx_group: CanvasGroup = null


## Re-wire for the current PixelDraw style (live switch from the Test Kitchen panel). E / F: the
## step / burner / ticket+dish layers move into one FX CanvasGroup that adds the cream sticker halo
## or the cocoa drop shadow around every object (the wall + counter background stays outside).
## A..D: the original node layout. Redraws everything.
func apply_art_style() -> void:
	if _step_layer == null:
		return
	var layers: Array = [_step_layer, _burner_layer, _fx]
	if PixelDraw.fx_active():
		if _fx_group == null:
			_fx_group = PixelDraw.make_fx_group("FXObjects")
			add_child(_fx_group)
		_fx_group.material = PixelDraw.fx_material()
		for n in layers:
			var nd: Node = n
			if nd.get_parent() != _fx_group:
				nd.get_parent().remove_child(nd)
				_fx_group.add_child(nd)
	else:
		for n in layers:
			var nd2: Node = n
			if nd2.get_parent() != self:
				nd2.get_parent().remove_child(nd2)
				add_child(nd2)
		if _fx_group != null:
			_fx_group.queue_free()
			_fx_group = null
	_redraw_tree(self)


func _redraw_tree(n: Node) -> void:
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()
	for c in n.get_children():
		_redraw_tree(c)


# --- Drawing ---------------------------------------------------------------------------------

func _draw() -> void:
	# Wall
	draw_rect(Rect2(0, 0, 320, 124), PixelDraw.WALL, true)
	for y in range(6, 118, 16):
		for x in range(6 + (8 if (y >> 4) % 2 == 1 else 0), 320, 16):
			draw_rect(Rect2(x, y, 2, 2), PixelDraw.CREAM_DARK, true)
	# Shelf with jars
	draw_rect(Rect2(12, 40, 64, 3), PixelDraw.OAK_DARK, true)
	PixelDraw.rounded_rect(self, Rect2(16, 28, 10, 12), 2, PixelDraw.SAGE)
	PixelDraw.rounded_rect(self, Rect2(30, 30, 10, 10), 2, PixelDraw.HONEY_LIGHT)
	PixelDraw.rounded_rect(self, Rect2(44, 26, 12, 14), 2, PixelDraw.BLUSH)
	# Counter
	draw_rect(Rect2(0, 124, 320, 6), PixelDraw.OAK, true)
	PixelDraw.px(self, Rect2(0, 124, 320, 1), PixelDraw.OUTLINE)
	draw_rect(Rect2(0, 130, 320, 50), PixelDraw.OAK_DARK, true)
	PixelDraw.px(self, Rect2(0, 130, 320, 1), PixelDraw.OUTLINE)
	for x in range(0, 320, 40):
		draw_rect(Rect2(x, 131, 1, 49), Color(PixelDraw.OUTLINE, 0.35), true)
	# Burner slot frame only while a pot is on it (an empty frame read as a missing sprite).
	if _burner != null and is_instance_valid(_burner):
		PixelDraw.rounded_rect(self, SLOT_RECT.grow(2), 4, PixelDraw.CREAM_DARK, PixelDraw.OAK_DARK)


func _draw_fx() -> void:
	match phase:
		Phase.TICKET:
			_draw_ticket()
		Phase.SERVE, Phase.DONE:
			_draw_dish(Vector2(165, 128))
			if phase == Phase.SERVE:
				_draw_bell()
		Phase.POP:
			var c := Vector2(160, 80)
			var t: float = clampf(phase_t / (POP_SEC * _pace), 0.0, 1.0)
			for k in range(6):
				var ang: float = float(k) * TAU / 6.0 + 0.4
				var rr: float = 28.0 + t * (0.0 if reduced_motion else 18.0)
				PixelDraw.sparkle(_fx, c + Vector2(cos(ang), sin(ang)) * rr, 2, PixelDraw.HONEY)
			for s in range(3):
				var filled: bool = s < _pop_stars
				PixelDraw.star(_fx, c + Vector2(-16 + s * 16, 0), 6, PixelDraw.HONEY if filled else PixelDraw.CREAM_DARK)
	if _burner_done_t >= 0.0:
		# Collected: a little sage "done" plate with a tick, then the slot hides.
		var dc: Vector2 = SLOT_RECT.get_center()
		PixelDraw.circle(_fx, dc, 8, PixelDraw.SAGE)
		PixelDraw.line(_fx, dc + Vector2(-4, 0), dc + Vector2(-1, 3), PixelDraw.OUTLINE, 1.0)
		PixelDraw.line(_fx, dc + Vector2(-1, 3), dc + Vector2(4, -3), PixelDraw.OUTLINE, 1.0)
	if _burner_pop_t >= 0.0:
		var sc: Vector2 = SLOT_RECT.get_center()
		for k in range(4):
			var ang2: float = float(k) * TAU / 4.0
			PixelDraw.sparkle(_fx, sc + Vector2(cos(ang2), sin(ang2)) * (14.0 + _burner_pop_t * 12.0), 1, PixelDraw.HONEY)


func _draw_ticket() -> void:
	var lift: float = 0.0 if reduced_motion else roundf((1.0 - clampf(phase_t / 0.25, 0.0, 1.0)) * 20.0)
	var r := Rect2(92, 14 + lift, 136, 136)
	if not PixelDraw.legacy():
		r = Rect2(78, 14 + lift, 164, 136)
	PixelDraw.shadow(_fx, Vector2(r.get_center().x, r.end.y + 3), 64, 3)
	PixelDraw.outlined_rect(_fx, r, PixelDraw.CREAM)
	# zigzag tear at the bottom
	for x in range(int(r.position.x) + 1, int(r.end.x) - 1, 6):
		_fx.draw_rect(Rect2(x, r.end.y - 3, 3, 3), PixelDraw.CREAM_DARK, true)
	_fx.draw_rect(Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, 14), PixelDraw.HONEY_LIGHT, true)
	PixelDraw.text(_fx, r.position + Vector2(6, 11), String(recipe.get("display_name", "")), PixelDraw.OUTLINE, 8)
	var y: float = r.position.y + 28
	var row_h: float = minf(11.0, 88.0 / float(maxi(steps.size(), 1)))
	for i in range(steps.size()):
		var s: Dictionary = steps[i]
		var lab: String = "%d. %s" % [i + 1, String(s.get("label", ""))]
		if StepRegistry.is_parallel(String(s.get("type", ""))):
			lab += " ~"
		KitchenArt.verb_icon(_fx, Vector2(r.position.x + 5, roundf(y) - 8), String(s.get("type", "")))
		PixelDraw.text(_fx, Vector2(r.position.x + 20, roundf(y)), lab, PixelDraw.OUTLINE, 8)
		y += row_h
	PixelDraw.text(_fx, Vector2(r.position.x + 8, y + 2), "-> Serve!", PixelDraw.SAGE_DARK, 8)
	var foot: String = "par %s" % _fmt_time(par_sec) if not no_clock else "no clock"
	if not modifier.is_empty():
		foot += "  " + String(modifier.get("label", ""))
	PixelDraw.text(_fx, Vector2(r.position.x + 8, r.end.y - 8), foot, PixelDraw.OAK_DARK, 8)
	PixelDraw.paw(_fx, Vector2(r.end.x - 12, r.position.y + 8), 4, PixelDraw.OAK_DARK)
	# "Space>" chip: pulses; the sage line under it drains as the auto-start time runs out.
	var chip := Rect2(r.end.x - 46, r.end.y - 19, 40, 12)
	var pulse: bool = reduced_motion or fmod(_time, 0.8) < 0.5
	PixelDraw.rounded_rect(_fx, chip, 2, PixelDraw.HONEY_LIGHT if pulse else PixelDraw.CREAM, PixelDraw.OUTLINE)
	var left: float = 1.0 - clampf(phase_t / maxf(ticket_sec() * _pace, 0.01), 0.0, 1.0)
	PixelDraw.px(_fx, Rect2(chip.position.x + 2, chip.end.y - 2, roundf((chip.size.x - 4) * left), 1), PixelDraw.SAGE_DARK)
	PixelDraw.text(_fx, chip.position + Vector2(4, 9), "Space>", PixelDraw.OUTLINE, 8)


func _quality() -> float:
	var list: Array = []
	for r in results:
		if r != null:
			list.append(r)
	if list.is_empty():
		return 0.0
	return float(compute_score(list, 0.0, 1.0, 0.0, balance, true)["precision"])


## Finished dish (KitchenArt sprite, great/homely look from precision, player's latte art).
func _draw_dish(bottom: Vector2) -> void:
	var list: Array = []
	for r in results:
		if r != null:
			list.append(r)
	var info: Dictionary = KitchenArt.dish_info(list, _quality())
	info["t"] = _time
	info["reduced"] = reduced_motion
	var dish_def: Dictionary = recipe.get("dish", {}) if recipe.get("dish", {}) is Dictionary else {}
	KitchenArt.dish(_fx, bottom, String(recipe.get("id", "")), dish_def, info)


func _draw_bell() -> void:
	var b: Rect2 = BELL_RECT
	var bob: float = 0.0 if reduced_motion else roundf(sin(_time * 5.0))
	var base := Rect2(b.position.x + 4, b.end.y - 6, b.size.x - 8, 6)
	PixelDraw.shadow(_fx, Vector2(b.get_center().x, b.end.y + 1), 20, 2)
	var dome_c := Vector2(b.get_center().x, b.end.y - 6)
	# half dome: 1px rows above the base line only (B..F: outer ink rows grown by outline_px - 1)
	var g: int = 0 if PixelDraw.legacy() else PixelDraw.ow() - 1
	var ro: float = 15.0 + float(g)
	for row in range(1, 16 + g):
		var hw_o: float = roundf(sqrt(maxf(ro * ro - float(row * row), 0.0)))
		_fx.draw_rect(Rect2(dome_c.x - hw_o, dome_c.y - row, hw_o * 2.0, 1), PixelDraw.OUTLINE, true)
		if row < 15:
			var hw_i: float = roundf(sqrt(maxf(14.0 * 14.0 - float(row * row), 0.0))) - 1.0
			if hw_i > 0.0:
				_fx.draw_rect(Rect2(dome_c.x - hw_i, dome_c.y - row, hw_i * 2.0, 1), PixelDraw.HONEY, true)
	PixelDraw.hl(_fx, Rect2(dome_c.x - 7, dome_c.y - 10, 3, 4), PixelDraw.HONEY_LIGHT)
	PixelDraw.outlined_rect(_fx, base, PixelDraw.OAK)
	PixelDraw.outlined_rect(_fx, Rect2(dome_c.x - 2, dome_c.y - 19 + bob, 4, 4), PixelDraw.HONEY)
	# B..F: lifted by the extra outline width (+ the text ring) so the label clears the dome knob.
	var lift: float = 0.0 if PixelDraw.legacy() else float(g + int(PixelDraw.S["text_ring"]))
	PixelDraw.text(_fx, Vector2(b.position.x + 4, dome_c.y - 23 + bob - lift), "SERVE", PixelDraw.OUTLINE, 8)


static func _fmt_time(sec: float) -> String:
	var s: int = int(ceilf(maxf(sec, 0.0)))
	return "%d:%02d" % [int(s / 60.0), s % 60]
