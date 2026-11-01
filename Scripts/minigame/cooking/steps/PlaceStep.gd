extends "res://Scripts/minigame/cooking/steps/StepBase.gd"

## PLACE verb: drop items onto a ghost marker (marshmallow cats, red bean, pancakes, buttons,
## mochi eyes + ears).
##   mode "swing" (default): the item sways on a string, +/- swing_amp_px over swing_sec (one
##       full period, x time_scale()). Tap (LMB / Space) to drop it; it falls straight down.
##       Offset = horizontal distance between the drop x and the marker x.
##   mode "drag": drag the item from the tray onto a ghost marker (press = pick up, release =
##       drop; hold_to_toggle makes it click / click). Keyboard: arrows / WASD move the item
##       (a tap of an arrow nudges 1 px); Space picks the next item up from the tray (if it
##       isn't already in hand) and Space again drops it. RMB (or Backspace) undoes the last item.
##       Offset = distance to the nearest free marker of the same kind.
##   bands_px [5, 10, 18] (x window_scale()): <= b0 -> 1.0, <= b1 -> 0.85, <= b2 -> 0.65, else 0.4.
##   count: items to place; accuracy = mean. stack: true stacks swing items on each other.
##   The marker is offset by _roll.target_x x the vessel width.
##   tint_from_prev: "stop_ring" tints items from earlier steps' extra.brown(s) (calico pancakes).
##   item: marshmallow_cat | red_bean | pancake | button | eyes_ears (cosmetic + layout).
## Off-centre drops stay where they land (slight tilt): wonky, never broken.
## extra = {offsets: [px], scores: [acc]}.
## Hooks for later audio: _sfx(id) is called with "drop", "land", "pickup", "undo".

const StopRing = preload("res://Scripts/minigame/cooking/steps/StopRingStep.gd")

const COUNTER_Y := 124.0
const PIVOT_Y := 36.0
const HANG_Y := 54.0
const GRAVITY := 900.0
const POP_SEC := 0.5
const RESPAWN_SEC := 0.35
const SETTLE_SEC := 0.45
const KEY_SPEED := 55.0
const MARSH_COL := Color("#FFFDF7")
const BEAN_COL := Color("#7A2E2E")
const BUTTON_COL := Color("#3A2C33")
const GLASS_COL := Color("#2B2129")

var mode: String = "swing"
var item: String = "marshmallow_cat"
var count: int = 1
var stack: bool = false
var bands: Array[float] = [5.0, 10.0, 18.0]
var amp: float = 40.0
var period: float = 1.6
var cx: float = 160.0
var target_x: float = 160.0

## Placed items: {pos: Vector2, kind: String, score: float, offset: float, tilt: float, target: int}
var placed: Array[Dictionary] = []
## Drag targets: {pos: Vector2, kind: String}
var targets: Array[Dictionary] = []
var tints: Array[Color] = []

# swing state
var swing_t: float = 0.0
var falling: bool = false
var fall_pos: Vector2 = Vector2.ZERO
var fall_v: float = 0.0
var fall_land_y: float = 0.0
var _respawn: float = 0.0

# drag state
var dragging: bool = false
var drag_pos: Vector2 = Vector2.ZERO
var key_cursor: Vector2 = Vector2.ZERO
var key_active: bool = false
var _key_hold: float = 0.0
var _settle: float = -1.0

var _pop_t: float = 99.0
var _pop_pos: Vector2 = Vector2.ZERO
var _pop_score: float = 0.0
var _pop_text: String = ""


func _on_start() -> void:
	mode = String(params.get("mode", "swing"))
	item = String(params.get("item", "marshmallow_cat"))
	count = maxi(int(params.get("count", 1)), 1)
	stack = bool(params.get("stack", false))
	var bp: Variant = params.get("bands_px", [5, 10, 18])
	bands.clear()
	if bp is Array and (bp as Array).size() >= 3:
		for v in bp:
			bands.append(float(v))
	else:
		bands.assign([5.0, 10.0, 18.0])
	amp = float(params.get("swing_amp_px", 40.0))
	period = maxf(float(params.get("swing_sec", 1.6)) * time_scale(), 0.3)
	cx = roundf(safe_rect().get_center().x)
	target_x = cx + float(roll("target_x", 0.0)) * _vessel_width()
	placed.clear()
	_build_targets()
	_build_tints()
	swing_t = 0.0
	falling = false
	dragging = false
	key_active = false
	key_cursor = _tray_slot(0)
	_settle = -1.0
	queue_redraw()


# --- Layout ------------------------------------------------------------------------------------

func _vessel_width() -> float:
	match item:
		"red_bean":
			return 50.0
		"pancake":
			return 44.0
		"button":
			return 30.0
		"eyes_ears":
			return 40.0
	return 44.0


## Centre of the vessel / dish (on the counter).
func _dish_center() -> Vector2:
	if item == "eyes_ears":
		return Vector2(target_x, 100)
	return Vector2(cx, COUNTER_Y)


func _build_targets() -> void:
	targets.clear()
	match item:
		"eyes_ears":
			var m: Vector2 = _dish_center()
			targets.append({"pos": m + Vector2(-12, -19), "kind": "ear"})
			targets.append({"pos": m + Vector2(12, -19), "kind": "ear"})
			targets.append({"pos": m + Vector2(-7, -2), "kind": "eye"})
			targets.append({"pos": m + Vector2(7, -2), "kind": "eye"})
		"button":
			for i in range(count):
				targets.append({"pos": Vector2(target_x, 88 + i * 12), "kind": "button"})
		"red_bean":
			targets.append({"pos": Vector2(target_x, 106), "kind": "red_bean"})
		_:
			for i in range(count):
				targets.append({"pos": Vector2(target_x, 0), "kind": item})


func _build_tints() -> void:
	tints.clear()
	var src: String = String(params.get("tint_from_prev", ""))
	if src == "":
		return
	var prev: Variant = params.get("_prev", [])
	if not (prev is Array):
		return
	for e in prev:
		if not (e is Dictionary) or String((e as Dictionary).get("type", "")) != src:
			continue
		var ex: Variant = (e as Dictionary).get("extra", {})
		if ex is Dictionary and (ex as Dictionary).has("brown"):
			tints.append(StopRing.brown_color(float((ex as Dictionary)["brown"])))


func _item_size() -> Vector2:
	match item:
		"marshmallow_cat":
			return Vector2(14, 10)
		"red_bean":
			return Vector2(7, 5)
		"pancake":
			return Vector2(30, 6)
		"button":
			return Vector2(7, 7)
	return Vector2(6, 6)


## Where the next swing item lands (its centre).
func _landing_y(index: int) -> float:
	var h: float = _item_size().y
	match item:
		"marshmallow_cat":
			var surface: float = 95.0
			if stack:
				return surface - h * 0.5 + 2.0 - float(index) * (h - 2.0)
			return surface - h * 0.5 + 2.0
		"pancake":
			var plate_top: float = COUNTER_Y - 3.0
			return plate_top - h * 0.5 - float(index) * (h - 1.0)
		"button", "red_bean":
			var ti: int = mini(index, targets.size() - 1)
			return (targets[ti]["pos"] as Vector2).y
	return COUNTER_Y - h


func _tray_rect() -> Rect2:
	var area: Rect2 = safe_rect()
	return Rect2(area.position.x + 14, 108, 54, 16)


func _tray_slot(i: int) -> Vector2:
	var r: Rect2 = _tray_rect()
	return Vector2(r.position.x + 8 + i * 12, r.get_center().y)


func _kind_for(index: int) -> String:
	if item == "eyes_ears":
		return "ear" if index < 2 else "eye"
	return item


# --- Scoring -----------------------------------------------------------------------------------

func score_for_offset(offset: float) -> float:
	var ws: float = window_scale()
	if offset <= bands[0] * ws:
		return 1.0
	if offset <= bands[1] * ws:
		return 0.85
	if offset <= bands[2] * ws:
		return 0.65
	return 0.4


func _label_for(score: float) -> String:
	if score >= 1.0:
		return "Purrfect!"
	if score >= 0.85:
		return "Nice!"
	if score >= 0.65:
		return "Cute!"
	return "Wonky!"


## Probe / debug view.
func get_debug_state() -> Dictionary:
	return {
		"mode": mode, "swing_x": swing_x(), "target_x": target_x, "falling": falling,
		"placed": placed.size(), "count": count, "dragging": dragging,
		"key_cursor": key_cursor, "targets": targets.duplicate(true), "respawn": _respawn,
		"ready": _swing_ready(),
	}


func swing_x() -> float:
	return cx + amp * cos(TAU * swing_t / period)


func _swing_ready() -> bool:
	return mode == "swing" and not falling and _respawn <= 0.0 and placed.size() < count and is_running()


# --- Process -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_pop_t += delta
	if is_running():
		if mode == "swing":
			_process_swing(delta)
		else:
			_process_drag(delta)
	queue_redraw()


func _process_swing(delta: float) -> void:
	if _respawn > 0.0:
		_respawn -= delta
		if _respawn <= 0.0:
			swing_t = 0.0
		return
	if falling:
		fall_v += GRAVITY * delta
		fall_pos.y += fall_v * delta
		if fall_pos.y >= fall_land_y:
			fall_pos.y = fall_land_y
			falling = false
			_land(fall_pos)
		return
	swing_t += delta


func _process_drag(delta: float) -> void:
	if _settle >= 0.0:
		_settle += delta
		if _settle >= SETTLE_SEC:
			_finish_all()
		return
	var v: Vector2 = nudge_vector()
	if v != Vector2.ZERO and not dragging:
		key_active = true
		_key_hold += delta
		var spd: float = KEY_SPEED * (1.8 if _key_hold > 0.6 else 1.0)
		key_cursor += v.normalized() * spd * delta
		key_cursor = key_cursor.clamp(Vector2(4, 36), Vector2(316, 176))
	else:
		_key_hold = 0.0


# --- Input -------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if not is_running() or mode != "drag":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_undo()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_BACKSPACE, KEY_X:
				_undo()
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_A:
				_nudge(Vector2.LEFT)
			KEY_RIGHT, KEY_D:
				_nudge(Vector2.RIGHT)
			KEY_UP, KEY_W:
				_nudge(Vector2.UP)
			KEY_DOWN, KEY_S:
				_nudge(Vector2.DOWN)


func _nudge(d: Vector2) -> void:
	if dragging or _settle >= 0.0:
		return
	if not key_active:
		key_active = true
		key_cursor = _tray_slot(0)
	key_cursor = (key_cursor + d).round()
	get_viewport().set_input_as_handled()


func _on_tap(_pos: Vector2, from_mouse: bool) -> void:
	if mode == "swing":
		if _swing_ready():
			_drop_swing()
			get_viewport().set_input_as_handled()
		return
	# drag mode: the keyboard picks up / drops with Space; the mouse uses the hold hooks.
	if not from_mouse and not dragging and _settle < 0.0 and placed.size() < count:
		if key_active:
			_drop_at(key_cursor.round())
		else:
			key_active = true
			key_cursor = _tray_slot(0) + Vector2(0, -14)
			_sfx("pickup")
		get_viewport().set_input_as_handled()


func _on_hold_begin(pos: Vector2, from_mouse: bool) -> void:
	if mode != "drag" or not from_mouse or _settle >= 0.0 or placed.size() >= count:
		return
	dragging = true
	key_active = false
	drag_pos = pos
	_sfx("pickup")
	get_viewport().set_input_as_handled()


func _on_hold_end(pos: Vector2) -> void:
	if mode != "drag" or not dragging:
		return
	dragging = false
	_drop_at(pos)


func _on_pointer_moved(pos: Vector2) -> void:
	if dragging:
		drag_pos = pos


# --- Actions -----------------------------------------------------------------------------------

func _drop_swing() -> void:
	falling = true
	fall_pos = Vector2(swing_x(), _hang_y())
	fall_v = 0.0
	fall_land_y = _landing_y(placed.size())
	_sfx("drop")


func _hang_y() -> float:
	# Pendulum arc: lifts a little at the ends of the swing.
	var dx: float = swing_x() - cx
	return HANG_Y - (dx * dx) / (2.0 * 90.0)


func _land(pos: Vector2) -> void:
	var idx: int = placed.size()
	var ti: int = mini(idx, targets.size() - 1)
	var tx: float = (targets[ti]["pos"] as Vector2).x
	var off: float = absf(pos.x - tx)
	var below_x: float = tx
	if stack and idx > 0:
		below_x = (placed[idx - 1]["pos"] as Vector2).x
	var tilt: float = clampf((pos.x - below_x) / 140.0, -0.12, 0.12) if off > bands[0] * window_scale() else 0.0
	_add_placed(pos, item, off, tilt, ti)
	_sfx("land")
	if placed.size() >= count:
		_finish_all()
	else:
		_respawn = RESPAWN_SEC


func _drop_at(pos: Vector2) -> void:
	var kind: String = _kind_for(placed.size())
	var best: int = -1
	var best_d: float = INF
	for i in range(targets.size()):
		if String(targets[i]["kind"]) != kind or _target_taken(i):
			continue
		var d: float = pos.distance_to(targets[i]["pos"] as Vector2)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		best = 0
		best_d = pos.distance_to(targets[0]["pos"] as Vector2)
	_add_placed(pos, kind, best_d, 0.0, best)
	_sfx("land")
	key_active = false
	key_cursor = _tray_slot(0)
	if placed.size() >= count:
		_settle = 0.0


func _target_taken(i: int) -> bool:
	for p in placed:
		if int(p["target"]) == i:
			return true
	return false


func _add_placed(pos: Vector2, kind: String, off: float, tilt: float, ti: int) -> void:
	var sc: float = score_for_offset(off)
	placed.append({"pos": pos, "kind": kind, "score": sc, "offset": off, "tilt": tilt, "target": ti})
	_pop_t = 0.0
	_pop_pos = pos
	_pop_score = sc
	_pop_text = _label_for(sc)


func _undo() -> void:
	if placed.is_empty() or dragging:
		return
	placed.pop_back()
	_settle = -1.0
	_pop_t = 99.0
	_sfx("undo")


func _finish_all() -> void:
	var sum: float = 0.0
	var offs: Array = []
	var scores: Array = []
	for p in placed:
		sum += float(p["score"])
		offs.append(snappedf(float(p["offset"]), 0.01))
		scores.append(float(p["score"]))
	extra = {"offsets": offs, "scores": scores}
	finish(sum / float(maxi(placed.size(), 1)))


## Audio hook (cozy sounds are a follow-up).
func _sfx(_id: String) -> void:
	pass


# --- Drawing -----------------------------------------------------------------------------------

func _draw() -> void:
	if not _started:
		return
	_draw_vessel()
	_draw_ghosts()
	for i in range(placed.size()):
		var p: Dictionary = placed[i]
		_draw_item(String(p["kind"]), p["pos"] as Vector2, float(p["tilt"]), i)
	if mode == "swing":
		_draw_swing()
	else:
		_draw_drag()
	_draw_pop()
	_draw_counter_pips()


func _draw_vessel() -> void:
	var c: Vector2 = _dish_center()
	match item:
		"marshmallow_cat":
			PixelDraw.mug(self, Vector2(cx, COUNTER_Y), 44, 36, PixelDraw.CREAM, PixelDraw.COFFEE, 0.85)
			# cocoa ripple
			PixelDraw.hl(self, Rect2(cx - 16, 97, 6, 1), Color(PixelDraw.MILK, 0.4))
			PixelDraw.hl(self, Rect2(cx + 6, 99, 8, 1), Color(PixelDraw.MILK, 0.4))
		"red_bean":
			_draw_plate(Vector2(cx, COUNTER_Y), 34)
			_draw_fish(Vector2(cx, 108), PixelDraw.HONEY)
		"pancake":
			_draw_plate(Vector2(cx, COUNTER_Y), 26)
		"button":
			_draw_glass(Vector2(cx, COUNTER_Y))
		"eyes_ears":
			_draw_plate(Vector2(cx, COUNTER_Y), 30)
			var m: Vector2 = c
			PixelDraw.shadow(self, Vector2(m.x, COUNTER_Y - 3), 22, 2)
			PixelDraw.circle(self, m, 20, MARSH_COL)
			PixelDraw.px(self, Rect2(m.x - 12, m.y + 12, 24, 1), PixelDraw.CREAM_DARK)
			PixelDraw.disc(self, m + Vector2(-11, 5), 2, Color(PixelDraw.BLUSH, 0.8))
			PixelDraw.disc(self, m + Vector2(11, 5), 2, Color(PixelDraw.BLUSH, 0.8))
			PixelDraw.line(self, m + Vector2(-1, 4), m + Vector2(0, 5))
			PixelDraw.line(self, m + Vector2(1, 5), m + Vector2(2, 4))


func _draw_plate(bc: Vector2, half_w: float) -> void:
	PixelDraw.shadow(self, bc + Vector2(0, 1), half_w + 2, 2)
	PixelDraw.rounded_rect(self, Rect2(bc.x - half_w, bc.y - 4, half_w * 2, 5), 2, PixelDraw.CREAM)
	PixelDraw.px(self, Rect2(bc.x - half_w + 4, bc.y - 2, half_w * 2 - 8, 1), PixelDraw.CREAM_DARK)


func _draw_fish(c: Vector2, col: Color) -> void:
	var body := PackedVector2Array()
	for i in range(24):
		var a: float = TAU * float(i) / 24.0
		body.append(PixelDraw.snap(c + Vector2(cos(a) * 22, sin(a) * 11) + Vector2(-4, 0)))
	var tail := PackedVector2Array([c + Vector2(14, 0), c + Vector2(28, -10), c + Vector2(24, 0), c + Vector2(28, 10)])
	PixelDraw.outlined_poly(self, tail, col)
	PixelDraw.outlined_poly(self, body, col)
	PixelDraw.disc(self, c + Vector2(-19, -3), 1.5, PixelDraw.OUTLINE)
	PixelDraw.line(self, c + Vector2(-14, -6), c + Vector2(-14, 6), col.darkened(0.25))
	for x in [-6, 2, 10]:
		PixelDraw.line(self, c + Vector2(x, -8), c + Vector2(x + 2, -6), col.darkened(0.2))


func _draw_glass(bc: Vector2) -> void:
	var r := Rect2(bc.x - 17, bc.y - 52, 34, 52)
	PixelDraw.shadow(self, bc + Vector2(0, 1), 20, 2)
	PixelDraw.rounded_rect(self, r, 3, GLASS_COL)
	# Tuxedo bib (cream gelato front) + bow tie
	var bib := PackedVector2Array([Vector2(bc.x - 9, r.position.y + 6), Vector2(bc.x + 9, r.position.y + 6), Vector2(bc.x + 5, bc.y - 6), Vector2(bc.x - 5, bc.y - 6)])
	draw_colored_polygon(bib, PixelDraw.CREAM)
	PixelDraw.disc(self, Vector2(bc.x - 4, r.position.y + 7), 3, PixelDraw.COCOA)
	PixelDraw.disc(self, Vector2(bc.x + 4, r.position.y + 7), 3, PixelDraw.COCOA)
	PixelDraw.disc(self, Vector2(bc.x, r.position.y + 7), 1.5, PixelDraw.HONEY)
	# Rim highlight
	PixelDraw.hl(self, Rect2(r.position.x + 3, r.position.y + 2, 1, 10), Color(PixelDraw.MILK, 0.35))


func _draw_ghosts() -> void:
	# Sage fill pulsing 0.35..0.75 at 1.5 Hz (steady under reduced motion), honey outline.
	var blink: float = 0.55 if reduced_motion() else 0.55 + 0.2 * sin(elapsed * TAU * 1.5)
	if mode == "drag":
		for i in range(targets.size()):
			if _target_taken(i):
				continue
			var tp: Vector2 = targets[i]["pos"]
			_draw_ghost_at(String(targets[i]["kind"]), tp, blink)
		return
	if placed.size() >= count:
		return
	var idx: int = placed.size()
	var gp := Vector2(target_x, _landing_y(idx))
	_draw_ghost_at(item, gp, blink)
	# Honey down-arrow under the counter edge at the target x (shape cue, not colour only).
	var ax: float = roundf(target_x)
	var ay: float = COUNTER_Y + 8
	for row in range(4):
		draw_rect(Rect2(ax - 4 + row, ay + row, 9 - row * 2, 1), PixelDraw.HONEY, true)
	draw_rect(Rect2(ax - 1, ay - 4, 3, 4), PixelDraw.HONEY, true)
	PixelDraw.px(self, Rect2(ax - 5, ay - 1, 11, 1), PixelDraw.OUTLINE)
	PixelDraw.px(self, Rect2(ax, ay + 4, 1, 1), PixelDraw.OUTLINE)


func _draw_ghost_at(kind: String, p: Vector2, alpha: float) -> void:
	var sz: Vector2 = _size_of(kind)
	var r := Rect2(PixelDraw.snap(p - sz * 0.5) - Vector2(2, 2), sz.round() + Vector2(4, 4))
	var col := Color(PixelDraw.SAGE, alpha)
	_draw_item_shape(kind, p, col, PixelDraw.HONEY)
	# Corner brackets: 2px thick, 4px long, warm outline colour (skipped on tiny targets like eyes,
	# where they would crowd the face; the honey outline + sage pulse carry those).
	if sz.x < 8.0:
		return
	r = r.grow(1.0)
	var x0: float = r.position.x
	var y0: float = r.position.y
	var x1: float = r.end.x - 2
	var y1: float = r.end.y - 2
	for c in [Vector2(x0, y0), Vector2(x1, y0), Vector2(x0, y1), Vector2(x1, y1)]:
		var corner: Vector2 = c
		var hx: float = corner.x if corner.x == x0 else corner.x - 2
		var vy: float = corner.y if corner.y == y0 else corner.y - 2
		draw_rect(Rect2(hx, corner.y, 4, 2), PixelDraw.OUTLINE, true)
		draw_rect(Rect2(corner.x, vy, 2, 4), PixelDraw.OUTLINE, true)


func _size_of(kind: String) -> Vector2:
	match kind:
		"ear":
			return Vector2(10, 9)
		"eye":
			return Vector2(4, 5)
	return _item_size()


func _draw_swing() -> void:
	var pivot := Vector2(cx, PIVOT_Y)
	# Rail + paw clip
	PixelDraw.outlined_rect(self, Rect2(cx - amp - 10, PIVOT_Y - 3, amp * 2 + 20, 3), PixelDraw.OAK)
	PixelDraw.circle(self, pivot, 3, PixelDraw.OAK_DARK)
	if placed.size() >= count:
		return
	if falling:
		_draw_item(item, fall_pos, 0.0, placed.size())
		return
	if _respawn > 0.0:
		return
	var p := Vector2(swing_x(), _hang_y())
	PixelDraw.line(self, pivot, p - Vector2(0, _item_size().y * 0.5 + 1), PixelDraw.OUTLINE)
	# Drop guide: dotted line to the landing height
	var land: float = _landing_y(placed.size())
	var pts := PackedVector2Array([p + Vector2(0, _item_size().y * 0.5 + 3), Vector2(p.x, land - _item_size().y * 0.5 - 1)])
	PixelDraw.dotted(self, pts, Color(PixelDraw.OUTLINE, 0.45), 3.0, 1.0)
	_draw_item(item, p, 0.0, placed.size())


func _draw_drag() -> void:
	var tr: Rect2 = _tray_rect()
	PixelDraw.rounded_rect(self, tr, 2, PixelDraw.OAK)
	PixelDraw.px(self, Rect2(tr.position.x + 2, tr.end.y - 3, tr.size.x - 4, 1), PixelDraw.OAK_DARK)
	var held_index: int = placed.size()
	for i in range(held_index, count):
		var in_hand: bool = i == held_index and (dragging or key_active)
		if in_hand:
			continue
		_draw_item(_kind_for(i), _tray_slot(i - held_index), 0.0, i)
	if held_index < count and _settle < 0.0:
		var kind: String = _kind_for(held_index)
		if dragging:
			PixelDraw.shadow(self, drag_pos + Vector2(0, 6), 4, 1)
			_draw_item(kind, drag_pos, 0.0, held_index)
		elif key_active:
			PixelDraw.shadow(self, key_cursor + Vector2(0, 6), 4, 1)
			_draw_item(kind, key_cursor, 0.0, held_index)
			PixelDraw.line(self, key_cursor + Vector2(-8, 0), key_cursor + Vector2(-6, 0), PixelDraw.OUTLINE)
			PixelDraw.line(self, key_cursor + Vector2(6, 0), key_cursor + Vector2(8, 0), PixelDraw.OUTLINE)
		else:
			var s: Vector2 = _tray_slot(0)
			var bob: float = 0.0 if reduced_motion() else roundf(sin(elapsed * 5.0))
			PixelDraw.line(self, s + Vector2(-1, -10 + bob), s + Vector2(1, -10 + bob), PixelDraw.CREAM)
			PixelDraw.line(self, s + Vector2(0, -9 + bob), s + Vector2(0, -9 + bob), PixelDraw.CREAM)
	if not placed.is_empty() and _settle < 0.0:
		PixelDraw.text(self, Vector2(tr.position.x, tr.end.y + 22), "RMB/Bksp: undo", PixelDraw.CREAM, 8)
	elif placed.is_empty() and not dragging and not key_active and _settle < 0.0:
		PixelDraw.text(self, Vector2(tr.position.x, tr.end.y + 22), "drag, or Space", PixelDraw.CREAM, 8)


func _tint_for(index: int) -> Color:
	if tints.is_empty():
		return PixelDraw.HONEY_LIGHT.lerp(PixelDraw.HONEY, 0.4)
	return tints[index % tints.size()]


func _draw_item(kind: String, p: Vector2, tilt: float, index: int) -> void:
	if absf(tilt) > 0.001:
		draw_set_transform(PixelDraw.snap(p), tilt, Vector2.ONE)
		_draw_item_shape(kind, Vector2.ZERO, _fill_for(kind, index), PixelDraw.OUTLINE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_draw_item_shape(kind, p, _fill_for(kind, index), PixelDraw.OUTLINE)


func _fill_for(kind: String, index: int) -> Color:
	match kind:
		"marshmallow_cat", "ear", "eye":
			return MARSH_COL if kind != "eye" else PixelDraw.OUTLINE
		"red_bean":
			return BEAN_COL
		"pancake":
			return _tint_for(index)
		"button":
			return BUTTON_COL
	return PixelDraw.CREAM


## Item drawn centred on p (fill / outline overridable for ghosts).
func _draw_item_shape(kind: String, p: Vector2, fill: Color, outline: Color) -> void:
	var c: Vector2 = PixelDraw.snap(p)
	match kind:
		"marshmallow_cat":
			var r := Rect2(c.x - 7, c.y - 4, 14, 9)
			var earl := PackedVector2Array([Vector2(c.x - 7, c.y - 3), Vector2(c.x - 6, c.y - 8), Vector2(c.x - 2, c.y - 4)])
			var earr := PackedVector2Array([Vector2(c.x + 7, c.y - 3), Vector2(c.x + 6, c.y - 8), Vector2(c.x + 2, c.y - 4)])
			if PixelDraw.legacy():
				for e in [earl, earr]:
					draw_colored_polygon(e, outline)
				PixelDraw.rounded_rect(self, r, 2, fill, outline)
				draw_rect(Rect2(c.x - 6, c.y - 4, 2, 1), fill, true)
				draw_rect(Rect2(c.x + 4, c.y - 4, 2, 1), fill, true)
				draw_rect(Rect2(c.x - 6, c.y - 5, 1, 1), fill, true)
				draw_rect(Rect2(c.x + 5, c.y - 5, 1, 1), fill, true)
			else:
				# B..F: the head is food, not a patron: ears + head get the full ow() outer outline
				# (ears grown outward, ear fill only on the inner row so the top edge keeps ow()).
				for e in [earl, earr]:
					for gp in Geometry2D.offset_polygon(e, float(PixelDraw.ow() - 1), Geometry2D.JOIN_MITER):
						draw_colored_polygon(gp, outline)
				PixelDraw.rounded_rect(self, r, 2, fill, outline)
				draw_rect(Rect2(c.x - 6, c.y - 4, 2, 1), fill, true)
				draw_rect(Rect2(c.x + 4, c.y - 4, 2, 1), fill, true)
			if fill.a > 0.9:
				draw_rect(Rect2(c.x - 3, c.y - 1, 1, 2), PixelDraw.OUTLINE, true)
				draw_rect(Rect2(c.x + 2, c.y - 1, 1, 2), PixelDraw.OUTLINE, true)
				draw_rect(Rect2(c.x - 5, c.y + 1, 2, 1), PixelDraw.BLUSH, true)
				draw_rect(Rect2(c.x + 3, c.y + 1, 2, 1), PixelDraw.BLUSH, true)
				draw_rect(Rect2(c.x - 1, c.y + 1, 2, 1), PixelDraw.OUTLINE, true)
		"red_bean":
			PixelDraw.rounded_rect(self, Rect2(c.x - 3, c.y - 2, 7, 5), 2, fill, outline)
			if fill.a > 0.9:
				PixelDraw.hl(self, Rect2(c.x - 1, c.y - 1, 1, 1), Color(PixelDraw.MILK, 0.6))
		"pancake":
			PixelDraw.rounded_rect(self, Rect2(c.x - 15, c.y - 3, 30, 6), 2, fill, outline)
			if fill.a > 0.9:
				PixelDraw.hl(self, Rect2(c.x - 12, c.y + 1, 24, 1), fill.darkened(0.15))
		"button":
			PixelDraw.circle(self, c, 3.5, fill, outline)
			if fill.a > 0.9:
				draw_rect(Rect2(c.x - 1, c.y - 1, 1, 1), PixelDraw.CREAM_DARK, true)
				draw_rect(Rect2(c.x + 1, c.y - 1, 1, 1), PixelDraw.CREAM_DARK, true)
		"ear":
			var tri := PackedVector2Array([Vector2(c.x - 5, c.y + 4), Vector2(c.x, c.y - 5), Vector2(c.x + 5, c.y + 4)])
			PixelDraw.outlined_poly(self, tri, fill, outline)
			if fill.a > 0.9:
				draw_rect(Rect2(c.x - 1, c.y, 3, 3), PixelDraw.BLUSH, true)
		"eye":
			if fill.a > 0.9:
				PixelDraw.rounded_rect(self, Rect2(c.x - 2, c.y - 2, 4, 5), 1, fill, outline)
				PixelDraw.hl(self, Rect2(c.x - 1, c.y - 1, 1, 1), PixelDraw.MILK)
			else:
				PixelDraw.rounded_rect(self, Rect2(c.x - 2, c.y - 2, 4, 5), 1, fill, outline)
		_:
			PixelDraw.circle(self, c, 3, fill, outline)


func _draw_pop() -> void:
	if _pop_t >= POP_SEC or _pop_text == "":
		return
	var k: float = clampf(_pop_t / POP_SEC, 0.0, 1.0)
	var rm: bool = reduced_motion()
	if _pop_score >= 0.85 and not rm:
		var n: int = 8 if _pop_score >= 1.0 else 5
		for i in range(n):
			var a: float = TAU * float(i) / float(n) + 0.4
			PixelDraw.sparkle(self, _pop_pos + Vector2(cos(a), sin(a)) * (6.0 + 12.0 * k), 2 if i % 2 == 0 else 1, PixelDraw.HONEY_LIGHT if i % 2 == 0 else PixelDraw.CREAM)
	var stars: int = StopRing._stars_for(_pop_score)
	var lift: float = 0.0 if rm else roundf(6.0 * k)
	var top: Vector2 = _pop_pos + Vector2(0, -12 - lift)
	for s in range(stars):
		PixelDraw.star(self, top + Vector2(-7 + s * 7 - (stars - 1) * 0.0, 0), 3.0, PixelDraw.HONEY)
	var w: float = PixelDraw.text_width(_pop_text) + 8
	var area: Rect2 = safe_rect()
	var bx: float = clampf(_pop_pos.x + 14, area.position.x, area.end.x - w)
	var r := Rect2(bx, clampf(_pop_pos.y - 26 - lift, 36, 160), w, 13)
	PixelDraw.rounded_rect(self, r, 3, PixelDraw.CREAM)
	PixelDraw.text(self, r.position + Vector2(4, 10), _pop_text, PixelDraw.OUTLINE, 8)


func _draw_counter_pips() -> void:
	var area: Rect2 = safe_rect()
	var y: float = 168
	var x0: float = area.get_center().x - (count - 1) * 5.0
	for i in range(count):
		var p := Vector2(x0 + i * 10, y)
		if i < placed.size():
			PixelDraw.circle(self, p, 3, _fill_for(String(placed[i]["kind"]), i))
		else:
			PixelDraw.circle(self, p, 3, PixelDraw.OAK_DARK)
			PixelDraw.disc(self, p, 1, PixelDraw.OAK)
