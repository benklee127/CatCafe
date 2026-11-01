extends Node2D

## Base class for every game hosted by MinigameHost (cooking now; brushing, laser pointer and
## nail trimming later). No class_name: preload / extend by path.
##   extends "res://Scripts/minigame/MinigameBase.gd"
##
## Lifecycle (driven by MinigameHost):
##   1. host instantiates the game and adds it under the PlayArea SubViewport (320x180 space).
##   2. host calls setup(context) once, right after add_child.
##   3. the game runs; the host polls get_hud_info() every frame to fill header/footer/banner.
##   4. the game emits `scored(result)` exactly once when finished -> host shows the ResultCard.
##      The game may emit `request_park` (e.g. its own [x]); the host shows the park prompt.
##   5. while the park prompt is up, the host sets process_mode = DISABLED on the game (freezes
##      _process, input and timers) and restores INHERIT on "Keep cooking".

signal scored(result: Dictionary)
signal request_park

const PLAY_SIZE := Vector2(320, 180)
const DEFAULT_THRESHOLDS: Dictionary = {"S": 0.90, "A": 0.75, "B": 0.55}
const GRADE_ORDER: Array[String] = ["S", "A", "B", "C"]

var context: Dictionary = {}


## Called by the host right after the game is added to the tree. Override and call super(ctx).
func setup(ctx: Dictionary) -> void:
	context = ctx


## Info the host shows around the play area. Every key is optional:
##   title: String, subtitle: String (patron + modifier), par_sec: float, elapsed_sec: float,
##   show_clock: bool, hot_streak: int,
##   burner: {visible: bool, progress: float 0..1, state: String, label: String},
##   stations: Array[{label: String, state: "todo"|"active"|"done"|"burner", stars: int}],
##   hint: String, banner: {title: String, text: String, visible: bool, style: "hint"|"pop"|"ticket"}
func get_hud_info() -> Dictionary:
	return {}


## Whether Esc / [x] may park this game. Return false during non-interruptible moments.
func can_park() -> bool:
	return true


## Extra data to merge into the context when the game is parked (e.g. progress). Default none.
func get_park_state() -> Dictionary:
	return {}


## Letter grade for a 0..1 score. `thresholds` = {"S": min, "A": min, "B": min}; below B is C.
static func grade_for(score: float, thresholds: Dictionary = DEFAULT_THRESHOLDS) -> String:
	if score >= float(thresholds.get("S", 0.90)):
		return "S"
	if score >= float(thresholds.get("A", 0.75)):
		return "A"
	if score >= float(thresholds.get("B", 0.55)):
		return "B"
	return "C"
