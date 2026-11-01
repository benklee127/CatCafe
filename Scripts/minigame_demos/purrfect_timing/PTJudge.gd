extends RefCounted

## Purr-fect Timing judgement + scoring. Pure logic, no nodes (the probe tests it directly).
##
## Windows (Cozy default): |delta| <= 120 ms "purrfect", <= 220 ms "good", otherwise "ok".
## Leniency multiplies both windows (x1 / x1.5 / x2). A per-step `scale` widens them further
## for slow, non-musical timers (the oven uses x3).
## Calibration: offset_ms is subtracted from every input time (+ = "I tend to hit late").
##
## Scoring never punishes:
##   * there is no miss/fail judgement; a missed or late beat is simply "ok" (40% credit).
##   * the Purr chain counts every purrfect/good hit of the order and NEVER resets; its bonus
##     (+$1 per 5, max +$3) can only grow.
##   * best_combo (longest unbroken run) is a brag stat on the result card only; it does not
##     touch money or grade.

const BASE_PURRFECT_MS := 120.0
const BASE_GOOD_MS := 220.0
const LENIENCY_VALUES: Array[float] = [1.0, 1.5, 2.0]
const LENIENCY_NAMES: Array[String] = ["Cozy  (x1)", "Comfy  (x1.5)", "Sleepy  (x2)"]
const POINTS: Dictionary = {"purrfect": 1.0, "good": 0.75, "ok": 0.4}
const GRADE_S := 0.9
const GRADE_A := 0.75
const GRADE_B := 0.55
const CHAIN_PER_BONUS := 5
const CHAIN_BONUS_MAX := 3

var leniency: float = 1.0
var offset_ms: float = 0.0

var counts: Dictionary = {"purrfect": 0, "good": 0, "ok": 0}
var chain: int = 0
var streak: int = 0
var best_combo: int = 0
var points: float = 0.0
var history: Array[String] = []
var tags: Array[String] = []


func purrfect_window(scale: float = 1.0) -> float:
	return BASE_PURRFECT_MS * leniency * scale / 1000.0


func good_window(scale: float = 1.0) -> float:
	return BASE_GOOD_MS * leniency * scale / 1000.0


## Input time corrected by the calibration offset.
func corrected(t_input: float) -> float:
	return t_input - offset_ms / 1000.0


## "purrfect" / "good" / "ok" for an already-corrected delta (seconds, input - target).
func judge_delta(delta_s: float, scale: float = 1.0) -> String:
	var a: float = absf(delta_s)
	if a <= purrfect_window(scale) + 0.000001:
		return "purrfect"
	if a <= good_window(scale) + 0.000001:
		return "good"
	return "ok"


func reset_score() -> void:
	counts = {"purrfect": 0, "good": 0, "ok": 0}
	chain = 0
	streak = 0
	best_combo = 0
	points = 0.0
	history.clear()
	tags.clear()


func add(j: String, tag: String = "") -> void:
	if not counts.has(j):
		j = "ok"
	counts[j] = int(counts[j]) + 1
	points += float(POINTS[j])
	history.append(j)
	tags.append(tag)
	if j == "ok":
		streak = 0  # display only: the chain and its bonus are untouched
	else:
		chain += 1
		streak += 1
		best_combo = maxi(best_combo, streak)


## Drops every judgement carrying `tag` (a parked step restarts cleanly). Recomputes all.
func drop_tag(tag: String) -> void:
	var keep_j: Array[String] = []
	var keep_t: Array[String] = []
	for i in history.size():
		if tags[i] != tag:
			keep_j.append(history[i])
			keep_t.append(tags[i])
	reset_score()
	for i in keep_j.size():
		add(keep_j[i], keep_t[i])


func total() -> int:
	return history.size()


func accuracy() -> float:
	if history.is_empty():
		return 1.0
	return points / float(history.size())


func chain_bonus() -> int:
	return mini(CHAIN_BONUS_MAX, floori(float(chain) / float(CHAIN_PER_BONUS)))


func grade() -> String:
	var acc: float = accuracy()
	if acc >= GRADE_S - 0.000001:
		return "S"
	if acc >= GRADE_A - 0.000001:
		return "A"
	if acc >= GRADE_B - 0.000001:
		return "B"
	return "C"


func base_money(base_price: int) -> int:
	return int(roundf(float(base_price) * (0.6 + 0.6 * accuracy())))


func money(base_price: int) -> int:
	return base_money(base_price) + chain_bonus()


func grade_title(g: String) -> String:
	match g:
		"S":
			return "PURR-FECT!"
		"A":
			return "LOVELY!"
		"B":
			return "NICE!"
		_:
			return "STILL TASTY!"
