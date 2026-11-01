extends Node2D

## Purr-fect Timing: one order (recipe) played in the 320x180 play SubViewport.
## Logic and drawing for every step type (shot / needle / beat / oven) live here; the overlay
## (PTOverlay.gd) owns the window, pausing, input capture and rewards.
##
## Timing model (fair at any fps):
##   * every target is an analytic time on the order clock (PTClock), never "the frame where
##     the marker overlapped the zone".
##   * inputs arrive as input_press(t) / input_release(t) / input_oven(t) where t is the
##     clock time the overlay read while dispatching the event; the calibration offset is
##     applied here (judge.corrected).
##   * update() only resolves things that need no input (auto "ok" for passed beats, idle
##     helpers, overflow), so a low frame rate can delay a popup but never change a grade.

signal finished(result: Dictionary)
signal judged(j: String, step_index: int)
signal step_changed(index: int)

const PX := preload("res://Scripts/minigame_demos/purrfect_timing/PTPixel.gd")
const CAT2D_SCENE := preload("res://Scenes/Prototype3D/Cat2D.tscn")
const PIPE_SCRIPT := preload("res://Scripts/prototype3d/CatPixelPipeline.gd")

const W := 320.0
const H := 180.0
const COUNTER_Y := 128.0
const INTRO_SEC := 1.4
const OUTRO_SEC := 0.8
const SHOT_LOCK := 0.35
const SHOT_IDLE := 7.0
const NEEDLE_IDLE := 8.0
const NEEDLE_EARLY_FACTOR := 1.6
const OVEN_SCALE := 3.0
const OVEN_GRACE := 2.5
const COUNT_IN := 4
const BAR_X0 := 70.0
const BAR_X1 := 250.0
const BAR_Y := 141.0
const LANE_HIT_X := 84.0
const LANE_SPEED := 110.0
const LANE_Y := 146.0
const LANE_X1 := 300.0
const GAUGE_X := 198.0
const GAUGE_TOP := 26.0
const GAUGE_BOTTOM := 124.0
const OVEN_SLOT := Vector2(286, 32)
const OVEN_R := 13.0
const CAT_PX := 56
const CAT_FOOT_Y := 53.0
const CAT_SPOTS: Array[Vector2] = [Vector2(30, 131), Vector2(291, 131)]

var clock: RefCounted = null
var judge: RefCounted = null
var synth: Node = null
var hold_toggle: bool = false
var reduced_motion: bool = false

var recipe: Dictionary = {}
var steps: Array = []
var state: String = "idle"   # idle | intro | play | outro | result
var step_index: int = -1
var step: Dictionary = {}
var step_type: String = ""
var step_judged: int = 0
var result: Dictionary = {}
var t_order0: float = 0.0
var beat_period: float = 0.6

var intro_until: float = 0.0
var outro_until: float = 0.0
var step_t0: float = 0.0
var helper_note: String = ""

# shot / stamp
var shot_hits_left: int = 0
var shot_hits: Array = []        # {x, j, t}
var shot_sweep_t0: float = 0.0
var shot_lock_until: float = 0.0
var shot_last_act: float = 0.0
# needle
var nd_level: float = 0.0
var nd_holding: bool = false
var nd_hold_t0: float = 0.0
var nd_l0: float = 0.0
var nd_overflows: int = 0
var nd_last_act: float = 0.0
var nd_next_puff: float = 0.0
var nd_flash_until: float = 0.0
var nd_final_j: String = ""
# beat
var notes: Array = []            # {t, j, wob}
var beat_b0: int = 0
var beat_last_hit_t: float = -99.0
var beat_side: int = 1
var beat_hits: int = 0
# oven (back burner, parallel)
var oven: Dictionary = {}        # {active, t_start, t_done, collected, j, dinged, t_collect, nope_t, look}
var cookie_stamps: Array[String] = []

var popups: Array = []           # {t, pos, text, col, scale}
var markers: Array = []          # {t, pos, col, size, life}
var puffs: Array = []            # {t, pos, vel, r, life, col}

var _finished_emitted: bool = false
var _bg: Node2D
var _fg: Node2D
## B..F: shelf props are drawn by their own node so the halo / drop-shadow group can wrap them.
var _bgp: Node2D
## B..F: the play hint line is drawn by its own node, outside the E / F FX groups, so it only
## gets the shared text rule (no per-letter sticker halo / drop shadow).
var _txt: Node2D
## E / F: CanvasGroups that add the cream sticker halo / cocoa drop shadow around whole objects.
var _fx_fg: CanvasGroup
var _fx_bgp: CanvasGroup
var _fx_mat: ShaderMaterial

const FX_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 halo_col = vec4(1.0, 0.965, 0.918, 1.0);
uniform float halo_px = 0.0;
uniform vec4 shadow_col = vec4(0.169, 0.129, 0.161, 0.35);
uniform vec2 shadow_off = vec2(0.0, 0.0);

float a_at(vec2 uv) {
	return textureLod(screen_tex, uv, 0.0).a;
}

void fragment() {
	vec4 c = textureLod(screen_tex, SCREEN_UV, 0.0);
	if (c.a > 0.0001) { c.rgb /= c.a; }
	vec2 px = SCREEN_PIXEL_SIZE;
	vec4 under = vec4(0.0);
	if (shadow_off != vec2(0.0)) {
		float s = 0.0;
		for (int x = 0; x <= 1; x++) {
			for (int y = 0; y <= 1; y++) {
				if (x + y == 0) { continue; }
				vec2 o = vec2(float(x), float(y)) * clamp(shadow_off, vec2(-1.0), vec2(1.0));
				s = max(s, a_at(SCREEN_UV - o * px));
			}
		}
		if (s > 0.5) { under = shadow_col; }
	}
	if (halo_px > 0.0) {
		float h = 0.0;
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				h = max(h, a_at(SCREEN_UV + vec2(float(x), float(y)) * px));
			}
		}
		if (h > 0.5) { under = halo_col; }
	}
	float a = c.a + under.a * (1.0 - c.a);
	vec3 rgb = a > 0.0 ? (c.rgb * c.a + under.rgb * under.a * (1.0 - c.a)) / a : vec3(0.0);
	COLOR = vec4(rgb, a);
}
"""
var _cats: Array = []            # {sprite, cat, expr, expr_until, base}
var _last_beat_seen: int = -1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg = Node2D.new()
	_bg.name = "BG"
	_bg.z_index = -10
	add_child(_bg)
	_bg.draw.connect(func() -> void: _draw_bg(_bg))
	_fg = Node2D.new()
	_fg.name = "FG"
	_fg.z_index = 10
	add_child(_fg)
	_fg.draw.connect(func() -> void: _draw_fg(_fg))
	_bgp = Node2D.new()
	_bgp.name = "BGProps"
	_bgp.z_index = -9
	add_child(_bgp)
	_bgp.draw.connect(func() -> void: _draw_bg_props(_bgp))
	_txt = Node2D.new()
	_txt.name = "HintText"
	_txt.z_index = 11
	add_child(_txt)
	_txt.draw.connect(func() -> void: _draw_hint_layer(_txt))
	if not PX.legacy():
		apply_art_style()


# ============================================================== art style

## Re-wire the FX groups for the current PX style (live switch from the test panel).
## A / B / C / D: no groups (A is exactly the original node layout and draw order).
func apply_art_style() -> void:
	if _fg == null:
		return
	var halo: bool = bool(PX.S["halo"])
	var drop: bool = bool(PX.S["drop_shadow"])
	if halo or drop:
		if _fx_mat == null:
			var sh := Shader.new()
			sh.code = FX_SHADER
			_fx_mat = ShaderMaterial.new()
			_fx_mat.shader = sh
		_fx_mat.set_shader_parameter("halo_px", 1.0 if halo else 0.0)
		_fx_mat.set_shader_parameter("shadow_off", Vector2(1, 1) if drop else Vector2.ZERO)
		_fx_mat.set_shader_parameter("halo_col", PX.HALO_COL)
		_fx_mat.set_shader_parameter("shadow_col", PX.DROP_COL)
		if _fx_fg == null:
			_fx_fg = _make_fx_group("FXFront", 10)
			_fx_bgp = _make_fx_group("FXProps", -9)
		_reparent(_fg, _fx_fg, 0)
		_reparent(_bgp, _fx_bgp, 0)
	else:
		_reparent(_fg, self, 10)
		_reparent(_bgp, self, -9)
	_bg.queue_redraw()
	_bgp.queue_redraw()
	_fg.queue_redraw()
	_txt.queue_redraw()


func _make_fx_group(nm: String, z: int) -> CanvasGroup:
	var g := CanvasGroup.new()
	g.name = nm
	g.z_index = z
	g.fit_margin = 4.0
	g.clear_margin = 4.0
	g.material = _fx_mat
	g.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(g)
	return g


func _reparent(n: Node2D, to: Node, z: int) -> void:
	if n.get_parent() != to:
		n.get_parent().remove_child(n)
		to.add_child(n)
	n.z_index = z


# ============================================================== cats (decorative)

## Two chibi cats from Cat2D (public API only: apply_genome / set_pose / set_expression /
## set_pixel_art), rendered through the same pixel pipeline as in-game cats.
func setup_cats(genomes: Array) -> void:
	if not _cats.is_empty():
		for i in _cats.size():
			var c: Dictionary = _cats[i]
			var gg: Variant = genomes[i] if i < genomes.size() else {}
			(c["cat"] as Node).call("apply_genome", gg)
			(c["cat"] as Node).call("set_expression", &"open")
			c["expr"] = &"open"
			c["expr_until"] = 0.0
		return
	for i in 2:
		var host := Node.new()
		host.name = "CatHost%d" % i
		add_child(host)
		var vp := SubViewport.new()
		vp.name = "CatVP"
		vp.size = Vector2i(CAT_PX, CAT_PX)
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.gui_disable_input = true
		vp.msaa_2d = Viewport.MSAA_DISABLED
		vp.snap_2d_transforms_to_pixel = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		host.add_child(vp)
		var cat: Node2D = CAT2D_SCENE.instantiate()
		cat.set("pixel_art", true)
		cat.position = Vector2(CAT_PX / 2.0, CAT_FOOT_Y)
		cat.scale = Vector2.ONE * float(CAT_PX) / 76.8
		vp.add_child(cat)
		cat.call("set_pixel_art", true)
		var g: Variant = genomes[i] if i < genomes.size() else {}
		cat.call("apply_genome", g)
		cat.call("set_pose", &"sit")
		cat.call("set_facing_left", i == 1)
		cat.call("set_expression", &"open")
		var pipe: Node = PIPE_SCRIPT.new()
		pipe.call("setup", host, vp, cat)
		pipe.call("set_pixel", true)
		var spr := Sprite2D.new()
		spr.name = "CatSprite%d" % i
		spr.centered = false
		spr.texture = pipe.call("get_texture")
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var base: Vector2 = CAT_SPOTS[i] - Vector2(CAT_PX / 2.0, CAT_FOOT_Y)
		spr.position = base
		add_child(spr)
		_cats.append({"host": host, "sprite": spr, "cat": cat, "expr": &"open", "expr_until": 0.0, "base": base})


func _cat_expr(e: StringName, secs: float, only: int = -1) -> void:
	if clock == null:
		return
	for i in _cats.size():
		if only >= 0 and i != only:
			continue
		var c: Dictionary = _cats[i]
		c["expr_until"] = clock.now() + secs
		if c["expr"] != e:
			c["expr"] = e
			(c["cat"] as Node).call("set_expression", e)


func _update_cats(now: float) -> void:
	var ph: float = beat_phase(now)
	var b: int = floori(ph)
	var f: float = ph - float(b)
	for i in _cats.size():
		var c: Dictionary = _cats[i]
		# Bob: a 2px hop on every beat (the right cat answers on the off-beat in beat steps).
		var off: float = f
		if i == 1 and step_type == "beat" and state == "play":
			off = fmod(f + 0.5, 1.0)
		var hop: float = 0.0 if reduced_motion else roundf(2.0 * pow(maxf(0.0, 1.0 - off * 3.0), 2.0))
		if state == "idle":
			hop = 0.0
		(c["sprite"] as Sprite2D).position = (c["base"] as Vector2) - Vector2(0, hop)
		if state != "result" and float(c["expr_until"]) > 0.0 and now > float(c["expr_until"]):
			c["expr_until"] = 0.0
			c["expr"] = &"open"
			(c["cat"] as Node).call("set_expression", &"open")


# ============================================================== order flow

func start_order(p_recipe: Dictionary, p_clock: RefCounted, p_judge: RefCounted, p_hold_toggle: bool) -> void:
	recipe = p_recipe.duplicate(true)
	steps = (recipe.get("steps", []) as Array).duplicate(true)
	clock = p_clock
	judge = p_judge
	hold_toggle = p_hold_toggle
	judge.call("reset_score")
	beat_period = 60.0 / maxf(40.0, float(recipe.get("bpm", 90)))
	t_order0 = clock.now()
	oven = {}
	cookie_stamps.clear()
	popups.clear()
	markers.clear()
	puffs.clear()
	result = {}
	_finished_emitted = false
	_last_beat_seen = -1
	if synth != null:
		synth.set("beat_t0", t_order0)
		synth.set("beat_period", beat_period)
		synth.set("metronome_on", true)
	_begin_step(0)


func beat_phase(now: float) -> float:
	return (now - t_order0) / beat_period


func _begin_step(i: int) -> void:
	var now: float = clock.now()
	helper_note = ""
	if i >= steps.size():
		if not oven.is_empty() and not bool(oven.get("collected", false)):
			if step_type != "oven_wait":
				var tea: bool = str(oven.get("look", "")) == "tea"
				steps.append({"type": "oven_wait", "label": "POUR THE TEA" if tea else "TAKE OUT THE TRAY"})
			else:
				return
		else:
			_finish()
			return
	step_index = i
	step = steps[i]
	step_type = str(step.get("type", ""))
	step_judged = 0
	step_t0 = now
	state = "intro"
	intro_until = now + (0.9 if step_type == "oven_wait" else INTRO_SEC)
	match step_type:
		"shot":
			shot_hits_left = int(step.get("hits", 1))
			shot_hits = []
			shot_sweep_t0 = intro_until
			shot_lock_until = 0.0
			shot_last_act = intro_until
		"needle":
			nd_level = 0.0
			nd_holding = false
			nd_l0 = 0.0
			nd_overflows = 0
			nd_last_act = intro_until
			nd_final_j = ""
			nd_flash_until = 0.0
		"beat":
			notes = []
			beat_hits = 0
			beat_last_hit_t = -99.0
			beat_b0 = ceili((intro_until - 0.25 - t_order0) / beat_period)
			var pat: String = str(step.get("pattern", "x.x.x.x."))
			for k in pat.length():
				if pat[k] == "x":
					var b: float = float(beat_b0 + COUNT_IN) + float(k) * 0.5
					notes.append({"t": t_order0 + b * beat_period, "j": "", "wob": Vector2.ZERO})
		"oven":
			intro_until = now + 1.0
			oven = {"active": true, "t_start": intro_until, "t_done": intro_until + float(step.get("duration", 8.0)),
				"collected": false, "j": "", "dinged": false, "t_collect": 0.0, "nope_t": -9.0,
				"look": str(step.get("look", "cookie"))}
	if synth != null:
		synth.set("metronome_gain", 1.0 if step_type == "beat" else 0.4)
	step_changed.emit(i)


func _complete_step(now: float) -> void:
	state = "outro"
	outro_until = now + (0.25 if step_type == "oven" else OUTRO_SEC)


func _finish() -> void:
	state = "result"
	step_type = "result"
	var price: int = int(recipe.get("price", 5))
	var g: String = judge.call("grade")
	result = {
		"recipe_id": recipe.get("id", ""),
		"name": recipe.get("name", ""),
		"grade": g,
		"title": judge.call("grade_title", g),
		"counts": (judge.get("counts") as Dictionary).duplicate(),
		"best_combo": judge.get("best_combo"),
		"chain": judge.get("chain"),
		"chain_bonus": judge.call("chain_bonus"),
		"base_money": judge.call("base_money", price),
		"money": judge.call("money", price),
		"accuracy": judge.call("accuracy"),
	}
	if synth != null:
		synth.set("metronome_on", false)
		synth.call("chime", "ding")
	for c in _cats:
		c["expr"] = &"happy"
		(c["cat"] as Node).call("set_expression", &"happy")
	if not _finished_emitted:
		_finished_emitted = true
		finished.emit(result)


## Pause / park: a held needle simply stops where it is (no judgement).
func suspend_holds() -> void:
	if step_type == "needle" and nd_holding and clock != null:
		nd_level = clampf(needle_level_at(clock.now()), 0.0, 0.97)
		nd_holding = false


## Order served or abandoned: go quiet (draws nothing, ignores input).
func stop() -> void:
	state = "idle"
	step_type = ""
	popups.clear()
	markers.clear()
	puffs.clear()
	if _bg != null:
		_bg.queue_redraw()
		_fg.queue_redraw()
		_txt.queue_redraw()


## Restart the current step (used when a parked order resumes). Earlier steps keep their
## judgements; the current step's partial judgements are dropped so nothing double-counts.
func restart_current_step() -> void:
	if state == "result" or step_index < 0:
		return
	if step_judged > 0:
		judge.call("drop_tag", "step%d" % step_index)
	step_judged = 0
	if step_type == "oven":
		# the oven was already started; just continue with the next step
		_begin_step(step_index + 1)
		return
	_begin_step(step_index)


# ============================================================== input

func input_press(t_raw: float) -> void:
	if state != "play" or judge == null:
		return
	var t: float = judge.call("corrected", t_raw)
	match step_type:
		"shot":
			_shot_press(t)
		"needle":
			if hold_toggle and nd_holding:
				_needle_release(t)
			else:
				_needle_start(t_raw)
		"beat":
			_beat_press(t)
		"oven_wait":
			input_oven(t_raw)


func input_release(t_raw: float) -> void:
	if hold_toggle or state != "play" or step_type != "needle" or not nd_holding:
		return
	_needle_release(judge.call("corrected", t_raw))


func input_oven(t_raw: float) -> void:
	if oven.is_empty() or bool(oven["collected"]) or judge == null:
		return
	if clock.now() < float(oven["t_start"]):
		return
	var t: float = judge.call("corrected", t_raw)
	var delta: float = t - float(oven["t_done"])
	if delta < -float(judge.call("good_window", OVEN_SCALE)):
		oven["nope_t"] = clock.now()
		_popup(_oven_center() + Vector2(0, 18), "NOT YET!", PX.OAK, 1)
		return
	_collect_oven(judge.call("judge_delta", delta, OVEN_SCALE), false)


## True when a click at play-space position p should go to the oven ring.
func is_oven_hit(p: Vector2) -> bool:
	if oven.is_empty() or bool(oven["collected"]):
		return false
	if step_type == "oven_wait" and state == "play":
		return true
	return p.distance_to(OVEN_SLOT) <= OVEN_R + 7.0


func _oven_center() -> Vector2:
	if step_type == "oven_wait":
		return Vector2(160, 96) if str(oven.get("look", "")) == "tea" else Vector2(160, 84)
	return OVEN_SLOT


func _collect_oven(j: String, auto: bool) -> void:
	oven["collected"] = true
	oven["j"] = j
	oven["t_collect"] = clock.now()
	if auto:
		helper_note = "THE CAT TOOK THEM OUT!"
	_record(j, _oven_center() + Vector2(0, -4), true)
	for k in 4:
		_spawn_puff(_oven_center() + Vector2(randf_range(-8, 8), -6), Vector2(randf_range(-6, 6), -18), 4.0, PX.MILK)
	if step_type == "oven_wait" and state == "play":
		_complete_step(clock.now())


# ---------------------------------------------------------------- shot / stamp

func shot_marker(t: float) -> float:
	var u: float = maxf(0.0, (t - shot_sweep_t0) * float(step.get("speed", 1.0)))
	var m: float = fmod(u, 2.0)
	return m if m <= 1.0 else 2.0 - m


## Nearest zone crossing (seconds) to clock time t, plus the one after `after` (for bots).
func _shot_crossings_near(t: float) -> Array:
	var sp: float = float(step.get("speed", 1.0))
	var c: float = float(step.get("zone", 0.5))
	var u: float = (t - shot_sweep_t0) * sp
	var k0: int = floori(u / 2.0)
	var out: Array = []
	for k in range(k0 - 1, k0 + 3):
		for uc in [c + 2.0 * k, 2.0 - c + 2.0 * k]:
			if uc >= 0.0:
				out.append(shot_sweep_t0 + uc / sp)
	out.sort()
	return out


func _shot_press(t: float) -> void:
	if shot_hits_left <= 0 or t < shot_lock_until:
		return
	var best: float = INF
	for ct in _shot_crossings_near(t):
		if absf(t - ct) < absf(best):
			best = t - ct
	var j: String = judge.call("judge_delta", best)
	var x: float = lerpf(BAR_X0, BAR_X1, shot_marker(t))
	_shot_hit(j, x, t)


func _shot_hit(j: String, x: float, t: float) -> void:
	shot_hits.append({"x": x, "j": j, "t": clock.now()})
	if str(step.get("look", "")) == "stamp":
		cookie_stamps.append(j)
	shot_hits_left -= 1
	shot_lock_until = t + SHOT_LOCK
	shot_last_act = clock.now()
	var pop_at := Vector2(160, 20) if str(step.get("look", "")) != "stamp" else _cookie_pos(shot_hits.size() - 1) + Vector2(0, -26)
	_record(j, pop_at, false)
	markers.append({"t": clock.now(), "pos": Vector2(x, BAR_Y + 14), "col": PX.judgement_color(j), "size": 2.0, "life": 99.0})
	if str(step.get("look", "")) == "stamp":
		_spawn_puff(_cookie_pos(shot_hits.size() - 1) + Vector2(0, -6), Vector2(0, -10), 3.0, PX.FOAM)
	elif str(step.get("look", "")) == "sift":
		for k in 4:
			_spawn_puff(Vector2(160 + randf_range(-14, 14), 80), Vector2(randf_range(-3, 3), 14), 2.0, PX.MATCHA)
	else:
		for k in 2:
			_spawn_puff(Vector2(160 + randf_range(-6, 6), 104), Vector2(randf_range(-5, 5), -16), 3.0, PX.MILK)
	if shot_hits_left <= 0:
		_complete_step(clock.now())


func _cookie_pos(i: int) -> Vector2:
	var n: int = maxi(1, int(step.get("hits", 3))) if step_type == "shot" else maxi(3, cookie_stamps.size())
	var x: float = 160.0 + (float(i) - float(n - 1) / 2.0) * 36.0
	return Vector2(x, 117)


# ---------------------------------------------------------------- needle

func needle_level_at(t: float) -> float:
	if not nd_holding:
		return nd_level
	return nd_l0 + maxf(0.0, t - nd_hold_t0) * float(step.get("rate", 0.5))


func _needle_start(t: float) -> void:
	if nd_holding:
		return
	nd_holding = true
	nd_hold_t0 = minf(t, clock.now())
	nd_l0 = nd_level
	nd_last_act = clock.now()


func _needle_release(t: float) -> void:
	var rate: float = float(step.get("rate", 0.5))
	var l: float = nd_l0 + maxf(0.0, t - nd_hold_t0) * rate
	nd_holding = false
	nd_level = minf(l, 1.0)
	nd_last_act = clock.now()
	var delta: float = (l - float(step.get("zone", 0.7))) / rate
	if delta < -float(judge.call("good_window")) * NEEDLE_EARLY_FACTOR:
		_popup(Vector2(160, 20), "KEEP GOING!", PX.OAK_DARK, 1)
		return
	var j: String = judge.call("judge_delta", delta)
	nd_final_j = j
	_record(j, Vector2(160, 20), false)
	_complete_step(clock.now())


func _needle_overflow(now: float) -> void:
	nd_holding = false
	nd_level = 0.0
	nd_overflows += 1
	nd_flash_until = now + 0.9
	nd_last_act = now
	for k in 5:
		_spawn_puff(Vector2(146 + randf_range(-10, 10), 84), Vector2(randf_range(-14, 14), -20), 4.0, PX.MILK)
	if synth != null:
		synth.call("chime", "puff")
	_cat_expr(&"surprised", 0.8)
	if nd_overflows >= 2:
		helper_note = "FOAMY BUT CUTE!"
		nd_final_j = "ok"
		_record("ok", Vector2(160, 20), false)
		_complete_step(now)
	else:
		_popup(Vector2(160, 20), "TOO FOAMY! AGAIN", PX.ALERT, 1)


# ---------------------------------------------------------------- beat

func _beat_press(t: float) -> void:
	var gw: float = judge.call("good_window")
	var best: int = -1
	var bd: float = INF
	for i in notes.size():
		var n: Dictionary = notes[i]
		if str(n["j"]) != "":
			continue
		var d: float = absf(t - float(n["t"]))
		if d <= gw and d < bd:
			bd = d
			best = i
	if best < 0:
		_spawn_puff(Vector2(LANE_HIT_X, LANE_Y - 6), Vector2(0, -8), 2.0, PX.FOAM)
		return
	var n2: Dictionary = notes[best]
	var j: String = judge.call("judge_delta", t - float(n2["t"]))
	_beat_judged(best, j)


func _beat_judged(i: int, j: String) -> void:
	var n: Dictionary = notes[i]
	n["j"] = j
	if j == "ok":
		n["wob"] = Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	beat_hits += 1
	beat_last_hit_t = clock.now()
	beat_side = -beat_side
	_record(j, Vector2(LANE_HIT_X + 6, LANE_Y - 30), false, true)
	markers.append({"t": clock.now(), "pos": Vector2(LANE_HIT_X, LANE_Y - 1), "col": PX.judgement_color(j), "size": 3.0, "life": 0.7})
	var look: String = str(step.get("look", ""))
	if look == "whisk" or look == "pour":
		_spawn_puff(Vector2(160 + randf_range(-10, 10), 98), Vector2(randf_range(-4, 4), -12), 2.5, PX.MILK if look == "pour" else Color("#DDEBC0"))


func _beat_all_judged() -> bool:
	for n in notes:
		if str(n["j"]) == "":
			return false
	return true


# ---------------------------------------------------------------- shared

func _record(j: String, pop_pos: Vector2, oven_hit: bool, small: bool = false) -> void:
	judge.call("add", j, "oven" if oven_hit else "step%d" % step_index)
	if not oven_hit:
		step_judged += 1
	var txt: String = PX.judgement_text(j)
	_popup(pop_pos, txt, PX.judgement_color(j), 1 if (small or j == "ok") else 2)
	if synth != null:
		synth.call("chime", j)
	match j:
		"purrfect":
			_cat_expr(&"happy", 0.7)
		"good":
			_cat_expr(&"smug", 0.5)
		_:
			_cat_expr(&"sleepy", 0.5)
	judged.emit(j, step_index)


func _popup(pos: Vector2, text: String, col: Color, scale: int) -> void:
	var i: int = popups.size() - 1
	while i >= 0:
		if (popups[i]["pos"] as Vector2).distance_to(pos) < 4.0:
			popups.remove_at(i)
		i -= 1
	popups.append({"t": clock.now(), "pos": pos, "text": text, "col": col, "scale": scale})
	if popups.size() > 6:
		popups.pop_front()


func _spawn_puff(pos: Vector2, vel: Vector2, r: float, col: Color) -> void:
	puffs.append({"t": clock.now(), "pos": pos, "vel": vel, "r": r, "life": 0.9, "col": col})
	if puffs.size() > 40:
		puffs.pop_front()


# ============================================================== update

func _process(_delta: float) -> void:
	if clock == null:
		return
	update()


func update() -> void:
	if clock == null or state == "idle":
		return
	var now: float = clock.now()
	if state == "intro" and now >= intro_until:
		state = "play"
		if step_type == "oven":
			_complete_step(now)
	if state == "play":
		match step_type:
			"shot":
				if now - shot_last_act > SHOT_IDLE and shot_hits_left > 0:
					helper_note = "THE CAT HELPED!"
					_shot_hit("ok", lerpf(BAR_X0, BAR_X1, float(step.get("zone", 0.5))), now)
			"needle":
				if nd_holding:
					nd_level = needle_level_at(now)
					if nd_level >= 1.0:
						_needle_overflow(now)
					elif now >= nd_next_puff:
						nd_next_puff = now + 0.14
						_spawn_puff(Vector2(150 + randf_range(-5, 5), 88), Vector2(randf_range(-6, 6), -22), 2.5 + nd_level * 2.0, PX.MILK)
				elif now - nd_last_act > NEEDLE_IDLE:
					helper_note = "THE CAT HELPED!"
					nd_final_j = "ok"
					nd_level = float(step.get("zone", 0.7))
					_record("ok", Vector2(160, 20), false)
					_complete_step(now)
			"beat":
				var gw: float = judge.call("good_window")
				for i in notes.size():
					var n: Dictionary = notes[i]
					if str(n["j"]) == "" and now > float(n["t"]) + gw:
						_beat_judged(i, "ok")
				if _beat_all_judged():
					_complete_step(now)
	# oven back burner
	if not oven.is_empty() and not bool(oven["collected"]):
		var td: float = float(oven["t_done"])
		if not bool(oven["dinged"]) and now >= td - float(judge.call("purrfect_window", OVEN_SCALE)):
			oven["dinged"] = true
			if synth != null:
				synth.call("chime", "ding")
			_cat_expr(&"surprised", 0.6, 1)
		if now > td + float(judge.call("good_window", OVEN_SCALE)) + OVEN_GRACE:
			_collect_oven("ok", true)
	if state == "outro" and now >= outro_until:
		_begin_step(step_index + 1)
	# beat-synced flourishes
	var b: int = floori(beat_phase(now))
	if b != _last_beat_seen:
		_last_beat_seen = b
		if state != "result" and not reduced_motion and b % 2 == 0:
			_spawn_puff(Vector2(160 + randf_range(-3, 3), 22), Vector2(randf_range(-3, 3), -6), 1.5, PX.MILK)
	_update_cats(now)
	var pi: int = popups.size() - 1
	while pi >= 0:
		if now - float(popups[pi]["t"]) > 0.9:
			popups.remove_at(pi)
		pi -= 1
	var mi: int = markers.size() - 1
	while mi >= 0:
		if now - float(markers[mi]["t"]) > float(markers[mi]["life"]):
			markers.remove_at(mi)
		mi -= 1
	var fi: int = puffs.size() - 1
	while fi >= 0:
		if now - float(puffs[fi]["t"]) > float(puffs[fi]["life"]):
			puffs.remove_at(fi)
		fi -= 1
	if step_type != "shot":
		# shot hit markers persist for their step only
		var k: int = markers.size() - 1
		while k >= 0:
			if float(markers[k]["life"]) > 50.0:
				markers.remove_at(k)
			k -= 1
	_bg.queue_redraw()
	_fg.queue_redraw()
	_txt.queue_redraw()


# ============================================================== bot hooks (probe / capture)

## Upcoming ideal inputs: [{kind: "press"|"release"|"oven", t: float, start: bool}].
## `start` entries are "begin holding now" and take no timing offset.
func bot_query() -> Array:
	var out: Array = []
	if clock == null:
		return out
	var now: float = clock.now()
	if state == "play":
		match step_type:
			"shot":
				if shot_hits_left > 0:
					var from: float = maxf(now, shot_lock_until) + 0.3
					for ct in _shot_crossings_near(from):
						if ct >= from:
							out.append({"kind": "press", "t": ct, "start": false})
							break
			"needle":
				if not nd_holding:
					out.append({"kind": "press", "t": now, "start": true})
				else:
					var tt: float = nd_hold_t0 + (float(step.get("zone", 0.7)) - nd_l0) / float(step.get("rate", 0.5))
					out.append({"kind": "press" if hold_toggle else "release", "t": tt, "start": false})
			"beat":
				for n in notes:
					if str(n["j"]) == "":
						out.append({"kind": "press", "t": float(n["t"]), "start": false})
						break
	if not oven.is_empty() and not bool(oven["collected"]) and state != "result":
		out.append({"kind": "oven", "t": float(oven["t_done"]), "start": false})
	return out


# ============================================================== drawing

func _draw_bg(ci: CanvasItem) -> void:
	if not PX.legacy():
		_draw_bg_styled(ci)
		return
	ci.draw_rect(Rect2(0, 0, W, H), PX.WALL)
	var row: int = 0
	var y: float = 20.0
	while y < COUNTER_Y - 4:
		var x: float = 6.0 + (6.0 if row % 2 == 1 else 0.0)
		while x < W:
			ci.draw_rect(Rect2(x, y, 1, 1), PX.WALL_DOT)
			ci.draw_rect(Rect2(x + 1, y - 1, 1, 1), PX.WALL_DOT)
			ci.draw_rect(Rect2(x - 1, y - 1, 1, 1), PX.WALL_DOT)
			x += 12.0
		y += 11.0
		row += 1
	_draw_shelves(ci)
	# counter
	ci.draw_rect(Rect2(0, COUNTER_Y - 1, W, 1), PX.OUTLINE)
	ci.draw_rect(Rect2(0, COUNTER_Y, W, 6), PX.OAK)
	ci.draw_rect(Rect2(0, COUNTER_Y, W, 1), Color("#DDBB93"))
	ci.draw_rect(Rect2(0, COUNTER_Y + 6, W, 1), PX.OUTLINE)
	ci.draw_rect(Rect2(0, COUNTER_Y + 7, W, H - COUNTER_Y - 7), PX.OAK_DARK)
	var px: float = 40.0
	while px < W:
		ci.draw_rect(Rect2(px, COUNTER_Y + 7, 1, H - COUNTER_Y - 7), Color("#94693F"))
		px += 64.0


## B..F background: wall + counter with outline_px edges (chunky: 2x2 wall motif, 2px grain).
func _draw_bg_styled(ci: CanvasItem) -> void:
	var ck: bool = PX.chunky()
	var o: float = float(PX.ow())
	ci.draw_rect(Rect2(0, 0, W, H), PX.WALL)
	var row: int = 0
	var y: float = 20.0
	while y < COUNTER_Y - 6:
		var x: float = 6.0 + (6.0 if row % 2 == 1 else 0.0)
		while x < W:
			if ck:
				ci.draw_rect(Rect2(x - 1, y - 1, 2, 2), PX.WALL_DOT)
			else:
				ci.draw_rect(Rect2(x, y, 1, 1), PX.WALL_DOT)
				ci.draw_rect(Rect2(x + 1, y - 1, 1, 1), PX.WALL_DOT)
				ci.draw_rect(Rect2(x - 1, y - 1, 1, 1), PX.WALL_DOT)
			x += 12.0
		y += 11.0
		row += 1
	# counter
	ci.draw_rect(Rect2(0, COUNTER_Y - o, W, o), PX.OUTLINE)
	ci.draw_rect(Rect2(0, COUNTER_Y, W, 6), PX.OAK)
	ci.draw_rect(Rect2(0, COUNTER_Y, W, 2 if ck else 1), PX.rim_of(PX.OAK) if bool(PX.S["rim_highlight"]) else Color("#DDBB93"))
	if bool(PX.S["cel_shade"]):
		ci.draw_rect(Rect2(0, COUNTER_Y + 4, W, 2), PX.shade_of(PX.OAK))
	ci.draw_rect(Rect2(0, COUNTER_Y + 6, W, o), PX.OUTLINE)
	ci.draw_rect(Rect2(0, COUNTER_Y + 6 + o, W, H - COUNTER_Y - 6 - o), PX.OAK_DARK)
	var px: float = 40.0
	while px < W:
		ci.draw_rect(Rect2(px, COUNTER_Y + 6 + o, 2 if ck else 1, H - COUNTER_Y - 6 - o), Color("#94693F"))
		px += 64.0


## B..F: shelves + jars on their own node (so E / F can halo / shadow them).
func _draw_bg_props(ci: CanvasItem) -> void:
	if PX.legacy():
		return
	_draw_shelves(ci)


func _draw_shelves(ci: CanvasItem) -> void:
	if not PX.legacy():
		var ck: bool = PX.chunky()
		for sx in [8.0, 254.0]:
			var sy: float = 64.0 if sx < 100.0 else 72.0
			PX.box(ci, Rect2(sx + 6, sy - 12, 9, 12), PX.SAGE)
			PX.box(ci, Rect2(sx + 19, sy - 9, 10, 9), PX.HONEY_LIGHT)
			PX.box(ci, Rect2(sx + 33, sy - 14, 8, 14), PX.PINK)
			PX.box(ci, Rect2(sx + 45, sy - 8, 8, 8), PX.MILK)
			if ck:
				# jar lids: one chunky 2px band per jar instead of nothing
				ci.draw_rect(Rect2(sx + 7, sy - 11, 7, 2), PX.SAGE_DARK)
				ci.draw_rect(Rect2(sx + 34, sy - 13, 6, 2), Color("#D9918B"))
			PX.box(ci, Rect2(sx - 1, sy - 1, 60, 5), PX.OAK_DARK)
		return
	for sx in [8.0, 254.0]:
		var sy: float = 64.0 if sx < 100.0 else 72.0
		ci.draw_rect(Rect2(sx, sy, 58, 3), PX.OAK_DARK)
		ci.draw_rect(Rect2(sx, sy + 3, 58, 1), PX.OUTLINE)
		PX.box(ci, Rect2(sx + 6, sy - 12, 9, 12), PX.SAGE)
		PX.box(ci, Rect2(sx + 19, sy - 9, 10, 9), PX.HONEY_LIGHT)
		PX.box(ci, Rect2(sx + 33, sy - 14, 8, 14), PX.PINK)
		PX.box(ci, Rect2(sx + 45, sy - 8, 8, 8), PX.MILK)


func _draw_fg(ci: CanvasItem) -> void:
	if clock == null or state == "idle":
		return
	var now: float = clock.now()
	PX.fx_wrapped = _fx_fg != null and _fg.get_parent() == _fx_fg
	if state != "result":
		match step_type:
			"shot":
				match str(step.get("look", "")):
					"stamp":
						_draw_stamp_station(ci, now)
					"sift":
						_draw_sift_station(ci, now)
					_:
						_draw_espresso_station(ci, now)
				_draw_timing_bar(ci, now)
			"needle":
				_draw_needle_station(ci, now)
			"beat":
				_draw_beat_station(ci, now)
				_draw_lane(ci, now)
			"oven", "oven_wait":
				_draw_big_oven(ci, now)
		if step_type != "oven_wait":
			_draw_oven_slot(ci, now)
		if PX.legacy():
			_draw_instruction(ci, now)
	for p in puffs:
		var age: float = now - float(p["t"])
		var k: float = age / float(p["life"])
		var pos: Vector2 = (p["pos"] as Vector2) + (p["vel"] as Vector2) * age
		PX.puff(ci, pos.round(), float(p["r"]) * (0.7 + k * 0.6), 1.0 - k, p["col"])
	for m in markers:
		var age2: float = now - float(m["t"])
		var a: float = 1.0 if float(m["life"]) > 50.0 else clampf(1.0 - age2 / float(m["life"]), 0.0, 1.0)
		var grow: float = 0.0 if float(m["life"]) > 50.0 else age2 * 3.0
		PX.paw(ci, (m["pos"] as Vector2).round() - Vector2(0, grow * 4.0), float(m["size"]), Color(m["col"], a), a > 0.5)
	_draw_top_bar(ci, now)
	for p in popups:
		var age3: float = now - float(p["t"])
		var rise: float = 0.0 if reduced_motion else minf(10.0, age3 * 30.0)
		var a3: float = clampf(1.0 - maxf(0.0, age3 - 0.5) / 0.4, 0.0, 1.0)
		var pos3: Vector2 = p["pos"]
		PX.text_outlined(ci, pos3.x, roundf(pos3.y - rise), str(p["text"]), Color(p["col"], a3), int(p["scale"]))
	if state == "intro":
		_draw_intro_banner(ci, now)
	if state == "result":
		_draw_result(ci, now)
	PX.fx_wrapped = false


## B..F: hint line + oven hint on the HintText node (never inside an FX group).
func _draw_hint_layer(ci: CanvasItem) -> void:
	if PX.legacy() or clock == null or state == "idle" or state == "result":
		return
	PX.fx_wrapped = false
	_draw_instruction(ci, clock.now())


func _draw_top_bar(ci: CanvasItem, now: float) -> void:
	ci.draw_rect(Rect2(0, 0, W, 13), PX.CREAM)
	if PX.legacy():
		ci.draw_rect(Rect2(0, 13, W, 1), PX.OAK)
	else:
		ci.draw_rect(Rect2(0, 13, W, PX.chrome_px()), PX.OUTLINE)
	PX.text(ci, Vector2(4, 3), str(recipe.get("name", "")).to_upper(), PX.OUTLINE)
	# step pips
	var real_steps: Array = []
	for s in steps:
		if str(s.get("type", "")) != "oven_wait":
			real_steps.append(s)
	var n: int = real_steps.size()
	var x0: float = 126.0
	if not PX.legacy():
		# bold title is wider: keep the pips clear of it
		x0 = maxf(x0, 4.0 + PX.text_width(str(recipe.get("name", "")).to_upper()) + 8.0)
	for i in n:
		var c := Vector2(x0 + i * 10.0, 6.5)
		if state == "result" or i < step_index:
			PX.paw(ci, c + Vector2(0, 1), 1.6, PX.HONEY, true)
		elif i == step_index:
			PX.disc(ci, c, 3.0, PX.SAGE)
		elif PX.chunky():
			PX.disc(ci, c, 1.5, PX.OAK, PX.OAK_DARK)
		else:
			ci.draw_circle(c, 2.0, PX.OAK)
	# metronome: 4 dots, the current beat lights up and swells
	if state != "result":
		var ph: float = beat_phase(now)
		var b: int = floori(ph)
		var f: float = ph - float(b)
		var mx: float = 178.0
		for k in 4:
			var on: bool = posmod(b, 4) == k
			var r: float = 1.5
			var col: Color = PX.OAK
			if on:
				r = 2.5 if f < 0.25 else 2.0
				col = PX.HONEY if k == 0 else PX.SAGE
			if PX.chunky():
				if on:
					PX.disc(ci, Vector2(mx + k * 8.0, 6.5), r - 0.5, col)
				else:
					ci.draw_rect(Rect2(mx + k * 8.0 - 1, 5.5, 2, 2), PX.OAK)
			else:
				ci.draw_circle(Vector2(mx + k * 8.0, 6.5), r, col)
	# purr chain chip
	var chain: int = int(judge.get("chain"))
	var label: String = "PURR %d" % chain
	var w: int = PX.text_width(label) + 13
	var cx: float = W - 4.0 - w
	if PX.legacy():
		PX.soft_box(ci, Rect2(cx, 1, w + 2, 11), PX.HONEY_LIGHT if chain > 0 else PX.WALL, PX.OAK_DARK)
	else:
		PX.chrome_box(ci, Rect2(cx, 2, w + 2, 10), PX.HONEY_LIGHT if chain > 0 else PX.WALL)
	PX.heart(ci, Vector2(cx + 3, 3), Color("#D9776E"), true)
	PX.text(ci, Vector2(cx + 12, 3), label, PX.OUTLINE)


func _draw_instruction(ci: CanvasItem, now: float) -> void:
	var t: String = ""
	match step_type:
		"shot":
			t = "CLICK OR SPACE WHEN THE PAW HITS THE HONEY"
		"needle":
			t = "CLICK TO START, CLICK AGAIN IN THE HONEY" if hold_toggle else "HOLD CLICK OR SPACE, LET GO IN THE HONEY"
		"beat":
			t = "TAP ON THE BEAT AS BEANS REACH THE PAW"
		"oven_wait":
			t = "CLICK THE TIMER WHEN IT DINGS"
		"oven":
			t = "THE OVEN BAKES WHILE YOU WORK"
	if helper_note != "" and state == "outro":
		t = helper_note
	var y: float = 166.0 if step_type != "beat" else 167.0
	PX.text_centered(ci, W / 2.0, y, t, PX.CREAM, 1, true)
	if not oven.is_empty() and not bool(oven["collected"]) and step_type != "oven_wait" and now >= float(oven["t_start"]):
		var td: float = float(oven["t_done"])
		if now >= td - float(judge.call("good_window", OVEN_SCALE)):
			var hint: String = "CLICK ME!" if fmod(now, 1.0) < 0.5 else "OR PRESS O"
			PX.text_outlined(ci, OVEN_SLOT.x - 46, OVEN_SLOT.y - 3, hint, PX.HONEY, 1)


func _draw_intro_banner(ci: CanvasItem, now: float) -> void:
	var dur: float = 0.9 if step_type == "oven_wait" else INTRO_SEC
	var k: float = clampf(1.0 - (intro_until - now) / dur, 0.0, 1.0)
	var slide: float = 0.0
	if not reduced_motion:
		slide = (1.0 - minf(1.0, k * 4.0))
		slide = slide * slide * 120.0
	var a: float = clampf((1.0 - k) * 6.0, 0.0, 1.0)
	var y: float = 50.0
	var bl: float = float(PX.ow())
	ci.draw_rect(Rect2(0, y - bl, W, bl), Color(PX.OAK_DARK if PX.legacy() else PX.OUTLINE, a))
	ci.draw_rect(Rect2(0, y, W, 36), Color(PX.CREAM, 0.96 * a))
	ci.draw_rect(Rect2(0, y + 36, W, bl), Color(PX.OAK_DARK if PX.legacy() else PX.OUTLINE, a))
	var n: int = 0
	for s in steps:
		if str(s.get("type", "")) != "oven_wait":
			n += 1
	var top: String = "STEP %d OF %d" % [mini(step_index + 1, n), n] if step_type != "oven_wait" else "LAST BIT"
	PX.text_centered(ci, W / 2.0 + slide, y + 5, top, Color(PX.OAK_DARK, a))
	PX.text_outlined(ci, W / 2.0 + slide, y + 16, str(step.get("label", "")), Color(PX.HONEY, a), 2)
	PX.paw(ci, Vector2(30 + slide, y + 20), 4.0, Color(PX.SAGE, a), a > 0.5)
	PX.paw(ci, Vector2(290 + slide, y + 20), 4.0, Color(PX.SAGE, a), a > 0.5)


# ---------------------------------------------------------------- stations

func _draw_espresso_station(ci: CanvasItem, now: float) -> void:
	# machine
	PX.soft_box(ci, Rect2(122, 26, 76, 64), PX.SAGE)
	ci.draw_rect(Rect2(123, 27, 74, 6), PX.SAGE_DARK)
	PX.box(ci, Rect2(132, 36, 56, 20), PX.CREAM)
	PX.disc(ci, Vector2(146, 46), 6.0, PX.MILK)
	ci.draw_line(Vector2(146, 46), Vector2(146, 46) + Vector2.from_angle(-PI / 2 + sin(now * 2.0) * 0.6) * 5.0, PX.OUTLINE, -1.0 if PX.legacy() else PX.lw())
	PX.disc(ci, Vector2(172, 46), 3.0, PX.HONEY)
	if PX.legacy():
		ci.draw_rect(Rect2(180, 42, 3, 9), PX.OAK)
	else:
		PX.box(ci, Rect2(179, 41, 5, 11), PX.OAK)
	# cups on top
	PX.box(ci, Rect2(128, 19, 9, 8), PX.MILK)
	PX.box(ci, Rect2(140, 19, 9, 8), PX.PINK)
	PX.box(ci, Rect2(175, 19, 9, 8), PX.MILK)
	# group head + portafilter
	PX.box(ci, Rect2(150, 89, 20, 6), PX.STEEL_DARK)
	PX.box(ci, Rect2(168, 90, 22, 4), PX.OUTLINE, PX.OUTLINE)
	# drip tray
	PX.box(ci, Rect2(132, 124, 56, 5), PX.STEEL_DARK)
	# cup
	var cup := Rect2(146, 104, 28, 21)
	var hits: int = shot_hits.size()
	var total: int = maxi(1, int(step.get("hits", 1)))
	var pouring: bool = hits > 0 and now - float(shot_hits[hits - 1]["t"]) < 0.7
	if pouring:
		ci.draw_rect(Rect2(158, 95, 4, cup.position.y - 95 + 4), PX.COFFEE)
	PX.handle(ci, Vector2(176, 113), 5.0, -PI / 2, PI / 2, 10, 3.0, PX.MILK, 1.0)
	PX.box(ci, cup, PX.MILK)
	var fill_k: float = float(hits) / float(total)
	if pouring:
		fill_k = (float(hits - 1) + clampf((now - float(shot_hits[hits - 1]["t"])) / 0.6, 0.0, 1.0)) / float(total)
	var fh: float = roundf(17.0 * fill_k)
	if fh > 0:
		ci.draw_rect(Rect2(cup.position.x + 1, cup.end.y - 1 - fh, cup.size.x - 2, fh), PX.COFFEE)
		ci.draw_rect(Rect2(cup.position.x + 1, cup.end.y - 1 - fh, cup.size.x - 2, 2), PX.CREMA)
	ci.draw_rect(Rect2(cup.position.x + 3, cup.position.y + 6, 2, 5), Color(PX.FOAM, 0.9))


func _draw_cookie_tray(ci: CanvasItem, n: int) -> void:
	PX.soft_box(ci, Rect2(96, 106, 128, 22), PX.STEEL)
	ci.draw_rect(Rect2(98, 108, 124, PX.lw()), PX.MILK)
	for i in n:
		var c: Vector2 = _cookie_pos(i)
		PX.ellipse(ci, c, 15.0, 7.0, PX.DOUGH)
		ci.draw_rect(Rect2(c.x - 9, c.y - 4, 4, PX.lw()), Color(PX.MILK, 0.7))
		if i < cookie_stamps.size():
			match cookie_stamps[i]:
				"purrfect":
					PX.paw(ci, c + Vector2(0, 2), 2.6, PX.COFFEE, false)
				"good":
					PX.paw(ci, c + Vector2(1, 2), 2.6, PX.CREMA, false)
				_:
					PX.ellipse(ci, c + Vector2(0, 1), 5.0, 3.0, PX.DOUGH_DARK, PX.DOUGH_DARK)


func _draw_stamp_station(ci: CanvasItem, now: float) -> void:
	var n: int = int(step.get("hits", 3))
	_draw_cookie_tray(ci, n)
	# the paw stamper hovers over the next cookie and thumps down on a hit
	var idx: int = mini(shot_hits.size(), n - 1)
	var cp: Vector2 = _cookie_pos(idx)
	var drop: float = 0.0
	if shot_hits.size() > 0:
		var age: float = now - float(shot_hits[shot_hits.size() - 1]["t"])
		if age < 0.3:
			cp = _cookie_pos(shot_hits.size() - 1)
			drop = (1.0 - age / 0.3) * 18.0
	var top: float = 64.0 + drop + (0.0 if reduced_motion else roundf(sin(now * 6.0)))
	PX.box(ci, Rect2(cp.x - 2, top - 26, 5, 24), PX.OAK)
	PX.soft_box(ci, Rect2(cp.x - 9, top - 3, 19, 10), PX.HONEY)
	PX.paw(ci, Vector2(cp.x, top + 15), 3.0, PX.PINK, true)


func _draw_timing_bar(ci: CanvasItem, now: float) -> void:
	var sp: float = float(step.get("speed", 1.0))
	var zone: float = float(step.get("zone", 0.5))
	var bw: float = BAR_X1 - BAR_X0
	PX.box(ci, Rect2(BAR_X0 - 2, BAR_Y - 2, bw + 4, 12), PX.CREAM)
	var gw: float = float(judge.call("good_window")) * sp * bw
	var pw: float = float(judge.call("purrfect_window")) * sp * bw
	var zc: float = BAR_X0 + zone * bw
	var g0: float = maxf(BAR_X0, zc - gw)
	var g1: float = minf(BAR_X1, zc + gw)
	ci.draw_rect(Rect2(roundf(g0), BAR_Y, roundf(g1 - g0), 8), PX.SAGE)
	var p0: float = maxf(BAR_X0, zc - pw)
	var p1: float = minf(BAR_X1, zc + pw)
	ci.draw_rect(Rect2(roundf(p0), BAR_Y, roundf(p1 - p0), 8), PX.HONEY)
	ci.draw_rect(Rect2(roundf(p0), BAR_Y, roundf(p1 - p0), PX.lw()), PX.HONEY_LIGHT)
	PX.paw(ci, Vector2(roundf(zc), BAR_Y + 5), 1.4, Color(PX.MILK, 0.9), false)
	# marker
	var t: float = maxf(now, shot_sweep_t0)
	var m: float = shot_marker(t) if state == "play" or state == "outro" else 0.0
	var mx: float = roundf(BAR_X0 + m * bw)
	if PX.legacy():
		ci.draw_rect(Rect2(mx - 1, BAR_Y - 3, 3, 14), PX.OUTLINE)
		ci.draw_rect(Rect2(mx, BAR_Y - 2, 1, 12), PX.MILK)
	else:
		var mw: float = PX.lw()
		var mo: float = float(PX.ow())
		ci.draw_rect(Rect2(mx - mo, BAR_Y - 2 - mo, mw + mo * 2.0, 12 + mo * 2.0), PX.OUTLINE)
		ci.draw_rect(Rect2(mx, BAR_Y - 2, mw, 12), PX.MILK)
	PX.paw(ci, Vector2(mx, BAR_Y - 6), 2.0, PX.MILK, true)
	# hit pips
	var total: int = int(step.get("hits", 1))
	for i in total:
		var c := Vector2(BAR_X1 + 12 + i * 8, BAR_Y + 4)
		if i < shot_hits.size():
			PX.disc(ci, c, 2.5, PX.judgement_color(str(shot_hits[i]["j"])))
		elif PX.chunky():
			PX.disc(ci, c, 1.5, PX.CREAM)
		else:
			ci.draw_arc(c, 2.5, 0, TAU, 10, PX.OUTLINE, float(PX.ow()))


func _draw_needle_station(ci: CanvasItem, now: float) -> void:
	var look: String = str(step.get("look", "milk"))
	var lvl: float = needle_level_at(now) if nd_holding else nd_level
	lvl = clampf(lvl, 0.0, 1.0)
	if look == "kettle":
		# kettle on a little stove ring
		PX.box(ci, Rect2(118, 122, 56, 6), PX.STEEL_DARK)
		PX.ellipse(ci, Vector2(146, 104), 24.0, 18.0, PX.SAGE)
		ci.draw_rect(Rect2(126, 96, 40, 2), PX.SAGE_DARK)
		PX.box(ci, Rect2(141, 82, 10, 6), PX.SAGE_DARK)
		PX.disc(ci, Vector2(146, 80), 3.0, PX.HONEY)
		var spout := PackedVector2Array([Vector2(168, 102), Vector2(184, 88), Vector2(187, 91), Vector2(170, 110)])
		if PX.chunky():
			spout = PackedVector2Array([Vector2(167, 101), Vector2(183, 87), Vector2(188, 92), Vector2(170, 111)])
		PX.poly(ci, spout, PX.SAGE_DARK)
		PX.handle(ci, Vector2(124, 100), 8.0, PI * 0.5, PI * 1.5, 10, 3.0, PX.SAGE_DARK if PX.chunky() else Color(0, 0, 0, 0), 0.0)
		if nd_holding:
			for k in 3:
				var ff: float = fmod(now * 2.0 + k * 0.33, 1.0)
				PX.puff(ci, Vector2(186 + ff * 6.0, 84 - ff * 18.0), 2.0 + ff * 2.0, 1.0 - ff)
	else:
		# steam wand + pitcher
		if PX.legacy():
			ci.draw_rect(Rect2(148, 16, 4, 74), PX.OUTLINE)
			ci.draw_rect(Rect2(149, 16, 2, 74), PX.STEEL_DARK)
		else:
			PX.box(ci, Rect2(148, 14, 4, 76), PX.STEEL_DARK)
		var pitcher := PackedVector2Array([Vector2(130, 86), Vector2(166, 86), Vector2(162, 128), Vector2(134, 128)])
		if not PX.legacy():
			PX.handle(ci, Vector2(167, 104), 7.0, -PI / 2, PI / 2, 10, 3.0, PX.STEEL if PX.chunky() else Color(0, 0, 0, 0), 0.0)
		PX.poly(ci, pitcher, PX.STEEL)
		ci.draw_rect(Rect2(133, 90, 2, 30), PX.MILK)
		if PX.legacy():
			ci.draw_arc(Vector2(167, 104), 7.0, -PI / 2, PI / 2, 10, PX.OUTLINE, 3.0)
		# milk/foam rises with the level
		var foam_h: float = roundf(4.0 + lvl * 8.0)
		if PX.legacy():
			ci.draw_rect(Rect2(132, 86 - foam_h + 4, 32, foam_h - 3), PX.FOAM)
			ci.draw_rect(Rect2(132, 86 - foam_h + 3, 32, 1), PX.OUTLINE)
		else:
			var fy0: float = 86 - foam_h + 3
			PX.box(ci, Rect2(131, fy0, 34, 87 - fy0), PX.FOAM)
	# gauge
	var gh: float = GAUGE_BOTTOM - GAUGE_TOP
	PX.soft_box(ci, Rect2(GAUGE_X - 3, GAUGE_TOP - 3, 22, gh + 6), PX.CREAM, PX.OAK_DARK)
	var rate: float = float(step.get("rate", 0.5))
	var zone: float = float(step.get("zone", 0.7))
	var gwl: float = float(judge.call("good_window")) * rate
	var pwl: float = float(judge.call("purrfect_window")) * rate
	var zx: float = GAUGE_X + 8
	_gauge_band(ci, zx, 8, zone - gwl, zone + gwl, PX.SAGE)
	_gauge_band(ci, zx, 8, zone - pwl, zone + pwl, PX.HONEY)
	var flash: bool = now < nd_flash_until
	_gauge_band(ci, GAUGE_X, 16, 0.95, 1.0, PX.ALERT if flash else PX.OAK)
	# fill
	var fy: float = roundf(GAUGE_BOTTOM - lvl * gh)
	ci.draw_rect(Rect2(GAUGE_X + 1, fy, 6, GAUGE_BOTTOM - fy), Color("#E89A8F"))
	var gl: float = PX.lw()
	ci.draw_rect(Rect2(GAUGE_X, GAUGE_TOP, gl, gh), PX.OAK_DARK)
	ci.draw_rect(Rect2(GAUGE_X + 8 - gl, GAUGE_TOP, gl, gh), PX.OAK_DARK)
	for k in 5:
		ci.draw_rect(Rect2(GAUGE_X - 2 - (gl - 1.0), roundf(GAUGE_BOTTOM - k * gh / 4.0), 2 + (gl - 1.0), gl), PX.OAK_DARK)
	# needle pointer
	var ny: float = fy
	var tri := PackedVector2Array([Vector2(GAUGE_X + 17, ny), Vector2(GAUGE_X + 24, ny - 4), Vector2(GAUGE_X + 24, ny + 4)])
	if PX.chunky():
		tri = PackedVector2Array([Vector2(GAUGE_X + 16, ny), Vector2(GAUGE_X + 25, ny - 5), Vector2(GAUGE_X + 25, ny + 5)])
	ci.draw_colored_polygon(tri, PX.OUTLINE)
	ci.draw_rect(Rect2(GAUGE_X, ny - (gl - 1.0), 17, gl), PX.OUTLINE)
	PX.paw(ci, Vector2(GAUGE_X + 31, ny + 1), 2.0, PX.MILK, true)
	if flash:
		PX.text_centered(ci, GAUGE_X + 8, GAUGE_TOP - 11, "HOT!", PX.ALERT, 1, true)
	if nd_final_j != "":
		PX.paw(ci, Vector2(GAUGE_X - 14, ny), 3.0, PX.judgement_color(nd_final_j), true)


func _gauge_band(ci: CanvasItem, x: float, w: float, l0: float, l1: float, col: Color) -> void:
	var gh: float = GAUGE_BOTTOM - GAUGE_TOP
	var a: float = clampf(l0, 0.0, 1.0)
	var b: float = clampf(l1, 0.0, 1.0)
	var y0: float = roundf(GAUGE_BOTTOM - b * gh)
	var y1: float = roundf(GAUGE_BOTTOM - a * gh)
	if y1 > y0:
		ci.draw_rect(Rect2(x, y0, w, y1 - y0), col)


func _draw_lane(ci: CanvasItem, now: float) -> void:
	var y: float = LANE_Y
	PX.soft_box(ci, Rect2(56, y - 9, LANE_X1 - 52, 18), PX.CREAM, PX.OUTLINE)
	var gw: float = float(judge.call("good_window")) * LANE_SPEED
	var pw: float = float(judge.call("purrfect_window")) * LANE_SPEED
	ci.draw_rect(Rect2(roundf(maxf(57.0, LANE_HIT_X - gw)), y - 8, roundf(LANE_HIT_X + gw - maxf(57.0, LANE_HIT_X - gw)), 16), Color(PX.SAGE, 0.55))
	ci.draw_rect(Rect2(roundf(LANE_HIT_X - pw), y - 8, roundf(pw * 2.0), 16), Color(PX.HONEY, 0.55))
	# beat ticks
	var ph: float = beat_phase(now)
	var b0: int = floori(ph) - 2
	for b in range(b0, b0 + 24):
		var bt: float = t_order0 + float(b) * beat_period
		var x: float = LANE_HIT_X + (bt - now) * LANE_SPEED
		if x > 58.0 and x < LANE_X1 - 2:
			ci.draw_rect(Rect2(roundf(x), y - 7, PX.lw(), 14), Color(PX.OAK, 0.8 if b % 4 == 0 else 0.4))
	# paw target pulses on the beat
	var f: float = ph - floorf(ph)
	var pr: float = 4.0 + (1.0 if f < 0.2 and not reduced_motion else 0.0)
	PX.paw(ci, Vector2(LANE_HIT_X, y + 2), pr, Color(PX.OAK, 0.9), true)
	# beans
	for n in notes:
		if str(n["j"]) != "":
			continue
		var x2: float = LANE_HIT_X + (float(n["t"]) - now) * LANE_SPEED
		if x2 < 52.0 or x2 > LANE_X1 - 2:
			continue
		var c := Vector2(roundf(x2), y)
		PX.ellipse(ci, c, 4.0, 3.5, PX.HONEY)
		ci.draw_rect(Rect2(c.x - 2, c.y - 2, 2, PX.lw()), PX.HONEY_LIGHT)
	# count-in
	var first_t: float = float(notes[0]["t"]) if not notes.is_empty() else now
	if state == "play" and now < first_t:
		var beats_left: int = ceili((first_t - now) / beat_period - 0.001)
		var txt: String = "READY?" if beats_left >= 4 else str(beats_left)
		PX.text_outlined(ci, 160, 18, txt, PX.HONEY, 2)


func _draw_beat_station(ci: CanvasItem, now: float) -> void:
	var look: String = str(step.get("look", "pour"))
	var total: int = maxi(1, notes.size())
	var k: float = float(beat_hits) / float(total)
	var since: float = now - beat_last_hit_t
	match look:
		"pour":
			if not PX.legacy():
				PX.handle(ci, Vector2(184, 111), 6.0, -PI / 2, PI / 2, 10, 3.0, PX.MILK if PX.chunky() else Color(0, 0, 0, 0), 0.0)
			PX.box(ci, Rect2(138, 98, 44, 28), PX.MILK)
			if PX.legacy():
				ci.draw_arc(Vector2(184, 111), 6.0, -PI / 2, PI / 2, 10, PX.OUTLINE, 3.0)
			var top_col: Color = PX.COFFEE.lerp(PX.CREMA, minf(1.0, k * 1.6)).lerp(PX.FOAM, maxf(0.0, k * 2.0 - 1.0))
			ci.draw_rect(Rect2(139, 101, 42, 3), top_col)
			ci.draw_rect(Rect2(139, 104, 42, 21), PX.COFFEE.lerp(PX.CREMA, k))
			# heart forming in the foam
			if k > 0.3:
				PX.heart(ci, Vector2(157, 102), Color(PX.MILK, minf(1.0, (k - 0.3) * 2.0)))
			var pouring: bool = since < 0.3
			var tilt: float = 1.05 if pouring else 0.55
			if reduced_motion:
				tilt = 0.8
			var pc := Vector2(140, 66)
			var pts := PackedVector2Array([Vector2(-11, -12), Vector2(11, -12), Vector2(13, 12), Vector2(-9, 12), Vector2(-13, -8)])
			var xf := Transform2D(tilt, pc)
			var ppts: PackedVector2Array = xf * pts
			var handle: Vector2 = xf * Vector2(-16, 0)
			if PX.legacy():
				ci.draw_colored_polygon(ppts, PX.STEEL)
				ci.draw_polyline(ppts + PackedVector2Array([ppts[0]]), PX.OUTLINE)
				ci.draw_circle(handle, 3.0, PX.OUTLINE)
				ci.draw_circle(handle, 1.5, PX.STEEL_DARK)
			else:
				PX.disc(ci, handle, 2.0 if PX.chunky() else 1.5, PX.STEEL_DARK)
				PX.poly(ci, ppts, PX.STEEL)
			if pouring:
				var spout: Vector2 = xf * Vector2(11, -12)
				var so: float = 1.0 if PX.legacy() else float(PX.ow())
				ci.draw_rect(Rect2(roundf(spout.x) - so, roundf(spout.y), 2 + so * 2.0, 100 - roundf(spout.y) + (0.0 if PX.legacy() else so)), PX.OUTLINE)
				ci.draw_rect(Rect2(roundf(spout.x), roundf(spout.y), 2, 100 - roundf(spout.y)), PX.MILK)
		"whisk":
			_draw_bowl(ci, 1.0)
			var froth: int = int(k * 14.0)
			for i in froth:
				var fx: float = 160.0 + float((i * 37) % 52) - 26.0
				var fy: float = 105.0 + float((i * 13) % 5) - 2.0
				ci.draw_circle(Vector2(fx, fy), 2.0 if PX.chunky() else 1.5, Color("#DDEBC0"))
			# chasen whisk swings to the beat
			var swing: float = float(beat_side) * (7.0 if since < 0.18 else 4.0)
			var base := Vector2(160 + swing, 101)
			if PX.chunky():
				# one chunky tine bundle instead of five 1px tines
				var tb := PackedVector2Array([base + Vector2(-3, -14), base + Vector2(3, -14), base + Vector2(5, 0), base + Vector2(-5, 0)])
				PX.poly(ci, tb, PX.HONEY_LIGHT)
				ci.draw_rect(Rect2(base.x - 1, base.y - 12, 2, 11), PX.HONEY)
			else:
				if not PX.legacy():
					for d in [-4, -2, 0, 2, 4]:
						ci.draw_line(base + Vector2(d * 0.6, -14), base + Vector2(d, 0), PX.OUTLINE, 1.0 + 2.0 * float(PX.ow()))
				for d in [-4, -2, 0, 2, 4]:
					ci.draw_line(base + Vector2(d * 0.6, -14), base + Vector2(d, 0), PX.HONEY_LIGHT, 1.0)
			PX.box(ci, Rect2(base.x - 2, base.y - 40, 5, 27), PX.HONEY)
			ci.draw_rect(Rect2(base.x - 2, base.y - 30, 5, PX.lw()), PX.OAK_DARK)
		"knead":
			var sq: float = 0.0 if since > 0.18 or reduced_motion else (1.0 - since / 0.18)
			var rx: float = 30.0 + sq * 5.0
			var ry: float = 13.0 - sq * 4.0
			PX.box(ci, Rect2(112, 122, 96, 6), PX.OAK_DARK)
			PX.ellipse(ci, Vector2(160, 122 - ry), rx, ry, PX.DOUGH)
			ci.draw_rect(Rect2(146, 122 - ry * 2 + 3, 8, PX.lw()), Color(PX.MILK, 0.8))
			var prints: int = mini(beat_hits, 7)
			var pstep: float = 7.0
			if PX.chunky():
				prints = mini(beat_hits, 5)  # fewer, bigger prints
				pstep = 9.0
			for i in prints:
				var ox: float = float(i - (3 if not PX.chunky() else 2)) * pstep
				var oy: float = 122 - ry + (2.0 if i % 2 == 0 else -2.0)
				PX.paw(ci, Vector2(160 + ox, oy), 1.4, PX.DOUGH_DARK, false)
			# a big cream cat paw kneads on every hit
			var press: float = sq
			var py: float = 64.0 + press * 16.0
			var px: float = 160.0 + float(beat_side) * 6.0
			PX.box(ci, Rect2(px - 8, py - 40, 16, 34), PX.MILK)
			PX.ellipse(ci, Vector2(px, py), 10.0, 7.0, PX.MILK)
			PX.paw(ci, Vector2(px, py + 2), 2.2, PX.PINK, false)
		"art":
			_draw_latte_art(ci, now)
		"grind":
			_draw_grinder(ci, k, since)
		"sprinkle":
			_draw_cookie_tray(ci, maxi(3, cookie_stamps.size()))
			var cols: Array[Color] = [PX.PINK, PX.SAGE, PX.HONEY, PX.MILK]
			for i in beat_hits * 4:
				var cp: Vector2 = _cookie_pos(i % maxi(3, cookie_stamps.size()))
				var h: int = (i * 7919) % 97
				var off := Vector2(float(h % 19) - 9.0, float(floori(h / 19.0) % 7) - 4.0)
				if PX.legacy():
					ci.draw_rect(Rect2((cp + off).round(), Vector2(2, PX.lw())), cols[i % 4])
				else:
					_sprinkle(ci, (cp + off).round(), cols[i % 4])
			var shake: float = 0.0 if since > 0.2 or reduced_motion else sin(since * 60.0) * 3.0
			var sx: float = _cookie_pos(beat_hits % 3).x + shake
			PX.soft_box(ci, Rect2(sx - 7, 62, 14, 22), PX.PINK)
			PX.box(ci, Rect2(sx - 6, 56, 12, 7), PX.STEEL)
			if PX.chunky():
				ci.draw_rect(Rect2(sx - 4, 58, 2, 2), PX.OUTLINE)
				ci.draw_rect(Rect2(sx + 2, 58, 2, 2), PX.OUTLINE)
			else:
				for d in 3:
					ci.draw_rect(Rect2(sx - 4 + d * 3, 58, 1, 1), PX.OUTLINE)
			if since < 0.3:
				for d in 3:
					if PX.legacy():
						ci.draw_rect(Rect2(sx - 3 + d * 3, 88 + since * 50.0 + d * 3, 2, PX.lw()), cols[(beat_hits + d) % 4])
					else:
						_sprinkle(ci, Vector2(sx - 4 + d * 4, roundf(88 + since * 50.0 + d * 4)), cols[(beat_hits + d) % 4])


## B..F sprinkle: 2x2 colour with an ink ring (1px B..E, 2px F: tiny bits stay readable).
func _sprinkle(ci: CanvasItem, p: Vector2, col: Color) -> void:
	var r := Rect2(p, Vector2(2, 2))
	ci.draw_rect(r.grow(float(maxi(1, PX.ow() - 1))), PX.OUTLINE)
	ci.draw_rect(r, col)


func _draw_bowl(ci: CanvasItem, matcha_k: float) -> void:
	var bowl := PackedVector2Array()
	for i in 13:
		var a: float = PI * float(i) / 12.0
		bowl.append(Vector2(160, 106) + Vector2(cos(a) * 32.0, sin(a) * 20.0))
	var inner := PackedVector2Array()
	for p in bowl:
		inner.append(Vector2(160, 106) + (p - Vector2(160, 106)) * 0.94)
	if PX.legacy():
		ci.draw_colored_polygon(bowl, PX.OUTLINE)
		ci.draw_colored_polygon(inner, Color("#C98E6B"))
	else:
		PX.box(ci, Rect2(149, 124, 22, 4), Color("#C98E6B"))
		PX.poly(ci, inner, Color("#C98E6B"))
	PX.ellipse(ci, Vector2(160, 106), 31.0, 5.0, Color("#E8F0F4").lerp(PX.MATCHA, matcha_k))
	if PX.legacy():
		ci.draw_rect(Rect2(150, 126, 20, 2), PX.OUTLINE)


func _draw_sift_station(ci: CanvasItem, now: float) -> void:
	var total: int = maxi(1, int(step.get("hits", 1)))
	_draw_bowl(ci, float(shot_hits.size()) / float(total))
	var tap: float = 0.0
	if not shot_hits.is_empty() and now - float(shot_hits[shot_hits.size() - 1]["t"]) < 0.2:
		tap = 3.0
	var c := Vector2(160, 72 + tap)
	PX.ellipse(ci, c, 22.0, 6.0, PX.STEEL)
	PX.ellipse(ci, c + Vector2(0, 1), 18.0, 4.0, PX.MATCHA_DARK, PX.STEEL_DARK)
	if PX.chunky():
		for d in range(-12, 13, 6):
			ci.draw_rect(Rect2(c.x + d - 1, c.y - 2, 2, 5), Color(PX.STEEL_DARK, 0.8))
	else:
		for d in range(-14, 15, 4):
			ci.draw_rect(Rect2(c.x + d, c.y - 2, 1, 5), Color(PX.STEEL_DARK, 0.6))
	PX.box(ci, Rect2(c.x + 22, c.y - 2, 24, 4), PX.OAK)
	# matcha tin
	PX.soft_box(ci, Rect2(204, 98, 23, 28), PX.SAGE)
	ci.draw_rect(Rect2(205, 106, 21, 9), PX.CREAM)
	PX.text(ci, Vector2(207 if PX.legacy() else 206, 107), "TEA", PX.SAGE_DARK)


func _draw_grinder(ci: CanvasItem, k: float, since: float) -> void:
	# glass hopper with beans
	var hop := PackedVector2Array([Vector2(140, 30), Vector2(180, 30), Vector2(172, 56), Vector2(148, 56)])
	PX.poly(ci, hop, Color("#F3E9DA"))
	var beans: int = int(round((1.0 - k) * 12.0))
	if PX.chunky():
		# fewer, bigger beans (no 1px outlines merging into mush)
		beans = int(round((1.0 - k) * 7.0))
		for i in beans:
			var bx2: float = 152.0 + float((i * 6) % 18)
			var by2: float = 51.0 - float(floori(i / 3.0)) * 6.0
			ci.draw_colored_polygon(PX.ellipse_points(Vector2(bx2, by2), 3.0, 2.0, 12), PX.COFFEE)
			ci.draw_rect(Rect2(bx2 - 1, by2 - 1, 2, 1), PX.CREMA)
	for i in (beans if not PX.chunky() else 0):
		var bx: float = 151.0 + float((i * 5) % 19)
		var by: float = 51.0 - float(floori(i / 4.0)) * 5.0
		PX.ellipse(ci, Vector2(bx, by), 2.5, 1.5, PX.COFFEE, PX.OUTLINE)
	# body
	PX.soft_box(ci, Rect2(144, 56, 32, 44), PX.OAK_DARK)
	if not PX.chunky():
		ci.draw_rect(Rect2(146, 58, 28, 3), Color("#94693F"))
	PX.box(ci, Rect2(150, 66, 20, 14), PX.CREAM)
	PX.paw(ci, Vector2(160, 74), 2.0, PX.HONEY, false)
	# crank turns a quarter per hit
	var ang: float = float(beat_hits) * PI * 0.5
	if since < 0.18 and not reduced_motion:
		ang -= (1.0 - since / 0.18) * PI * 0.5
	var hub := Vector2(178, 62)
	var tip: Vector2 = hub + Vector2.from_angle(ang) * 12.0
	PX.bar_line(ci, hub, tip, PX.STEEL_DARK, 3.0)
	PX.disc(ci, hub, 2.0, PX.STEEL)
	PX.disc(ci, tip, 3.0, PX.HONEY)
	# drawer + grounds pile
	PX.box(ci, Rect2(146, 100, 28, 10), PX.OAK)
	ci.draw_rect(Rect2(157, 104, 6, 2), PX.OUTLINE)
	if k > 0.0:
		PX.ellipse(ci, Vector2(160, 125), 4.0 + k * 14.0, 1.5 + k * 3.0, PX.COFFEE)


func _draw_latte_art(ci: CanvasItem, _now: float) -> void:
	var c := Vector2(160, 72)
	PX.ellipse(ci, c + Vector2(0, 44), 44.0, 10.0, PX.MILK)
	PX.disc(ci, c, 40.0, PX.MILK)
	PX.handle(ci, c + Vector2(43, 0), 9.0, -PI / 2, PI / 2, 12, 4.0, PX.MILK, 2.0)
	PX.disc(ci, c, 34.0, PX.CREMA)
	ci.draw_circle(c, 33.0, PX.CREMA)
	ci.draw_arc(c, 33.0, 0, TAU, 40, Color("#9C6A3E"), PX.lw())
	var done: Array = []
	for n in notes:
		if str(n["j"]) != "":
			done.append(n)
	var strokes: int = done.size()
	for i in strokes:
		var w: Vector2 = (done[i]["wob"] as Vector2)
		_art_stroke(ci, i, c + w)


## One foam stroke of the latte cat (15 strokes = the full face).
func _art_stroke(ci: CanvasItem, i: int, c: Vector2) -> void:
	var foam: Color = PX.FOAM
	var line: Color = Color("#8A5A35")
	var sw: float = PX.lw()
	# whiskers (8..11) keep A's exact 1px foam call in every style: chunky only thickens
	# strokes A shows, it never adds features
	match i:
		0:
			ci.draw_colored_polygon(_half_disc(c + Vector2(0, 4), 17.0, PI * 0.5, PI * 1.5), foam)
		1:
			ci.draw_colored_polygon(_half_disc(c + Vector2(0, 4), 17.0, -PI * 0.5, PI * 0.5), foam)
		2:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -4), c + Vector2(-13, -22), c + Vector2(-3, -11)]), foam)
		3:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(16, -4), c + Vector2(13, -22), c + Vector2(3, -11)]), foam)
		4:
			ci.draw_rect(Rect2(c.x - 8, c.y, 3, 3), line)
		5:
			ci.draw_rect(Rect2(c.x + 5, c.y, 3, 3), line)
		6:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-2, 6), c + Vector2(2, 6), c + Vector2(0, 8)]), PX.PINK)
		7:
			ci.draw_polyline(PackedVector2Array([c + Vector2(-4, 10), c + Vector2(-2, 11), c + Vector2(0, 9), c + Vector2(2, 11), c + Vector2(4, 10)]), line, -1.0 if sw < 2.0 else sw)
		8:
			ci.draw_line(c + Vector2(-14, 7), c + Vector2(-26, 4), foam, 1.0)
		9:
			ci.draw_line(c + Vector2(14, 7), c + Vector2(26, 4), foam, 1.0)
		10:
			ci.draw_line(c + Vector2(-14, 10), c + Vector2(-26, 12), foam, 1.0)
		11:
			ci.draw_line(c + Vector2(14, 10), c + Vector2(26, 12), foam, 1.0)
		12:
			ci.draw_rect(Rect2(c.x - 12, c.y + 6, 3, 2), Color(PX.PINK, 0.8))
			ci.draw_rect(Rect2(c.x + 9, c.y + 6, 3, 2), Color(PX.PINK, 0.8))
		13:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -18), c + Vector2(-13, -10), c + Vector2(-7, -13)]), Color(PX.PINK, 0.7))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(12, -18), c + Vector2(13, -10), c + Vector2(7, -13)]), Color(PX.PINK, 0.7))
		_:
			PX.heart(ci, c + Vector2(17, -26), foam)


func _half_disc(c: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array([c])
	for i in 13:
		var a: float = lerpf(a0, a1, float(i) / 12.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw_oven_slot(ci: CanvasItem, now: float) -> void:
	if oven.is_empty():
		return
	var collected: bool = bool(oven["collected"])
	if collected and now - float(oven["t_collect"]) > 1.2:
		return
	var c: Vector2 = OVEN_SLOT
	var nope: float = now - float(oven["nope_t"])
	if nope < 0.3 and not reduced_motion:
		c.x += roundf(sin(nope * 60.0) * 2.0)
	_draw_ring(ci, c, OVEN_R, now, collected)


func _draw_ring(ci: CanvasItem, c: Vector2, r: float, now: float, collected: bool) -> void:
	var ts: float = float(oven["t_start"])
	var td: float = float(oven["t_done"])
	var k: float = clampf((now - ts) / maxf(0.01, td - ts), 0.0, 1.0)
	var ready: bool = now >= td - float(judge.call("good_window", OVEN_SCALE)) and not collected
	if ready:
		var pulse: float = 0.5 + 0.5 * sin(now * 10.0)
		ci.draw_circle(c, r + 4.0 + pulse * 2.0, Color(PX.HONEY, 0.35 + 0.25 * pulse))
	PX.disc(ci, c, r, PX.CREAM)
	if k > 0.0:
		ci.draw_arc(c, r - 3.0, -PI / 2, -PI / 2 + TAU * k, 32, PX.HONEY if ready or collected else PX.SAGE, 4.0)
	# the "ding" mark at 12 o'clock
	if PX.legacy():
		ci.draw_rect(Rect2(c.x - 1, c.y - r - 2, 3, 4), PX.OUTLINE)
	else:
		var dm: float = float(PX.ow() - 1)
		ci.draw_rect(Rect2(c.x - 1 - dm, c.y - r - 2 - dm, 3 + dm * 2.0, 4 + dm), PX.OUTLINE)
	if str(oven.get("look", "")) == "tea":
		# tiny teapot in the middle
		PX.ellipse(ci, c + Vector2(0, 1), r * 0.42, r * 0.32, PX.SAGE)
		ci.draw_rect(Rect2(c.x - 1, c.y - r * 0.32 - 2, 3, 2), PX.OUTLINE)
		ci.draw_rect(Rect2(c.x + r * 0.42, c.y - 1, 3, PX.lw()), PX.OUTLINE)
	else:
		PX.disc(ci, c, r * 0.42, PX.DOUGH if not collected else PX.DOUGH_DARK)
		PX.paw(ci, c + Vector2(0, 1), maxf(1.0, r * 0.12), PX.COFFEE, false)
	if collected:
		PX.paw(ci, c + Vector2(r * 0.7, -r * 0.7), 2.0, PX.judgement_color(str(oven["j"])), true)


func _draw_big_oven(ci: CanvasItem, now: float) -> void:
	var look: String = str(oven.get("look", step.get("look", "cookie")))
	if look == "tea":
		PX.ellipse(ci, Vector2(160, 92), 44.0, 32.0, PX.SAGE)
		ci.draw_rect(Rect2(124, 76, 72, 2), PX.SAGE_DARK)
		PX.box(ci, Rect2(150, 54, 20, 8), PX.SAGE_DARK)
		PX.disc(ci, Vector2(160, 52), 3.0, PX.HONEY)
		var sp := PackedVector2Array([Vector2(202, 92), Vector2(222, 72), Vector2(226, 76), Vector2(206, 102)])
		PX.poly(ci, sp, PX.SAGE_DARK)
		PX.handle(ci, Vector2(116, 92), 12.0, PI * 0.5, PI * 1.5, 12, 4.0, PX.SAGE_DARK if PX.chunky() else Color(0, 0, 0, 0), 0.0)
		if not oven.is_empty():
			_draw_ring(ci, Vector2(160, 96), 20.0, now, bool(oven["collected"]))
		return
	PX.soft_box(ci, Rect2(112, 30, 96, 96), PX.OAK_DARK)
	ci.draw_rect(Rect2(113, 31, 94, 8), Color("#94693F"))
	if not PX.legacy():
		ci.draw_rect(Rect2(113, 39, 94, PX.lw()), PX.OUTLINE)
	for k in 3:
		PX.disc(ci, Vector2(124 + k * 10, 35), 2.0, PX.CREAM)
	PX.soft_box(ci, Rect2(122, 46, 76, 72), Color("#3B2A20"))
	ci.draw_rect(Rect2(124, 48, 72, 68), Color("#FFB86B", 0.25 + 0.1 * sin(now * 3.0)))
	if oven.is_empty():
		PX.text_outlined(ci, 160, 74, "BAKING!", PX.HONEY, 1)
		return
	_draw_ring(ci, _oven_center(), 24.0, now, bool(oven["collected"]))


# ---------------------------------------------------------------- result card

## The round S / A / B / C grade stamp (also used by the art-option sheets).
func draw_grade_stamp(ci: CanvasItem, sc: Vector2, g: String) -> void:
	var gc: Color = PX.HONEY
	match g:
		"A":
			gc = PX.SAGE
		"B":
			gc = PX.OAK
		"C":
			gc = PX.PINK
	if PX.legacy():
		PX.disc(ci, sc, 25.0, PX.OUTLINE)
		PX.disc(ci, sc, 23.0, gc, gc.darkened(0.25))
	else:
		PX.disc(ci, sc, 24.0, gc.darkened(0.25))
		PX.disc(ci, sc, 22.0, gc, gc.darkened(0.25))
	ci.draw_arc(sc, 19.0, 0, TAU, 32, Color(PX.CREAM, 0.6), PX.lw())
	var lx: float = sc.x - 12 - (0.0 if PX.legacy() else float(PX._bold(5)) / 2.0)
	PX.text(ci, Vector2(lx + 2, sc.y - 17 + 2), g, Color(PX.OUTLINE, 0.25), 5)
	PX.text(ci, Vector2(lx, sc.y - 17), g, PX.OUTLINE, 5)


func _draw_result(ci: CanvasItem, now: float) -> void:
	var r := Rect2(54, 18, 212, 146)
	ci.draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(PX.OUTLINE, 0.25))
	PX.soft_box(ci, r, PX.OAK, PX.OUTLINE)
	PX.soft_box(ci, r.grow(-3 - float(PX.ow() - 1)), PX.CREAM, PX.OAK_DARK)
	var dish: String = str(result.get("name", "")).to_upper()
	PX.text_centered(ci, 160, 26, dish + " SERVED!", PX.OAK_DARK)
	if PX.legacy():
		ci.draw_rect(Rect2(66, 36, 188, PX.lw()), PX.OAK)
	else:
		PX.divider(ci, 66, 36, 188)
	# grade stamp
	var g: String = str(result.get("grade", "C"))
	var sc := Vector2(104, 72)
	draw_grade_stamp(ci, sc, g)
	PX.text_centered(ci, sc.x, 104, str(result.get("title", "")), PX.OUTLINE)
	if g == "C":
		PX.heart(ci, Vector2(sc.x - 3, 114), Color("#D9776E"), true)
	# breakdown
	var counts: Dictionary = result.get("counts", {})
	var x0: float = 150.0 if PX.legacy() else 142.0
	var vx: float = 250.0 if PX.legacy() else 258.0
	var rows: Array = [
		["purrfect", "PURR-FECT", int(counts.get("purrfect", 0))],
		["good", "GOOD", int(counts.get("good", 0))],
		["ok", "OK", int(counts.get("ok", 0))],
	]
	var y: float = 46.0
	for row in rows:
		PX.paw(ci, Vector2(x0 + 3, y + 4), 2.0, PX.judgement_color(str(row[0])), true)
		PX.text(ci, Vector2(x0 + 11, y + 1), str(row[1]), PX.OUTLINE)
		var v: String = str(row[2])
		PX.text(ci, Vector2(vx - PX.text_width(v), y + 1), v, PX.OUTLINE)
		y += 11.0
	if PX.legacy():
		ci.draw_rect(Rect2(x0, y + 1, 100, PX.lw()), PX.OAK)
	else:
		PX.divider(ci, x0, y + 1, vx - x0)
	y += 5.0
	PX.text(ci, Vector2(x0, y), "BEST COMBO", PX.OAK_DARK)
	var bc: String = str(result.get("best_combo", 0))
	PX.text(ci, Vector2(vx - PX.text_width(bc), y), bc, PX.OAK_DARK)
	y += 10.0
	PX.text(ci, Vector2(x0, y), "PURR CHAIN", PX.OAK_DARK)
	var cb: String = "%d +$%d" % [int(result.get("chain", 0)), int(result.get("chain_bonus", 0))]
	PX.text(ci, Vector2(vx - PX.text_width(cb), y), cb, PX.OAK_DARK)
	y += 14.0
	var money: String = "+$%d" % int(result.get("money", 0))
	PX.text_outlined(ci, 200, y, money, PX.HONEY, 2)
	# serve prompt
	var blink: bool = fmod(now, 1.0) < 0.7
	if blink:
		PX.text_centered(ci, 160, 148, "CLICK TO SERVE", PX.OAK_DARK)
