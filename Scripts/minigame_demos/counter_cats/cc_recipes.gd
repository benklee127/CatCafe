extends RefCounted

## Counter Cats demo recipes, tuning and scoring (pure data + static math).
## Three verbs: "ring" (stop-the-ring timing tap), "pour" (hold, release on the
## line), "drop" (pendulum place/drop). The recipe picker doubles as difficulty.

const RECIPES: Array = [
	{
		"id": "catpuccino", "name": "Catpuccino", "difficulty": "Easy", "price_mult": 1.0, "par_sec": 26.0,
		"vessel": "mug",
		"steps": [
			{"type": "ring", "label": "Grind", "sweep_sec": 1.9, "hits": 1, "item": "puck"},
			{"type": "ring", "label": "Tamp", "sweep_sec": 1.8, "hits": 1, "item": "puck"},
			{"type": "pour", "label": "Pull shot", "target": 0.35, "band": 0.14, "rate": 0.26, "color": "espresso", "item": "beans"},
			{"type": "pour", "label": "Steam milk", "target": 0.78, "band": 0.14, "rate": 0.28, "color": "milk", "item": "jug"},
			{"type": "drop", "label": "Foam paw", "swing_hz": 0.7, "item": "paw", "targets": [0.0]},
		],
	},
	{
		"id": "paw_cookies", "name": "Paw-Print Cookies", "difficulty": "Medium", "price_mult": 1.2, "par_sec": 30.0,
		"vessel": "bowl",
		"steps": [
			{"type": "pour", "label": "Batter", "target": 0.6, "band": 0.12, "rate": 0.3, "color": "dough", "item": "jug"},
			{"type": "ring", "label": "Stamp x3", "sweep_sec": 1.5, "hits": 3, "item": "tray", "vessel": "tray"},
			{"type": "ring", "label": "Bake", "sweep_sec": 1.7, "hits": 1, "item": "tray", "vessel": "tray"},
			{"type": "drop", "label": "Sugar fish x2", "swing_hz": 0.8, "item": "fish", "vessel": "tray", "targets": [-22.0, 22.0]},
		],
	},
	{
		"id": "calico_parfait", "name": "Calico Parfait", "difficulty": "Fancy", "price_mult": 1.5, "par_sec": 32.0,
		"vessel": "glass",
		"steps": [
			{"type": "pour", "label": "Mango", "target": 0.3, "band": 0.10, "rate": 0.3, "color": "mango", "item": "jug"},
			{"type": "pour", "label": "Sesame", "target": 0.6, "band": 0.10, "rate": 0.3, "color": "sesame", "item": "jug"},
			{"type": "pour", "label": "Vanilla", "target": 0.85, "band": 0.10, "rate": 0.3, "color": "vanilla", "item": "jug"},
			{"type": "ring", "label": "Chill", "sweep_sec": 1.4, "hits": 2, "item": "glass"},
			{"type": "drop", "label": "Ear wafers x2", "swing_hz": 0.95, "item": "wafer", "targets": [-5.0, 5.0]},
		],
	},
]

const CHAOS_NAMES: Array[String] = ["Off", "Cozy", "Lively"]
const CHAOS_CAP: Array[int] = [0, 1, 2]
const LENIENCY: Array[float] = [1.0, 1.5, 2.0]

# Ring judge windows (seconds) and scores. Leniency + helper widen windows.
const RING_WINDOWS: Array = [[0.06, 1.0, "Perfect!"], [0.12, 0.85, "Great!"], [0.20, 0.65, "Good"]]
const RING_OK: float = 0.4
const RING_TARGET_R: float = 14.0
const RING_START_R: float = 46.0
const RING_SWEEPS_BEFORE_AUTO: int = 3

# Pendulum drop: perfect within 4 px, zero at 24 px (x leniency).
const DROP_PERFECT_PX: float = 4.0
const DROP_ZERO_PX: float = 24.0
const DROP_SWINGS_BEFORE_AUTO: int = 4

# Grades on a 0..100 dish score: 70 precision + 30 speed.
const GRADE_MIN: Dictionary = {"S": 90.0, "A": 75.0, "B": 55.0}
const MONEY_BY_GRADE: Dictionary = {"S": 9, "A": 6, "B": 4, "C": 3}

# Cat care, per cat per round (judges: cap low, shoo/ignore neutral).
const PET_OVERSTIM: float = -8.0
const PET_TRUST: float = 2.0
const ASSIST_TRUST: float = 1.0
const CAP_OVERSTIM: float = -15.0
const CAP_TRUST: float = 4.0
const PET_HOLD_SEC: float = 0.6
const HELPER_TRUST: float = 70.0
const HELPER_WIDEN: float = 1.15

static func recipe_by_index(i: int) -> Dictionary:
	return RECIPES[clampi(i, 0, RECIPES.size() - 1)]

static func recipe_by_id(id: String) -> Dictionary:
	for r in RECIPES:
		if r["id"] == id:
			return r
	return RECIPES[0]

static func ring_judge(err_sec: float, widen: float) -> Array:
	var e: float = absf(err_sec)
	for w in RING_WINDOWS:
		if e <= float(w[0]) * widen:
			return [float(w[1]), String(w[2])]
	return [RING_OK, "Ok"]

## Pour: band = full width (fraction of the vessel); perfect core = a third of it.
static func pour_judge(err: float, band: float, widen: float) -> Array:
	var half: float = band * 0.5 * widen
	var e: float = absf(err)
	var acc: float = clampf(1.0 - e / (half * 3.0), 0.0, 1.0)
	if e <= half / 3.0:
		return [1.0, "Perfect!"]
	if e <= half:
		return [maxf(acc, 0.85), "Great!"]
	if e <= half * 2.0:
		return [maxf(acc, 0.55), "Good"]
	return [maxf(acc, 0.3), "Ok"]

static func drop_judge(off_px: float, widen: float) -> Array:
	var p: float = DROP_PERFECT_PX * widen
	var z: float = DROP_ZERO_PX * widen
	var e: float = absf(off_px)
	if e <= p:
		return [1.0, "Perfect!"]
	var acc: float = clampf(1.0 - (e - p) / (z - p), 0.0, 1.0)
	if acc >= 0.7:
		return [acc, "Great!"]
	if acc >= 0.4:
		return [acc, "Good"]
	return [maxf(acc, 0.3), "Ok"]

static func speed_factor(elapsed: float, par: float) -> float:
	if elapsed <= par:
		return 1.0
	return clampf(1.0 - (elapsed - par) / par, 0.0, 1.0)

static func grade_for(score: float) -> String:
	if score >= GRADE_MIN["S"]:
		return "S"
	if score >= GRADE_MIN["A"]:
		return "A"
	if score >= GRADE_MIN["B"]:
		return "B"
	return "C"

static func money_for(grade: String, price_mult: float) -> int:
	return int(round(float(MONEY_BY_GRADE.get(grade, 3)) * price_mult))

## Capped care delta for one cat for one round.
static func care_delta(pets: int, assists: int) -> Dictionary:
	var o: float = maxf(CAP_OVERSTIM, PET_OVERSTIM * float(pets))
	var t: float = minf(CAP_TRUST, PET_TRUST * float(pets) + ASSIST_TRUST * float(assists))
	return {"overstim": o, "trust": t}

static func mood_for(overstim: float, threshold: float) -> String:
	var r: float = overstim / maxf(threshold, 0.001)
	if r < 0.4:
		return "calm"
	if r < 0.8:
		return "fizzy"
	return "frazzled"
