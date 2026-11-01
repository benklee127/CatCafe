extends SceneTree

## Counter Cats art-style probe: boots the demo, then for each art style A-F
## flips the test panel's "Art style" option, opens an order (chaos Lively),
## lets it run with taps, shows a result card and leaves. Fails on a style that
## does not apply or an order that does not open/close.
## Usage:
##   godot --headless --path . --fixed-fps 60 --script res://Tools/probe_counter_cats_styles.gd
## Exit code 0 = pass, 1 = fail.

const SCENE := "res://Scenes/MinigameDemos/CounterCats/CounterCatsDemo.tscn"
const Art := preload("res://Scripts/minigame_demos/counter_cats/cc_art.gd")

var demo: Node
var overlay: Node
var launcher: Node
var frame: int = 0
var li: int = -1
var t0: int = 0
var fails: Array[String] = []

func _initialize() -> void:
	demo = (load(SCENE) as PackedScene).instantiate()
	root.add_child(demo)
	overlay = demo.get_node("CounterCatsOverlay")
	launcher = demo.get_node("CounterCatsLauncher")

func _process(_d: float) -> bool:
	frame += 1
	if frame < 30:
		return false
	if li < 0 or frame - t0 >= 260:
		if li >= 0:
			_finish_style()
		li += 1
		if li >= Art.STYLE_ORDER.length():
			Art.set_style("A")
			print("style probe: %d styles, %d failures" % [Art.STYLE_ORDER.length(), fails.size()])
			for f in fails:
				print("  FAIL ", f)
			quit(1 if not fails.is_empty() else 0)
			return true
		var L: String = Art.STYLE_ORDER[li]
		launcher.call("set_art_style", L)
		if Art.style != L:
			fails.append("%s: style not applied (got %s)" % [L, Art.style])
		var opts: Dictionary = {"recipe_id": ["catpuccino", "paw_cookies", "calico_parfait"][li % 3], "chaos": 2, "leniency": 1.0, "toggle": false, "preferred_cat": 0}
		var ctx: Dictionary = demo.call("build_context", opts)
		ctx["seed"] = 40 + li
		demo.call("start", ctx)
		if not bool(overlay.get("is_open")):
			fails.append("%s: order did not open" % L)
		t0 = frame
		return false
	if frame % 40 == 0:
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.pressed = (frame / 40) % 2 == 0
		root.push_input(ev)
	return false

func _finish_style() -> void:
	var L: String = Art.STYLE_ORDER[li]
	overlay.call("_on_scored", {"grade": "SABCSA"[li], "grade_text": "x", "recipe_name": "x", "elapsed": 10.0, "par": 20.0, "precision": 60.0, "speed": 20.0, "money": 0, "cats": []})
	overlay.call("serve")
	if bool(overlay.get("is_open")):
		fails.append("%s: overlay did not close" % L)
	else:
		print("style probe: %s ok (%s)" % [L, Art.STYLES[L]["desc"]])
