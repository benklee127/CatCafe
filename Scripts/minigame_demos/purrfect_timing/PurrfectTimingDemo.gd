extends Node

## Purr-fect Timing playable demo root. The live cafe (MainLevel3D.tscn, unmodified) runs as
## the background; this adds the F12 test panel (PTLauncher) and the minigame window
## (PTOverlay). Opening an order pauses the cafe; serving unpauses and pays via add_money.

const LauncherScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTLauncher.gd")
const OverlayScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTOverlay.gd")
const PX := preload("res://Scripts/minigame_demos/purrfect_timing/PTPixel.gd")

var level: Node = null
var launcher: CanvasLayer = null
var overlay: CanvasLayer = null


func _ready() -> void:
	# `-- --pt-art-style=C` forces an art style (A..F) at boot; the F12 panel switches it live.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pt-art-style="):
			PX.set_style(a.get_slice("=", 1))
	level = get_node_or_null("MainLevel3D")
	overlay = OverlayScript.new()
	overlay.name = "PurrfectOverlay"
	overlay.set("level", level)
	add_child(overlay)
	launcher = LauncherScript.new()
	launcher.name = "PurrfectLauncher"
	launcher.set("overlay", overlay)
	add_child(launcher)
	launcher.connect("start_requested", _on_start)
	launcher.connect("resume_requested", _on_resume)
	overlay.connect("order_closed", Callable(launcher, "on_order_closed"))
	overlay.connect("order_parked", Callable(launcher, "on_parked"))
	overlay.connect("order_opened", Callable(launcher, "on_order_opened"))


func _on_start(i: int) -> void:
	overlay.set("settings", launcher.call("get_settings"))
	overlay.call("open_recipe", i)


func _on_resume() -> void:
	var s: Dictionary = launcher.call("get_settings")
	overlay.set("settings", s)
	overlay.call("resume_parked")
