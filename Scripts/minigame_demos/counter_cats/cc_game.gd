extends Node2D

## Counter Cats: Whisker Kitchen - the 2D play area (320x180, nearest filter).
## Mirrors the shared MinigameBase contract (setup(ctx), get_hud_info(), signal
## scored(result), signal request_park) without depending on it, so it can move
## onto the shared MinigameHost later.
##
## Loop: intro -> [transition -> step -> flourish] x N -> serve -> done.
## Cat events are decided at transition slots, telegraphed for exactly the 1.0 s
## transition (no judged input happens then), and arrive when the next step starts.

signal scored(result: Dictionary)
signal request_park
signal popup(pos: Vector2, text: String, color: Color)

const Art := preload("res://Scripts/minigame_demos/counter_cats/cc_art.gd")
const R := preload("res://Scripts/minigame_demos/counter_cats/cc_recipes.gd")
const CounterCatScript := preload("res://Scripts/minigame_demos/counter_cats/cc_counter_cat.gd")
const BgStyled := preload("res://Scripts/minigame_demos/counter_cats/cc_bg_styled.gd")

const PLAY_SIZE := Vector2(320, 180)
const WX: float = 150.0          # work spot
const CY: float = 118.0          # counter surface (item / cat feet line)
const TX: float = 232.0          # ingredient tray
const HOME_X: float = 289.0      # cat cushion
const SILL := Vector2(254, 59)   # second cat's window-sill perch
const MX: float = 98.0           # pour meter left
const METER_TOP: float = 40.0
const METER_H: float = 72.0
const BIN := Rect2(287, 132, 28, 18)
const PIVOT := Vector2(WX, 12)
const ROPE: float = 30.0
const SWING_A: float = 30.0
const TELEGRAPH_SEC: float = 1.0
const TRANSITION_SEC: float = 0.8
const FLOURISH_SEC: float = 0.7
const INTRO_SEC: float = 0.9
const LOAF_SEC: float = 5.0
const ASSIST_SEC: float = 6.0
const SNIFF_SEC: float = 2.0
const BAT_SLIDE_SEC: float = 1.4
const BIN_REGRAB_SEC: float = 1.3
const MIN_EVENT_START: float = 4.0
const MIN_EVENT_GAP: float = 5.0

# ---- config / context
var context: Dictionary = {}
var recipe: Dictionary = {}
var steps: Array = []
var chaos: int = 1
var widen: float = 1.0
var toggle_mode: bool = false
var rng := RandomNumberGenerator.new()

# ---- run state
var phase: String = "intro"
var phase_t: float = 0.0
var elapsed: float = 0.0
## Art-sheet renders only: parts to skip ("props", "vessel", "meter", "jug") so one
## gauge can be captured without its neighbours. Always empty in play.
var iso_hide: Array = []
var step_i: int = -1
var results: Array = []          # per step {acc, label}
var cats: Array = []             # cameo nodes
var cat_stats: Array = []        # per cat {pets, assists, booped}
var events_left: int = 0
var last_event_at: float = -100.0
var event: Dictionary = {}       # active/pending event
var event_log: Array = []
var sticker: bool = false
var catches: int = 0
var finished: bool = false
var serve_hold: float = 0.0

# ---- step runtime
var ring_t: float = 0.0
var ring_sweeps: int = 0
var ring_hits: Array = []
var pour_level: float = 0.0
var pour_start: float = 0.0
var pouring: bool = false
var drop_t: float = 0.0
var drop_k: int = 0
var drop_accs: Array = []
var drop_falling: bool = false
var drop_pos: Vector2 = Vector2.ZERO
var drop_vy: float = 0.0
var item_on_tray: String = ""
var item_hop: float = -1.0       # 0..1 while the item hops tray -> work spot
var bat_item: Dictionary = {}    # {pos, t, state: "slide"|"bin"}

# ---- dish visuals
var layers: Array = []           # [{color, amount}]
var vessel: String = "mug"
var garnish: Array = []          # [{tex, pos}]
var stamped: int = 0
var baked: float = 0.0           # 0..1 golden
var frosted: bool = false
var shot_done: bool = false

# ---- pet
var pet_cat: int = -1
var pet_t: float = 0.0
var pet_holding: bool = false
var pet_from_mouse: bool = false
var primary_held: bool = false

var _bg: ImageTexture
var _cat_layer: Node2D
var _top: Node2D

func setup(ctx: Dictionary) -> void:
	context = ctx
	recipe = R.recipe_by_id(str(ctx.get("recipe_id", "catpuccino")))
	steps = recipe["steps"]
	chaos = clampi(int(ctx.get("chaos", 1)), 0, 2)
	widen = float(ctx.get("leniency", 1.0))
	toggle_mode = bool(ctx.get("toggle", false))
	if ctx.has("seed"):
		rng.seed = int(ctx["seed"])
	else:
		rng.randomize()
	events_left = R.CHAOS_CAP[chaos]
	vessel = str(recipe.get("vessel", "mug"))
	_bg = _paint_background()
	_cat_layer = Node2D.new()
	_cat_layer.name = "Cats"
	add_child(_cat_layer)
	_top = Node2D.new()
	_top.name = "TopFX"
	add_child(_top)
	_top.draw.connect(_draw_top)
	var infos: Array = ctx.get("cats", [])
	var want: int = 2 if chaos >= 2 else 1
	for i in range(mini(want, infos.size())):
		var info: Dictionary = infos[i]
		var helper: bool = float(info.get("trust", 0.0)) >= R.HELPER_TRUST and str(info.get("mood", "calm")) == "calm"
		info["helper"] = helper
		info["shy"] = float(info.get("trust", 0.0)) < 30.0
		var c: Node2D = CounterCatScript.new()
		c.name = "CounterCat%d" % i
		c.position = home_of(i)
		_cat_layer.add_child(c)
		c.call("setup", info)
		c.set("glint", helper)
		c.call("face_left", true)
		cats.append(c)
		cat_stats.append({"pets": 0, "assists": 0, "booped": 0})
	if helper_widen() > 1.0:
		widen *= R.HELPER_WIDEN
	_set_phase("intro")

func home_of(i: int) -> Vector2:
	return Vector2(HOME_X, CY) if i == 0 else SILL

func helper_widen() -> float:
	for c in cats:
		if bool(c.get("info").get("helper", false)):
			return R.HELPER_WIDEN
	return 1.0

# ------------------------------------------------------------------ phases

func _set_phase(p: String) -> void:
	phase = p
	phase_t = 0.0

func _process(delta: float) -> void:
	if finished:
		queue_redraw()
		return
	elapsed += delta
	phase_t += delta
	_update_pet(delta)
	_update_event(delta)
	match phase:
		"intro":
			if phase_t >= INTRO_SEC:
				_begin_transition()
		"transition":
			if phase_t >= _transition_len():
				_start_step()
		"bat_wait":
			_update_bat(delta)
		"step":
			if not _frozen():
				_update_step(delta)
		"flourish":
			if phase_t >= FLOURISH_SEC:
				_begin_transition()
		"serve":
			_update_serve()
	if item_hop >= 0.0:
		item_hop += delta / 0.3
		if item_hop >= 1.0:
			item_hop = -1.0
	queue_redraw()
	_top.queue_redraw()

func _frozen() -> bool:
	return pet_cat >= 0

func _transition_len() -> float:
	return TELEGRAPH_SEC if (not event.is_empty() and str(event.get("phase", "")) == "telegraph") else TRANSITION_SEC

func _begin_transition() -> void:
	var next_i: int = step_i + 1
	_set_phase("transition")
	if next_i >= steps.size():
		_begin_serve()
		return
	var st: Dictionary = steps[next_i]
	item_on_tray = _tray_item(st)
	if next_i >= 1:
		_maybe_schedule_event(next_i, false)

func _tray_item(st: Dictionary) -> String:
	var it: String = str(st.get("item", ""))
	return it if it in ["jug", "beans", "paw", "fish", "wafer"] else ""

func _start_step() -> void:
	step_i += 1
	var st: Dictionary = steps[step_i]
	vessel = str(st.get("vessel", recipe.get("vessel", "mug")))
	if st.get("item", "") == "puck":
		vessel = "puck"
	ring_t = 0.0
	ring_sweeps = 0
	ring_hits = []
	pouring = false
	pour_start = _fill()
	pour_level = pour_start
	drop_t = 0.0
	drop_k = 0
	drop_accs = []
	drop_falling = false
	# pending event arrives now
	var batting: bool = false
	if not event.is_empty() and str(event.get("phase", "")) == "telegraph":
		batting = _arrive_event()
	if batting:
		_set_phase("bat_wait")
		return
	_item_to_work()
	_set_phase("step")

func _item_to_work() -> void:
	if item_on_tray != "":
		item_hop = 0.0
	item_on_tray = ""

func _finish_step(acc: float, label: String) -> void:
	results.append({"acc": clampf(acc, 0.0, 1.0), "label": label})
	pouring = false
	var col: Color = Art.SAGE_DARK if acc >= 0.85 else (Art.AMBER if acc >= 0.55 else Art.MUTED)
	popup.emit(Vector2(WX, 60), label, col)
	_set_phase("flourish")

# ------------------------------------------------------------------ steps

func current_step() -> Dictionary:
	if step_i < 0 or step_i >= steps.size():
		return {}
	return steps[step_i]

func _update_step(delta: float) -> void:
	var st: Dictionary = current_step()
	match str(st.get("type", "")):
		"ring":
			var sweep: float = float(st.get("sweep_sec", 1.6))
			ring_t += delta
			if ring_t >= sweep:
				ring_t = 0.0
				ring_sweeps += 1
				if ring_sweeps >= R.RING_SWEEPS_BEFORE_AUTO:
					_register_ring_hit(R.RING_OK, "Ok")
		"pour":
			if pouring:
				pour_level = minf(1.0, pour_level + float(st.get("rate", 0.35)) * delta)
				if pour_level >= 1.0:
					_judge_pour()
		"drop":
			if drop_falling:
				drop_vy += 520.0 * delta
				drop_pos.y += drop_vy * delta
				var land: float = _dish_top()
				if drop_pos.y >= land:
					drop_pos.y = land
					drop_falling = false
					var off: float = drop_pos.x - drop_target_x()
					var j: Array = R.drop_judge(off, widen)
					garnish.append({"tex": str(st.get("item", "paw")), "pos": Vector2(roundf(drop_pos.x), land)})
					drop_accs.append(float(j[0]))
					if drop_k + 1 < drop_targets().size():
						drop_k += 1
						drop_t = 0.0
						popup.emit(Vector2(drop_pos.x, land - 16), j[1], Art.SAGE_DARK if float(j[0]) >= 0.85 else Art.AMBER)
					else:
						var sum: float = 0.0
						for a in drop_accs:
							sum += float(a)
						_finish_step(sum / float(drop_accs.size()), j[1])
			else:
				drop_t += delta
				var hz: float = float(st.get("swing_hz", 0.8))
				if drop_t * hz >= float(R.DROP_SWINGS_BEFORE_AUTO):
					drop_pos = _pendulum_pos()
					drop_pos.x = drop_target_x() + signf(drop_pos.x - drop_target_x()) * 10.0
					drop_vy = 0.0
					drop_falling = true

func ring_target_t() -> float:
	var sweep: float = float(current_step().get("sweep_sec", 1.6))
	return sweep * (R.RING_START_R - R.RING_TARGET_R) / R.RING_START_R

func ring_radius() -> float:
	var sweep: float = float(current_step().get("sweep_sec", 1.6))
	return R.RING_START_R * (1.0 - ring_t / sweep)

func _register_ring_hit(acc: float, label: String) -> void:
	ring_hits.append(acc)
	var st: Dictionary = current_step()
	var hits: int = int(st.get("hits", 1))
	var lbl: String = str(st.get("label", ""))
	if lbl.begins_with("Stamp"):
		stamped = ring_hits.size()
	elif lbl == "Bake":
		baked = acc
	elif lbl == "Chill":
		frosted = true
	if ring_hits.size() >= hits:
		var s: float = 0.0
		for a in ring_hits:
			s += float(a)
		_finish_step(s / float(ring_hits.size()), label)
	else:
		popup.emit(_ring_center() + Vector2(0, -22), label, Art.SAGE_DARK if acc >= 0.85 else Art.AMBER)
		ring_t = 0.0
		ring_sweeps = 0

func _ring_center() -> Vector2:
	var st: Dictionary = current_step()
	if str(st.get("label", "")).begins_with("Stamp"):
		var k: int = clampi(ring_hits.size(), 0, 2)
		return Vector2(WX - 22.0 + 22.0 * k, CY - 8)
	match vessel:
		"puck":
			return Vector2(WX, CY - 10)
		"tray":
			return Vector2(WX, CY - 8)
		"glass":
			return Vector2(WX, CY - 24)
	return Vector2(WX, CY - 14)

func _judge_pour() -> void:
	var st: Dictionary = current_step()
	pouring = false
	var j: Array = R.pour_judge(pour_level - float(st.get("target", 0.7)), float(st.get("band", 0.12)), widen)
	# Overshoots are quietly skimmed back near the line so later layers always fit.
	var tgt: float = float(st.get("target", 0.7))
	var band: float = float(st.get("band", 0.12))
	var kept: float = clampf(pour_level, tgt - band, tgt + band * 0.5)
	if pour_level - kept > 0.02:
		popup.emit(Vector2(WX, CY - 56), "(skimmed)", Art.MUTED)
	var amt: float = maxf(0.0, kept - pour_start)
	layers.append({"color": _liquid(str(st.get("color", "milk"))), "amount": amt})
	if str(st.get("color", "")) == "espresso":
		shot_done = true
	_finish_step(j[0], j[1])

func _liquid(id: String) -> Color:
	match id:
		"espresso":
			return Art.ESPRESSO
		"milk":
			return Color("#E9D2B0")
		"dough":
			return Art.DOUGH
		"mango":
			return Art.MANGO
		"sesame":
			return Art.SESAME
		"vanilla":
			return Art.VANILLA
	return Art.MILK

func _fill() -> float:
	var f: float = 0.0
	for l in layers:
		f += float(l["amount"])
	return f

func _pendulum_pos() -> Vector2:
	var hz: float = float(current_step().get("swing_hz", 0.8))
	var a: float = sin(TAU * hz * drop_t)
	var x: float = drop_target_x() + SWING_A * a
	var y: float = PIVOT.y + ROPE + 6.0 - absf(a) * 5.0
	return Vector2(x, y)

func drop_targets() -> Array:
	return current_step().get("targets", [0.0])

func drop_target_x() -> float:
	var t: Array = drop_targets()
	return WX + float(t[clampi(drop_k, 0, t.size() - 1)])

func pendulum_offset() -> float:
	return _pendulum_pos().x - drop_target_x()

func _dish_top() -> float:
	match vessel:
		"glass":
			return CY - 4.0 - 44.0 * clampf(_fill(), 0.0, 1.0) - 2.0
		"tray":
			return CY - 10.0
		"bowl":
			return CY - 16.0
	return CY - 26.0

# ------------------------------------------------------------------ input API (overlay + probe)

func pointer_down(p: Vector2) -> void:
	if finished:
		return
	if phase == "bat_wait" and not bat_item.is_empty():
		if bat_item["state"] == "slide" and p.distance_to(bat_item["pos"]) <= 14.0:
			_catch_bat()
			return
		if bat_item["state"] == "bin" and BIN.grow(6).has_point(p):
			_regrab()
			return
	for i in range(cats.size()):
		var c: Node2D = cats[i]
		if not c.call("hit", p):
			continue
		if _event_is(i, "assist") and str(event.get("phase", "")) == "active":
			assist()
			return
		if _event_is(i, "sniff") and str(event.get("phase", "")) == "active":
			boop()
			return
		if _pettable(i):
			pet_start(i, true)
			return
	primary_down()

func pointer_up(_p: Vector2) -> void:
	if pet_from_mouse and pet_cat >= 0:
		pet_release()
		return
	primary_up()

func primary_down() -> void:
	if finished or primary_held:
		return
	primary_held = true
	if phase == "bat_wait" and not bat_item.is_empty():
		if bat_item["state"] == "slide":
			_catch_bat()
		else:
			_regrab()
		return
	if phase == "serve" and _event_is(-1, "sniff") and str(event.get("phase", "")) == "active":
		boop()
		return
	if phase != "step" or _frozen():
		return
	var st: Dictionary = current_step()
	match str(st.get("type", "")):
		"ring":
			var j: Array = R.ring_judge(ring_t - ring_target_t(), widen)
			_register_ring_hit(j[0], j[1])
		"pour":
			if toggle_mode and pouring:
				_try_release_pour()
			else:
				pouring = true
		"drop":
			if not drop_falling:
				drop_pos = _pendulum_pos()
				drop_vy = 0.0
				drop_falling = true

func primary_up() -> void:
	primary_held = false
	if toggle_mode or phase != "step":
		return
	if str(current_step().get("type", "")) == "pour" and pouring:
		_try_release_pour()

func _try_release_pour() -> void:
	if pour_level - pour_start < 0.03:
		pouring = false   # accidental tap: keep waiting, nothing lost
		return
	_judge_pour()

## Keyboard pet: the cat in the current event, else the nearest one on the counter.
func pet_key_down() -> void:
	var idx: int = -1
	if not event.is_empty() and int(event.get("cat", -1)) >= 0 and _pettable(int(event["cat"])):
		idx = int(event["cat"])
	else:
		for i in range(cats.size()):
			if _pettable(i):
				idx = i
				break
	if idx >= 0:
		pet_start(idx, false)

func pet_key_up() -> void:
	if not pet_from_mouse and pet_cat >= 0:
		pet_release()

func _pettable(i: int) -> bool:
	if i < 0 or i >= cats.size() or finished:
		return false
	var c: Node2D = cats[i]
	if c.position.x < 8.0 or c.position.x > 316.0:
		return false
	if not event.is_empty() and int(event.get("cat", -1)) == i and str(event.get("type", "")) in ["bat", "sniff"] and str(event.get("phase", "")) != "leaving":
		return false
	return true

func pet_start(i: int, from_mouse: bool) -> void:
	if pet_cat >= 0 or not _pettable(i):
		return
	pet_cat = i
	pet_t = 0.0
	pet_holding = true
	pet_from_mouse = from_mouse
	pouring = false if not toggle_mode else pouring

func pet_release() -> void:
	pet_holding = false
	if not toggle_mode and pet_cat >= 0 and pet_t < R.PET_HOLD_SEC:
		cats[pet_cat].set("pet_progress", 0.0)
		pet_cat = -1

func _update_pet(delta: float) -> void:
	if pet_cat < 0:
		return
	if not pet_holding and not toggle_mode:
		return
	pet_t += delta
	var c: Node2D = cats[pet_cat]
	c.set("pet_progress", clampf(pet_t / R.PET_HOLD_SEC, 0.0, 1.0))
	if pet_t >= R.PET_HOLD_SEC + 0.2:
		_complete_pet()

func _complete_pet() -> void:
	var i: int = pet_cat
	pet_cat = -1
	pet_holding = false
	var c: Node2D = cats[i]
	c.set("pet_progress", 0.0)
	c.set("purring", 1.6)
	c.call("happy_bounce")
	c.call("hide_bubble")
	var before: Dictionary = R.care_delta(cat_stats[i]["pets"], cat_stats[i]["assists"])
	cat_stats[i]["pets"] += 1
	var after: Dictionary = R.care_delta(cat_stats[i]["pets"], cat_stats[i]["assists"])
	var gained: bool = after["overstim"] < before["overstim"] or after["trust"] > before["trust"]
	popup.emit(c.position + Vector2(0, -50), "Purr~  calmer!" if gained else "Purr~ (so cozy)", Art.PINK)
	for k in range(3):
		_spawn_heart(c.position + Vector2(-8 + 8 * k, -36))
	if _event_is(i, "loaf") or _event_is(i, "assist"):
		_end_event_cat(i, 0.5)

func _spawn_heart(at: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = Art.heart()
	s.position = at
	add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "position:y", at.y - 16.0, 0.8)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_callback(s.queue_free)

func assist() -> void:
	if event.is_empty() or str(event.get("type", "")) != "assist" or str(event.get("phase", "")) != "active":
		return
	var i: int = int(event["cat"])
	cat_stats[i]["assists"] += 1
	var c: Node2D = cats[i]
	c.call("happy_bounce")
	c.call("hide_bubble")
	c.set("assist_glow", false)
	popup.emit(c.position + Vector2(0, -50), "Paw assist!", Art.GOLD)
	if phase == "step":
		var st: Dictionary = current_step()
		match str(st.get("type", "")):
			"pour":
				pour_level = float(st.get("target", 0.7)) + 0.03
				layers.append({"color": _liquid(str(st.get("color", "milk"))), "amount": pour_level - pour_start})
			"drop":
				for k in range(drop_k, drop_targets().size()):
					drop_k = k
					garnish.append({"tex": str(st.get("item", "paw")), "pos": Vector2(drop_target_x() + 1, _dish_top())})
			"ring":
				var lbl: String = str(st.get("label", ""))
				if lbl.begins_with("Stamp"):
					stamped = 3
				elif lbl == "Bake":
					baked = 0.85
				elif lbl == "Chill":
					frosted = true
		_finish_step(0.85, "Great! (paw assist)")
	_end_event_cat(i, 0.4)

func boop() -> void:
	if event.is_empty() or str(event.get("type", "")) != "sniff" or str(event.get("phase", "")) != "active":
		return
	var i: int = int(event["cat"])
	cat_stats[i]["booped"] += 1
	var c: Node2D = cats[i]
	c.call("lean", -1.0, false)
	c.call("sneeze")
	popup.emit(c.position + Vector2(0, -50), "Boop! ...achoo!", Art.PINK)
	serve_hold = phase_t + 1.0
	_end_event_cat(i, 0.5)

func _catch_bat() -> void:
	catches += 1
	popup.emit(bat_item["pos"] + Vector2(0, -12), "Nice catch!", Art.GOLD)
	_spawn_sparkle(bat_item["pos"])
	bat_item = {}
	_item_to_work()
	_set_phase("step")

func _regrab() -> void:
	popup.emit(BIN.get_center() + Vector2(-24, -20), "Got it!", Art.MUTED)
	bat_item = {}
	_item_to_work()
	_set_phase("step")

func _spawn_sparkle(at: Vector2) -> void:
	for k in range(3):
		var s := Sprite2D.new()
		s.texture = Art.sparkle()
		s.position = at + Vector2(-8 + 8 * k, -4 * (k % 2))
		add_child(s)
		var tw := s.create_tween()
		tw.tween_property(s, "scale", Vector2(1.6, 1.6), 0.25)
		tw.tween_property(s, "modulate:a", 0.0, 0.3)
		tw.tween_callback(s.queue_free)

# ------------------------------------------------------------------ cat events

func _event_is(i: int, t: String) -> bool:
	if event.is_empty() or str(event.get("type", "")) != t:
		return false
	return i < 0 or int(event.get("cat", -1)) == i

func _slots_left(next_i: int) -> int:
	# transitions before steps next_i .. N-1, plus the serve slot
	return (steps.size() - next_i) + 1

func _maybe_schedule_event(next_i: int, serve: bool) -> void:
	if events_left <= 0 or cats.is_empty() or not event.is_empty():
		return
	var arrive_at: float = elapsed + TELEGRAPH_SEC
	if arrive_at < MIN_EVENT_START or arrive_at - last_event_at < MIN_EVENT_GAP:
		return
	var ci: int = 0
	var used: int = R.CHAOS_CAP[chaos] - events_left
	if cats.size() > 1 and used % 2 == 1:
		ci = 1
	var t: String = ""
	var forced: Array = context.get("force_events", [])
	if not forced.is_empty():
		# test hook (probe / screenshots): the next forced event, when this slot can host it
		var f: String = str(forced[0])
		if (f == "sniff") != serve or (f == "bat" and _tray_item(steps[next_i]) == ""):
			return
		t = f
		forced.pop_front()
	else:
		var slots: int = 1 if serve else _slots_left(next_i)
		var p: float = float(events_left) / float(maxi(1, slots))
		if rng.randf() > p:
			return
		t = _pick_event(ci, next_i, serve)
	if t == "":
		return
	events_left -= 1
	last_event_at = arrive_at
	event = {"type": t, "cat": ci, "phase": "telegraph", "t": 0.0}
	event_log.append({"type": t, "cat": ci, "at": arrive_at})
	var c: Node2D = cats[ci]
	c.call("telegraph", "bang")
	# approach during the telegraph so the cat is in place on arrival
	var dest: Vector2 = _event_spot(t)
	var tw: Tween = c.create_tween()
	tw.tween_interval(0.3)
	tw.tween_callback(func() -> void: c.call("go_to", dest, 0.65, "sit"))

func _pick_event(ci: int, next_i: int, serve: bool) -> String:
	var info: Dictionary = cats[ci].get("info")
	var mood: String = str(info.get("mood", "calm"))
	var traits: Array = info.get("traits", [])
	if serve:
		if bool(info.get("shy", false)):
			return ""
		return "sniff"
	if bool(info.get("helper", false)) and not _helper_used():
		return "assist"
	var has_item: bool = _tray_item(steps[next_i]) != ""
	if bool(info.get("shy", false)) or mood == "frazzled":
		return "loaf"
	var w_bat: float = 0.0
	if has_item:
		w_bat = 0.75 if mood == "fizzy" else 0.3
		if traits.has("feisty"):
			w_bat += 0.4
		if traits.has("cuddly"):
			w_bat -= 0.2
	return "bat" if rng.randf() < clampf(w_bat, 0.0, 0.95) else "loaf"

func _helper_used() -> bool:
	for e in event_log:
		if e["type"] == "assist":
			return true
	return false

func _event_spot(t: String) -> Vector2:
	match t:
		"loaf":
			return Vector2(TX, CY)
		"bat":
			return Vector2(TX - 24.0, CY)
		"assist":
			return Vector2(WX + 46.0, CY)
		"sniff":
			return Vector2(WX + 32.0, CY)
	return Vector2(TX, CY)

## Returns true when the step must wait (bat).
func _arrive_event() -> bool:
	event["phase"] = "active"
	event["t"] = 0.0
	var i: int = int(event["cat"])
	var c: Node2D = cats[i]
	c.call("hide_bubble")
	match str(event["type"]):
		"loaf":
			var info: Dictionary = c.get("info")
			if str(info.get("mood", "")) == "frazzled":
				c.call("set_pose", "sit")
				c.call("set_expression", "worried")
				c.call("show_bubble", "pets")
			else:
				c.call("set_pose", "sleep")
				c.call("set_expression", "sleepy")
			c.call("face_left", true)
			popup.emit(Vector2(TX, CY - 50), "%s loafs on the tray" % c.call("cat_name"), Art.MUTED)
		"bat":
			c.call("face_left", false)
			c.call("lunge", 1.0)
			bat_item = {"tex": item_on_tray, "pos": Vector2(TX, CY - 6), "t": 0.0, "state": "slide"}
			item_on_tray = ""
			popup.emit(Vector2(TX, CY - 46), "Bat! Catch it!", Art.ORANGE)
			return true
		"assist":
			c.call("face_left", true)
			c.call("set_expression", "happy")
			c.call("show_bubble", "paw")
			c.set("assist_glow", true)
			popup.emit(c.position + Vector2(0, -50), "Helper paw ready!", Art.GOLD)
	return false

func _update_event(delta: float) -> void:
	if event.is_empty():
		return
	event["t"] = float(event["t"]) + delta
	if str(event["phase"]) != "active":
		return
	var i: int = int(event["cat"])
	match str(event["type"]):
		"loaf":
			if float(event["t"]) >= LOAF_SEC and pet_cat != i:
				_end_event_cat(i, 0.0)
		"assist":
			if float(event["t"]) >= ASSIST_SEC:
				cats[i].set("assist_glow", false)
				_end_event_cat(i, 0.0)
		"bat":
			if float(event["t"]) >= 0.5:
				_end_event_cat(i, 0.0)

func _end_event_cat(i: int, delay: float) -> void:
	var c: Node2D = cats[i]
	if not event.is_empty() and int(event.get("cat", -1)) == i:
		event = {}
	c.call("hide_bubble")
	c.set("assist_glow", false)
	var home: Vector2 = home_of(i)
	var tw: Tween = c.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		c.call("rest_face")
		var dur: float = clampf(c.position.distance_to(home) / 90.0, 0.4, 2.0)
		c.call("go_to", home, dur, "sit", 1))

func _update_bat(delta: float) -> void:
	if bat_item.is_empty():
		_item_to_work()
		_set_phase("step")
		return
	bat_item["t"] = float(bat_item["t"]) + delta
	if bat_item["state"] == "slide":
		var k: float = clampf(float(bat_item["t"]) / BAT_SLIDE_SEC, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - k, 2.0)
		bat_item["pos"] = Vector2(lerpf(TX, 314.0, e), CY - 6)
		if k >= 1.0:
			bat_item["state"] = "bin"
			bat_item["t"] = 0.0
			bat_item["pos"] = BIN.get_center() + Vector2(0, -4)
			popup.emit(BIN.get_center() + Vector2(-30, -20), "Plop! Soft landing", Art.MUTED)
	else:
		if float(bat_item["t"]) >= BIN_REGRAB_SEC:
			_regrab()

# ------------------------------------------------------------------ serve / result

func _begin_serve() -> void:
	_set_phase("serve")
	if _event_is(-1, "assist"):
		_end_event_cat(int(event["cat"]), 0.0)
	_maybe_schedule_event(steps.size(), true)
	popup.emit(Vector2(WX, 50), "Order up!", Art.SAGE_DARK)

func _update_serve() -> void:
	var sniff: bool = _event_is(-1, "sniff")
	if sniff:
		var ph: String = str(event["phase"])
		if ph == "telegraph" and float(event["t"]) >= TELEGRAPH_SEC:
			event["phase"] = "active"
			event["t"] = 0.0
			var c: Node2D = cats[int(event["cat"])]
			c.call("hide_bubble")
			c.call("face_left", true)
			c.call("lean", -1.0, true)
			popup.emit(c.position + Vector2(0, -50), "*sniff sniff*  boop it?", Art.MUTED)
		elif ph == "active" and float(event["t"]) >= SNIFF_SEC:
			sticker = true
			var i: int = int(event["cat"])
			var c2: Node2D = cats[i]
			c2.call("lean", -1.0, false)
			garnish.append({"tex": "sticker", "pos": Vector2(WX + 8, _dish_top() + 6)})
			popup.emit(Vector2(WX, 60), "Cat-Approved!", Art.PINK)
			serve_hold = phase_t + 1.0
			_end_event_cat(i, 0.3)
		return
	if phase_t >= 0.9 and phase_t >= serve_hold and pet_cat < 0:
		_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	var s: float = 0.0
	for r in results:
		s += float(r["acc"])
	var mean: float = s / float(maxi(1, results.size()))
	var precision: float = 70.0 * mean
	var speed: float = 30.0 * R.speed_factor(elapsed, float(recipe["par_sec"]))
	var score: float = precision + speed
	var grade: String = R.grade_for(score)
	var cats_out: Array = []
	for i in range(cats.size()):
		var info: Dictionary = cats[i].get("info")
		var st: Dictionary = cat_stats[i]
		cats_out.append({
			"name": str(info.get("name", "Cat")),
			"node_id": int(info.get("node_id", 0)),
			"pets": int(st["pets"]),
			"assists": int(st["assists"]),
			"booped": int(st["booped"]),
			"delta": R.care_delta(int(st["pets"]), int(st["assists"])),
		})
	var result := {
		"recipe_id": recipe["id"], "recipe_name": recipe["name"],
		"grade": grade, "grade_text": Art.GRADE_TEXT[grade], "score": score,
		"precision": precision, "speed": speed, "elapsed": elapsed, "par": float(recipe["par_sec"]),
		"money": R.money_for(grade, float(recipe["price_mult"])),
		"cats": cats_out, "sticker": sticker, "catches": catches,
		"steps": results.duplicate(true), "events": event_log.duplicate(true),
		"grade_value": clampf(score / 100.0, 0.0, 1.0),
	}
	scored.emit(result)

# ------------------------------------------------------------------ HUD / probe info

func get_hud_info() -> Dictionary:
	var st_list: Array = []
	for i in range(steps.size()):
		var state: String = "todo"
		if i < results.size():
			state = "done"
		elif i == step_i and phase in ["step", "bat_wait"]:
			state = "active"
		elif i == step_i + 1 and phase == "transition":
			state = "next"
		st_list.append({"label": steps[i]["label"], "state": state, "acc": (results[i]["acc"] if i < results.size() else -1.0)})
	var hint: String = ""
	var hold_word: String = "TAP" if toggle_mode else "HOLD"
	match phase:
		"intro":
			hint = "Order: %s. Let's cook!" % recipe["name"]
		"transition":
			hint = "Next: %s" % (steps[step_i + 1]["label"] if step_i + 1 < steps.size() else "serve")
		"bat_wait":
			if not bat_item.is_empty() and bat_item["state"] == "slide":
				hint = "Click the sliding %s (or Space) to catch it!" % _item_name(str(bat_item.get("tex", "")))
			else:
				hint = "It landed in the cushion bin - click it (or Space) to grab it back"
		"step":
			var st: Dictionary = current_step()
			match str(st.get("type", "")):
				"ring":
					hint = "TAP (click / Space) when the ring meets the paw circle"
				"pour":
					hint = ("%s (click / Space) to pour, %s on the line" % [hold_word, "tap again" if toggle_mode else "let go"])
				"drop":
					hint = "TAP (click / Space) to drop it on the cup's center"
		"serve":
			hint = "Order up!"
	var alert: String = ""
	if not event.is_empty():
		var nm: String = str(cats[int(event["cat"])].call("cat_name"))
		if str(event["phase"]) == "telegraph":
			alert = "%s is eyeing the counter..." % nm
		else:
			match str(event["type"]):
				"loaf":
					alert = "%s is loafing - pet (P / hold click) or work around" % nm
				"bat":
					alert = "%s batted the %s!" % [nm, _item_name(str(bat_item.get("tex", "")))]
				"assist":
					alert = "%s offers a paw - press A or click them for a free Great" % nm
				"sniff":
					alert = "%s is sniffing the dish - boop (click / Space)!" % nm
	var chips: Array = []
	for i in range(cats.size()):
		var info: Dictionary = cats[i].get("info")
		chips.append({"name": info.get("name", "Cat"), "mood": info.get("mood", "calm"), "trust": info.get("trust", 0.0), "pets": cat_stats[i]["pets"], "helper": info.get("helper", false), "shy": info.get("shy", false)})
	return {
		"title": recipe["name"], "difficulty": recipe["difficulty"], "par_sec": recipe["par_sec"],
		"elapsed_sec": elapsed, "steps": st_list, "hint": hint, "alert": alert,
		"telegraph": (not event.is_empty() and str(event["phase"]) == "telegraph"), "cats": chips,
		"petting": pet_cat >= 0,
	}

func _item_name(t: String) -> String:
	match t:
		"jug":
			return "milk jug"
		"beans":
			return "coffee beans"
		"paw":
			return "foam paw"
		"fish":
			return "sugar fish"
		"wafer":
			return "ear wafer"
	return "ingredient"

func can_park() -> bool:
	return not finished

## Snapshot for the probe's bot.
func get_debug_state() -> Dictionary:
	var st: Dictionary = current_step()
	var d := {"phase": phase, "step_i": step_i, "type": str(st.get("type", "")), "finished": finished,
		"event": event.duplicate(), "pet_cat": pet_cat, "bat": bat_item.duplicate(), "elapsed": elapsed}
	if phase == "step":
		match d["type"]:
			"ring":
				d["ring_err"] = ring_t - ring_target_t()
			"pour":
				d["pour_level"] = pour_level
				d["pour_target"] = float(st.get("target", 0.7))
				d["pouring"] = pouring
			"drop":
				d["drop_off"] = pendulum_offset()
				d["drop_falling"] = drop_falling
	return d

# ------------------------------------------------------------------ drawing

func _draw() -> void:
	draw_texture(_bg, Vector2.ZERO)
	if not iso_hide.has("props"):
		_draw_tray()
		_draw_bin()
		_draw_cushion()
		_draw_work_glow()
	if not iso_hide.has("vessel"):
		_draw_vessel()
		_draw_garnish()
	if phase == "step" or phase == "flourish":
		var t: String = str(current_step().get("type", ""))
		if t == "pour" and phase == "step":
			_draw_pour_ui()
		elif t == "ring" and phase == "step":
			_draw_ring()
		elif t == "drop":
			_draw_pendulum()

func _draw_top() -> void:
	if phase != "bat_wait" or bat_item.is_empty():
		return
	var tex: Texture2D = _item_tex(str(bat_item.get("tex", "")))
	if tex == null:
		return
	var p: Vector2 = bat_item["pos"]
	if bat_item["state"] == "slide":
		var wob: float = roundf(sin(float(bat_item["t"]) * 30.0))
		_arc(_top, p, 11.0, Art.GOLD, 1.0, 20)
		_top.draw_texture(tex, (p - tex.get_size() * 0.5 + Vector2(0, wob)).round())
	else:
		_arc(_top, p, 12.0 + roundf(sin(elapsed * 8.0)), Art.SAGE_DARK, 1.0, 20)
		_top.draw_texture(tex, (p - tex.get_size() * 0.5).round())

## Outlined box. Style A: 1px outline inside r (today's look). B-F: the outline
## grows outward to the style's thickness, plus halo / drop shadow (fx), rim
## light and cel shade on the fill.
func _box(r: Rect2, fill: Color, line: Color = Art.OUTLINE, fx: bool = true) -> void:
	r = Rect2(r.position.round(), r.size.round())
	if Art.is_a():
		draw_rect(r, line)
		draw_rect(r.grow(-1), fill)
		return
	if fx:
		_box_fx([r])
	var outer: Rect2 = r.grow(Art.ow() - 1)
	_notched(outer, line)
	var inner: Rect2 = r.grow(-1)
	if inner.size.x <= 0 or inner.size.y <= 0:
		return
	draw_rect(inner, fill)
	_shade_rect(inner, fill)

## Halo + drop shadow under a group of boxes (drawn first so parts of one object
## don't put cream seams on each other).
func _box_fx(rects: Array) -> void:
	if Art.is_a():
		return
	var g: int = Art.ow() - 1
	if Art.flag("shadow"):
		for q in rects:
			var o: Rect2 = Rect2((q as Rect2).position.round(), (q as Rect2).size.round()).grow(g)
			_notched(Rect2(o.position + Vector2(1, 1), o.size), Art.SHADOW)
	if Art.flag("halo"):
		for q in rects:
			var o2: Rect2 = Rect2((q as Rect2).position.round(), (q as Rect2).size.round()).grow(g + 1)
			_notched(o2, Art.CREAM)

## Rect with its 4 corner pixels cut when shapes are chunky (rounder silhouettes).
func _notched(r: Rect2, col: Color, ci: CanvasItem = null) -> void:
	var c: CanvasItem = self if ci == null else ci
	if not Art.chunky() or r.size.x < 4 or r.size.y < 4:
		c.draw_rect(r, col)
		return
	c.draw_rect(Rect2(r.position.x + 1, r.position.y, r.size.x - 2, r.size.y), col)
	c.draw_rect(Rect2(r.position.x, r.position.y + 1, 1, r.size.y - 2), col)
	c.draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 1, r.size.y - 2), col)

## Rim light (top + left 1px) and 2-tone cel shade (bottom third) on a filled rect.
func _shade_rect(inner: Rect2, fill: Color) -> void:
	if fill.a < 0.5:
		return
	if Art.flag("cel") and inner.size.y >= 3:
		var h: float = maxf(1.0, roundf(inner.size.y * 0.3))
		draw_rect(Rect2(inner.position.x, inner.end.y - h, inner.size.x, h), Art.cel_col(fill))
	if Art.flag("rim"):
		draw_rect(Rect2(inner.position.x, inner.position.y, inner.size.x, 1), Art.rim_col(fill))
		if inner.size.y > 2:
			draw_rect(Rect2(inner.position.x, inner.position.y + 1, 1, inner.size.y - 2), Art.rim_col(fill))

## A detail pixel-rect: chunky styles enforce a 2px minimum feature size.
func _dot(r: Rect2, col: Color) -> void:
	if not Art.is_a():
		r = Rect2(r.position, Vector2(maxf(2.0, r.size.x), maxf(2.0, r.size.y)))
	draw_rect(r, col)

## Ring / arc line. Style A: plain 1px arc. B-F: dark outline arc under a
## thicker coloured arc (outline_px each side).
func _arc(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float, seg: int, a0: float = 0.0, a1: float = TAU) -> void:
	if Art.is_a():
		ci.draw_arc(c, r, a0, a1, seg, col, w, false)
		return
	var cw: float = w + (1.0 if Art.chunky() else 0.0)
	if Art.flag("shadow"):
		ci.draw_arc(c + Vector2(1, 1), r, a0, a1, seg, Art.SHADOW, cw + 2.0 * Art.ow(), false)
	if Art.flag("halo"):
		ci.draw_arc(c, r, a0, a1, seg, Art.CREAM, cw + 2.0 * Art.ow() + 2.0, false)
	ci.draw_arc(c, r, a0, a1, seg, Art.OUTLINE, cw + 2.0 * Art.ow(), false)
	ci.draw_arc(c, r, a0, a1, seg, col, cw, false)

## Extra transparent padding the current style adds around sprites (0 in A).
func _spad() -> float:
	return float(Art.sprite_pad() - 1)

func _draw_tray() -> void:
	_box(Rect2(TX - 16, CY - 3, 32, 5), Art.OAK_LIGHT)
	if Art.is_a():
		draw_rect(Rect2(TX - 15, CY - 2, 30, 1), Color(Color.WHITE, 0.35))
	var it: String = item_on_tray
	if it != "" and phase in ["transition", "intro", "flourish"]:
		var tex: Texture2D = _item_tex(it)
		if tex != null:
			var bob: float = 0.0 if _event_is(-1, "loaf") else roundf(sin(elapsed * 5.0) * 0.6)
			draw_texture(tex, Vector2(TX - roundf(tex.get_size().x / 2.0), CY - 3 - tex.get_size().y + bob + _spad()))
	# hop from tray to work spot
	if item_hop >= 0.0:
		pass

func _item_tex(id: String) -> Texture2D:
	match id:
		"jug":
			return Art.jug()
		"beans":
			return Art.beans()
		"paw":
			return Art.paw()
		"fish":
			return Art.fish()
		"wafer":
			return Art.wafer()
		"sticker":
			return Art.sticker()
	return null

func _draw_bin() -> void:
	var b: Rect2 = BIN
	var lid := Rect2(b.position.x + 2, b.position.y - 3, b.size.x - 4, 5)
	_box_fx([b, lid])
	_box(b, Color("#D9B48A"), Art.OUTLINE, false)
	if Art.chunky():
		for x in range(int(b.position.x) + 4, int(b.end.x) - 3, 6):
			draw_rect(Rect2(x, b.position.y + 3, 2, b.size.y - 6), Color("#B88A63"))
	else:
		for x in range(int(b.position.x) + 3, int(b.end.x) - 1, 4):
			draw_rect(Rect2(x, b.position.y + 2, 1, b.size.y - 4), Color("#B88A63"))
	_box(lid, Art.PINK, Art.OUTLINE, false)

func _draw_cushion() -> void:
	_box(Rect2(HOME_X - 20, CY - 4, 40, 7), Color("#E7B7C0"))
	if not Art.flag("rim"):
		_dot(Rect2(HOME_X - 18, CY - 3, 36, 1), Color("#F4D3D9"))

func _draw_work_glow() -> void:
	# lace doily placemat under the work spot (scalloped edge)
	var col: Color = Color("#FFFDF6")
	if Art.is_a():
		draw_rect(Rect2(WX - 38, CY - 3, 76, 6), Art.OUTLINE)
		draw_rect(Rect2(WX - 37, CY - 2, 74, 4), col)
		for x in range(int(WX) - 36, int(WX) + 36, 4):
			draw_rect(Rect2(x, CY + 3, 2, 1), col)
			draw_rect(Rect2(x - 1, CY + 3, 1, 1), Art.OUTLINE)
			draw_rect(Rect2(x + 2, CY + 3, 1, 1), Art.OUTLINE)
			draw_rect(Rect2(x, CY + 4, 2, 1), Art.OUTLINE)
	else:
		_draw_doily_styled(col)
	if phase == "step":
		var a: float = 0.5 + 0.5 * sin(elapsed * 4.0)
		draw_rect(Rect2(WX - 36, CY - 2, 72, 1), Color(Art.GOLD, 0.35 * a))

func _draw_doily_styled(col: Color) -> void:
	var o: int = Art.ow()
	var mat := Rect2(WX - 37, CY - 2, 74, 4)
	# scallops: 2px bumps (4px in chunky styles) along the front edge
	var sw: int = 4 if Art.chunky() else 2
	var gap: int = 8 if Art.chunky() else 4
	var bumps: Array = []
	for x in range(int(WX) - 36 + (2 if Art.chunky() else 0), int(WX) + 36 - sw + 1, gap):
		bumps.append(Rect2(x, CY + 2, sw, 2))
	if Art.flag("shadow"):
		draw_rect(Rect2(mat.grow(o).position + Vector2(1, 1), mat.grow(o).size), Art.SHADOW)
	if Art.flag("halo"):
		draw_rect(mat.grow(o + 1), Art.CREAM)
		for q in bumps:
			draw_rect((q as Rect2).grow(o + 1), Art.CREAM)
	for q in bumps:
		_notched((q as Rect2).grow(o), Art.OUTLINE)
	_notched(mat.grow(o), Art.OUTLINE)
	for q in bumps:
		draw_rect(q, col)
	draw_rect(mat, col)
	if Art.flag("cel"):
		draw_rect(Rect2(mat.position.x, mat.end.y - 1, mat.size.x, 1), Color("#EFE6D8"))
		for q in bumps:
			draw_rect(q, Color("#EFE6D8"))

func _draw_vessel() -> void:
	match vessel:
		"puck":
			# portafilter: handle + basket of grounds
			var tamped: bool = results.size() > 0 or (phase == "flourish")
			_box_fx([Rect2(WX - 30, CY - 14, 18, 5), Rect2(WX - 13, CY - 16, 26, 10), Rect2(WX - 11, CY - 18 + (2 if tamped else 0), 22, 4), Rect2(WX - 8, CY - 6, 16, 6)])
			_box(Rect2(WX - 30, CY - 14, 18, 5), Color("#5A4B45"), Art.OUTLINE, false)
			_box(Rect2(WX - 13, CY - 16, 26, 10), Color("#B7C2C9"), Art.OUTLINE, false)
			_box(Rect2(WX - 11, CY - 18 + (2 if tamped else 0), 22, 4), Art.COFFEE, Art.OUTLINE, false)
			_box(Rect2(WX - 8, CY - 6, 16, 6), Color("#8E9AA2"), Art.OUTLINE, false)
		"mug":
			if not Art.is_a():
				_draw_mug_styled()
				return
			_box(Rect2(WX + 14, CY - 22, 8, 14), Art.CREAM)
			draw_rect(Rect2(WX + 16, CY - 19, 4, 8), Color(0, 0, 0, 0))
			_box(Rect2(WX + 15, CY - 20, 5, 10), Color("#FFFFFF00"))
			# cat-ear rim
			for sx in [-1, 1]:
				var ex: float = WX + 11.0 * sx
				for k in range(4):
					var w: float = 8.0 - 2.0 * k
					draw_rect(Rect2(ex - w / 2.0 - 1, CY - 29 - k, w + 2, 1), Art.OUTLINE)
					draw_rect(Rect2(ex - w / 2.0, CY - 29 - k, w, 1), Color("#F7EBDD") if k > 0 else Art.PINK)
				draw_rect(Rect2(ex - 1, CY - 33, 2, 1), Art.OUTLINE)
			_box(Rect2(WX - 17, CY - 28, 34, 28), Color("#F7EBDD"))
			_draw_layers(Rect2(WX - 15, CY - 26, 30, 24))
			draw_rect(Rect2(WX - 15, CY - 8, 30, 2), Color("#E7B7C0"))
		"glass":
			_box(Rect2(WX - 12, CY - 50, 24, 50), Color("#EAF4F6"))
			_draw_layers(Rect2(WX - 10, CY - 48, 20, 44))
			draw_rect(Rect2(WX - 9, CY - 46, 2, 30), Color(Color.WHITE, 0.6))
			if frosted:
				for k in range(6):
					_dot(Rect2(WX - 8 + (k * 7) % 17, CY - 44 + k * 7, 1, 1), Color.WHITE)
		"bowl":
			_box_fx([Rect2(WX - 24, CY - 20, 48, 18), Rect2(WX - 18, CY - 4, 36, 4)])
			_box(Rect2(WX - 24, CY - 20, 48, 18), Color("#B9D7E0"), Art.OUTLINE, false)
			_box(Rect2(WX - 18, CY - 4, 36, 4), Color("#9CC3CF"), Art.OUTLINE, false)
			_draw_layers(Rect2(WX - 22, CY - 18, 44, 14))
		"tray":
			_box(Rect2(WX - 36, CY - 4, 72, 5), Color("#9AA5AD"))
			for k in range(3):
				var cx: float = WX - 22 + 22 * k
				var col: Color = Art.DOUGH.lerp(Art.COOKIE, clampf(baked, 0.0, 1.0))
				_box(Rect2(cx - 8, CY - 10, 16, 7), col, Art.OUTLINE, Art.is_a())
				if k < stamped and Art.chunky():
					# chunky paw print: 2px toes + 4x2 pad
					draw_rect(Rect2(cx - 2, CY - 6, 4, 2), Art.OAK_DEEP)
					draw_rect(Rect2(cx - 5, CY - 9, 2, 2), Art.OAK_DEEP)
					draw_rect(Rect2(cx - 1, CY - 9, 2, 2), Art.OAK_DEEP)
					draw_rect(Rect2(cx + 3, CY - 9, 2, 2), Art.OAK_DEEP)
				elif k < stamped:
					draw_rect(Rect2(cx - 2, CY - 7, 4, 2), Art.OAK_DEEP)
					draw_rect(Rect2(cx - 4, CY - 9, 1, 1), Art.OAK_DEEP)
					draw_rect(Rect2(cx - 1, CY - 9, 2, 1), Art.OAK_DEEP)
					draw_rect(Rect2(cx + 3, CY - 9, 1, 1), Art.OAK_DEEP)
			if str(current_step().get("label", "")) == "Bake" and phase == "step":
				for k in range(3):
					var y: float = CY - 16 - fmod(elapsed * 10.0 + k * 4.0, 12.0)
					_dot(Rect2(WX - 16 + k * 16 + roundf(sin(y) * 1.5), y, 1, 3), Color(Art.ORANGE, 0.6))

## Cat-ear mug for styles B-F: same footprint, thick outline, stepped ears
## (chunky: 2px steps), solid handle ring with a clean hole.
func _draw_mug_styled() -> void:
	var o: int = Art.ow()
	var body := Rect2(WX - 17, CY - 28, 34, 28)
	var handle := Rect2(WX + 14, CY - 22, 8, 14) if not Art.chunky() else Rect2(WX + 14, CY - 23, 9, 16)
	var ears: Array = []
	for sx in [-1, 1]:
		var ex: float = WX + 11.0 * sx
		if Art.chunky():
			ears.append(Rect2(ex - 4, CY - 30, 8, 2))
			ears.append(Rect2(ex - 2, CY - 32, 4, 2))
		else:
			for k in range(4):
				var w: float = 8.0 - 2.0 * k
				ears.append(Rect2(ex - w / 2.0, CY - 29 - k, w, 1))
	_box_fx([body, handle] + ears)
	for q in ears:
		_notched((q as Rect2).grow(o), Art.OUTLINE)
	_box(handle, Art.CREAM, Art.OUTLINE, false)
	var hole: Rect2 = Rect2(handle.position.x + 2, handle.position.y + 3, handle.size.x - 4, handle.size.y - 6)
	draw_rect(Rect2(hole.position.x, hole.position.y, hole.size.x - (1 if not Art.chunky() else 0), hole.size.y), Art.OUTLINE)
	for q in ears:
		var e: Rect2 = q
		var tip: bool = e.position.y <= CY - 31 if Art.chunky() else e.position.y <= CY - 32
		draw_rect(e, Color("#F7EBDD") if tip else Art.PINK)
		if Art.chunky() and not tip:
			draw_rect(Rect2(e.position.x + 2, e.position.y, e.size.x - 4, e.size.y), Art.PINK)
			draw_rect(Rect2(e.position.x, e.position.y, 2, e.size.y), Color("#F7EBDD"))
			draw_rect(Rect2(e.end.x - 2, e.position.y, 2, e.size.y), Color("#F7EBDD"))
	_box(body, Color("#F7EBDD"), Art.OUTLINE, false)
	_draw_layers(Rect2(WX - 15, CY - 26, 30, 24))
	draw_rect(Rect2(WX - 15, CY - 8, 30, 2), Color("#E7B7C0"))

func _draw_layers(inner: Rect2) -> void:
	var y: float = inner.end.y
	var all: Array = layers.duplicate()
	if phase == "step" and str(current_step().get("type", "")) == "pour":
		all.append({"color": _liquid(str(current_step().get("color", "milk"))), "amount": pour_level - pour_start})
	for l in all:
		var h: float = roundf(inner.size.y * float(l["amount"]))
		if h <= 0.0:
			continue
		y -= h
		draw_rect(Rect2(inner.position.x, y, inner.size.x, h), l["color"])
		draw_rect(Rect2(inner.position.x, y, inner.size.x, 1), Color(l["color"]).lightened(0.2))
	if not garnish.is_empty() and vessel == "mug":
		pass

func _draw_garnish() -> void:
	for g in garnish:
		var tex: Texture2D = _item_tex(str(g["tex"]))
		if tex == null:
			continue
		var p: Vector2 = g["pos"]
		draw_texture(tex, Vector2(roundf(p.x - tex.get_size().x / 2.0), roundf(p.y - tex.get_size().y + 3 + _spad())))

func _draw_pour_ui() -> void:
	var st: Dictionary = current_step()
	var target: float = float(st.get("target", 0.7))
	var half: float = float(st.get("band", 0.12)) * 0.5 * widen
	var m := Rect2(MX, METER_TOP, 10, METER_H)
	var col: Color = _liquid(str(st.get("color", "milk")))
	var inner: Rect2 = _vessel_inner()
	if not iso_hide.has("meter"):
		_draw_pour_meter(st, m, target, half, col)
	# the line on the vessel itself
	if inner.size.y > 0 and not iso_hide.has("vessel"):
		var vy: float = roundf(inner.end.y - inner.size.y * target)
		if not Art.is_a():
			for x in range(int(inner.position.x) - 2, int(inner.end.x) + 2, 5):
				draw_rect(Rect2(x, vy - 1, 3, 2), Art.SAGE_DARK)
		else:
			for x in range(int(inner.position.x) - 2, int(inner.end.x) + 2, 3):
				draw_rect(Rect2(x, vy, 2, 1), Art.SAGE_DARK)
	if iso_hide.has("jug"):
		return
	_draw_pour_source(st, inner, col)

func _draw_pour_meter(st: Dictionary, m: Rect2, target: float, half: float, col: Color) -> void:
	_box(m.grow(1), Color("#FBF3E6"))
	var y_of := func(f: float) -> float: return roundf(m.end.y - METER_H * f)
	# good band, great band, perfect core
	var gb0: float = y_of.call(minf(1.0, target + half * 2.0))
	var gb1: float = y_of.call(maxf(0.0, target - half * 2.0))
	draw_rect(Rect2(m.position.x, gb0, m.size.x, gb1 - gb0), Color(Art.SAGE, 0.35))
	var b0: float = y_of.call(minf(1.0, target + half))
	var b1: float = y_of.call(maxf(0.0, target - half))
	draw_rect(Rect2(m.position.x, b0, m.size.x, b1 - b0), Art.SAGE)
	var ty: float = y_of.call(target)
	if Art.is_a():
		draw_rect(Rect2(m.position.x - 3, ty, m.size.x + 6, 1), Art.SAGE_DARK)
	else:
		var tl := Rect2(m.position.x - 4, ty - 1, m.size.x + 8, 2)
		draw_rect(tl.grow(1), Art.OUTLINE)
		draw_rect(tl, Art.SAGE_DARK)
	# current level
	var ly: float = y_of.call(pour_level)
	draw_rect(Rect2(m.position.x + 3, ly, 4, m.end.y - ly), col)
	draw_rect(Rect2(m.position.x + 3, ly, 4, 1 if Art.is_a() else 2), Art.OUTLINE)
	# arrow
	var ax: float = m.end.x + 2 + (Art.ow() - 1)
	if Art.is_a():
		for k in range(3):
			draw_rect(Rect2(ax + k, ly - k, 1, 1 + 2 * k), Art.OUTLINE)
	else:
		# 2px-wide columns: a solid 8x8 notch arrow
		for k in range(4):
			draw_rect(Rect2(ax + 2 * k, ly - k, 2, 2 + 2 * k), Art.OUTLINE)
	# paw marker on the target line
	var pt: Texture2D = Art.paw(Art.SAGE_DARK, "paw_sage")
	draw_texture(pt, Vector2(m.end.x + 6, ty - 5) + Vector2(0, -_spad()) + Vector2(Art.ow() - 1, 0))

func _draw_pour_source(st: Dictionary, inner: Rect2, col: Color) -> void:
	# jug + stream
	var jt: Texture2D = Art.jug() if str(st.get("item", "")) != "beans" else null
	if str(st.get("color", "")) == "espresso":
		# espresso spout above the mug
		_box_fx([Rect2(WX - 10, CY - 62, 20, 8), Rect2(WX - 3, CY - 55, 6, 4)])
		_box(Rect2(WX - 10, CY - 62, 20, 8), Color("#5A4B45"), Art.OUTLINE, false)
		_box(Rect2(WX - 3, CY - 55, 6, 4), Color("#8E9AA2"), Art.OUTLINE, false)
		if pouring:
			if Art.is_a():
				draw_rect(Rect2(WX - 1, CY - 51, 2, 51 - 2 - inner.size.y * pour_level), Art.ESPRESSO)
			else:
				_draw_stream(WX - 2.0, CY - 51 + float(Art.ow() - 1), CY - 2 - inner.size.y * pour_level, Art.COFFEE)
	elif jt != null:
		var jp := Vector2(WX + 14, CY - 74)
		draw_set_transform(jp + Vector2(6, 6), -0.55 if pouring else -0.15, Vector2.ONE)
		draw_texture(jt, Vector2(-6, -6) - Vector2(_spad(), _spad()))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if pouring:
			var top: float = jp.y + 14
			var bottom: float = inner.end.y - inner.size.y * pour_level
			if Art.is_a():
				draw_rect(Rect2(WX + 8, top, 2, maxf(0.0, bottom - top)), col)
			else:
				_draw_stream(WX + 8.0, top, bottom, col)

## B-F pour stream: one solid 2px liquid ribbon outlined on its outside
## edges only (no inner lines, no hollow middle), plus a 2px splash where it lands.
func _draw_stream(x: float, top: float, bottom: float, col: Color) -> void:
	var b: float = roundf(bottom)
	var h: float = maxf(0.0, b - top)
	if h <= 0.0:
		return
	draw_rect(Rect2(x - 1, top, 4, h), Art.OUTLINE)
	draw_rect(Rect2(x, top, 2, h), col)
	draw_rect(Rect2(x - 3, b - 2, 8, 2), col.lightened(0.3))

func _vessel_inner() -> Rect2:
	match vessel:
		"mug":
			return Rect2(WX - 15, CY - 26, 30, 24)
		"glass":
			return Rect2(WX - 10, CY - 48, 20, 44)
		"bowl":
			return Rect2(WX - 22, CY - 18, 44, 14)
	return Rect2()

func _draw_ring() -> void:
	var c: Vector2 = _ring_center().round()
	var st: Dictionary = current_step()
	var sweep: float = float(st.get("sweep_sec", 1.6))
	var px_per_sec: float = R.RING_START_R / sweep
	var good_px: float = 0.20 * widen * px_per_sec
	var tr: float = R.RING_TARGET_R
	# good-zone annulus
	draw_arc(c, tr, 0, TAU, 40, Color(Art.SAGE, 0.35), maxf(2.0, good_px * 2.0), false)
	# dashed target ring
	var dashes: int = 16 if not Art.chunky() else 12
	for k in range(dashes):
		var a0: float = TAU * float(k) / float(dashes)
		if Art.is_a():
			draw_arc(c, tr, a0, a0 + TAU / 32.0, 3, Art.SAGE_DARK, 1.0, false)
		else:
			draw_arc(c, tr, a0, a0 + TAU / float(dashes * 2), 3, Art.SAGE_DARK, 2.0, false)
	draw_texture(Art.paw(Art.SAGE_DARK, "paw_sage"), c + Vector2(-6, -tr - 11) - Vector2(_spad(), _spad()))
	# shrinking ring
	var r: float = ring_radius()
	var err: float = absf(ring_t - ring_target_t())
	var col: Color = Art.SAGE_DARK if err <= 0.12 * widen else Art.AMBER
	if Art.is_a():
		draw_arc(c, r, 0, TAU, 48, Art.OUTLINE, 3.0, false)
		draw_arc(c, r, 0, TAU, 48, col, 1.0, false)
	else:
		_arc(self, c, r, col, 1.0, 48)
	# hit counter pips
	var hits: int = int(st.get("hits", 1))
	if hits > 1:
		for k in range(hits):
			var pr := Rect2(WX - 3 * hits + 6 * k, CY + 6, 4, 4)
			if not Art.is_a():
				# keep a gap of at least 2px between the grown outlines
				var step_px: float = 6.0 + 2.0 * float(Art.ow() - 1) + (2.0 if not Art.chunky() else 0.0)
				pr = Rect2(roundf(WX - step_px * float(hits) * 0.5 + step_px * k + (step_px - 4.0) * 0.5), CY + 6 + float(Art.ow() - 1), 4, 4)
			_box(pr, Art.SAGE if k < ring_hits.size() else Art.CREAM)

func _draw_pendulum() -> void:
	var st: Dictionary = current_step()
	var tex: Texture2D = _item_tex(str(st.get("item", "paw")))
	# rail + hook
	_box(Rect2(WX - 50, PIVOT.y - 4, 100, 4 if Art.is_a() else 5), Art.OAK)
	var top: float = _dish_top()
	if phase == "step":
		# center guide
		var gx: float = drop_target_x()
		for y in range(int(PIVOT.y) + 6, int(top) - 2, 4 if not Art.chunky() else 5):
			_dot(Rect2(gx, y, 1, 2), Color(Art.SAGE_DARK, 0.55))
		var tw: float = R.DROP_PERFECT_PX * widen
		if not Art.is_a():
			draw_rect(Rect2(gx - tw, top - 1, tw * 2.0 + 1.0, 2).grow(1), Art.OUTLINE)
		draw_rect(Rect2(gx - tw, top - 1, tw * 2.0 + 1.0, 2), Art.SAGE)
		draw_rect(Rect2(gx - 1, top - 3, 3, 1) if Art.is_a() else Rect2(gx - 1, top - 4, 3, 2), Art.SAGE_DARK)
	if tex == null:
		return
	if drop_falling:
		draw_texture(tex, (drop_pos - tex.get_size() * 0.5).round())
	elif phase == "step":
		var p: Vector2 = _pendulum_pos()
		var piv := Vector2(drop_target_x(), PIVOT.y)
		var steps_n: int = 8
		for k in range(steps_n):
			var q: Vector2 = piv.lerp(p, float(k) / float(steps_n))
			_dot(Rect2(q.round(), Vector2(1, 1)), Art.OUTLINE)
		draw_texture(tex, (p - tex.get_size() * 0.5).round())

# ------------------------------------------------------------------ background

func _paint_background() -> ImageTexture:
	if not Art.is_a():
		return BgStyled.paint()
	var img := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	img.fill(Art.WALL)
	# wall stripes
	for x in range(0, 320, 16):
		img.fill_rect(Rect2i(x, 0, 6, 112), Art.WALL_STRIPE)
	# wainscot band
	img.fill_rect(Rect2i(0, 84, 320, 28), Color("#EBCFAE"))
	img.fill_rect(Rect2i(0, 84, 320, 1), Art.OAK)
	for x in range(8, 320, 24):
		img.fill_rect(Rect2i(x, 88, 18, 20), Color("#E3C39F"))
	# window (right)
	var wr := Rect2i(222, 12, 64, 46)
	img.fill_rect(wr, Art.OUTLINE)
	img.fill_rect(wr.grow(-1), Art.OAK)
	img.fill_rect(wr.grow(-3), Art.SKY)
	img.fill_rect(Rect2i(wr.position.x + 3 + 29, wr.position.y + 3, 2, 40), Art.OAK)
	img.fill_rect(Rect2i(wr.position.x + 3, wr.position.y + 3 + 19, 58, 2), Art.OAK)
	img.fill_rect(Rect2i(232, 22, 12, 3), Color.WHITE)
	img.fill_rect(Rect2i(235, 20, 6, 2), Color.WHITE)
	img.fill_rect(Rect2i(262, 40, 10, 3), Color.WHITE)
	img.fill_rect(Rect2i(218, 58, 72, 4), Art.OAK_DARK)
	img.fill_rect(Rect2i(218, 58, 72, 1), Art.OUTLINE)
	# little plant on the sill
	img.fill_rect(Rect2i(276, 50, 8, 8), Color("#C9785A"))
	img.fill_rect(Rect2i(274, 44, 4, 6), Art.SAGE_DARK)
	img.fill_rect(Rect2i(279, 42, 4, 8), Art.SAGE)
	# shelf (left) with jars
	img.fill_rect(Rect2i(10, 40, 76, 4), Art.OAK)
	img.fill_rect(Rect2i(10, 44, 76, 1), Art.OUTLINE)
	var jars: Array = [[13, Color("#F2C14E")], [26, Color("#9FD3E0")], [39, Color("#E79AA0")], [52, Color("#C9A27A")], [65, Color("#8FBF9F")]]
	for j in jars:
		var x: int = j[0]
		img.fill_rect(Rect2i(x, 28, 11, 12), Art.OUTLINE)
		img.fill_rect(Rect2i(x + 1, 29, 9, 11), j[1])
		img.fill_rect(Rect2i(x + 2, 26, 7, 3), Art.OUTLINE)
		img.fill_rect(Rect2i(x + 3, 27, 5, 1), Art.OAK_LIGHT)
		img.fill_rect(Rect2i(x + 2, 31, 1, 6), Color(1, 1, 1, 0.6))
	# counter top surface + front
	img.fill_rect(Rect2i(0, 110, 320, 12), Art.OAK)
	img.fill_rect(Rect2i(0, 110, 320, 1), Art.OUTLINE)
	img.fill_rect(Rect2i(0, 111, 320, 2), Art.OAK_LIGHT)
	img.fill_rect(Rect2i(0, 122, 320, 1), Art.OUTLINE)
	img.fill_rect(Rect2i(0, 123, 320, 57), Art.OAK_DARK)
	for x in range(40, 320, 56):
		img.fill_rect(Rect2i(x, 130, 46, 42), Art.OUTLINE)
		img.fill_rect(Rect2i(x + 1, 131, 44, 40), Color("#B48862"))
		img.fill_rect(Rect2i(x + 1, 131, 44, 1), Color("#C79C74"))
	img.fill_rect(Rect2i(0, 123, 320, 2), Art.OAK_DEEP)
	# cake under a glass cloche (left end of the pass counter)
	img.fill_rect(Rect2i(12, 114, 44, 3), Art.OUTLINE)
	img.fill_rect(Rect2i(13, 114, 42, 2), Color("#F7EBDD"))
	img.fill_rect(Rect2i(22, 101, 24, 13), Art.OUTLINE)
	img.fill_rect(Rect2i(23, 102, 22, 12), Color("#F3D7A6"))
	img.fill_rect(Rect2i(23, 102, 22, 3), Color("#FFF3DC"))
	img.fill_rect(Rect2i(23, 107, 22, 1), Art.PINK)
	img.fill_rect(Rect2i(32, 98, 4, 4), Art.ROSE)
	for y in range(86, 114):
		var hw: int = int(round(20.0 * sqrt(clampf(1.0 - pow((114.0 - float(y)) / 28.0, 2.0), 0.0, 1.0))))
		img.set_pixel(34 - hw, y, Art.OUTLINE)
		img.set_pixel(34 + hw, y, Art.OUTLINE)
	img.fill_rect(Rect2i(30, 84, 9, 3), Art.OUTLINE)
	img.fill_rect(Rect2i(19, 92, 1, 10), Color(1, 1, 1, 0.8))
	img.fill_rect(Rect2i(21, 89, 1, 3), Color(1, 1, 1, 0.8))
	return ImageTexture.create_from_image(img)
