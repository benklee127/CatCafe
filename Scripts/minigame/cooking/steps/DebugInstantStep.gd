extends "res://Scripts/minigame/cooking/steps/StepBase.gd"

## Placeholder / test verb. Two modes:
##   * Injected: params.debug_accuracy (float) -> finishes after params.debug_delay seconds
##     (default 0) with that accuracy and params.debug_time (or elapsed) as time_sec.
##     Used by Tools/probe_cooking_framework.gd and CookingGame's step_override.
##   * Interactive (no debug_accuracy): a "verb coming soon" card. Tap (LMB/Space) while the
##     bouncing marker crosses the paw zone; accuracy from distance. Lets the demo play every
##     recipe before the real verbs exist. A back_burner stand-in also finishes on O.

var _marker: float = 0.0
var _dir: float = 1.0


func _finish_injected() -> void:
	var t: float = float(params.get("debug_time", -1.0))
	finish(float(params.get("debug_accuracy", 1.0)), t)


func _process(delta: float) -> void:
	if not is_running():
		return
	if params.has("debug_accuracy"):
		if elapsed >= float(params.get("debug_delay", 0.0)):
			_finish_injected()
		return
	var speed: float = 0.9 / time_scale()
	_marker += _dir * speed * delta
	if _marker >= 1.0:
		_marker = 1.0
		_dir = -1.0
	elif _marker <= 0.0:
		_marker = 0.0
		_dir = 1.0
	queue_redraw()


func _accuracy_now() -> float:
	var half: float = 0.08 * window_scale()
	var d: float = absf(_marker - 0.5)
	if d <= half:
		return 1.0
	if d <= half * 2.0:
		return 0.85
	if d <= half * 3.5:
		return 0.65
	return 0.4


func _on_tap(_pos: Vector2, _from_mouse: bool) -> void:
	if params.has("debug_accuracy"):
		return
	if String(params.get("_type", "")) == "back_burner":
		return
	finish(_accuracy_now())
	get_viewport().set_input_as_handled()


func _on_burner_key() -> void:
	if params.has("debug_accuracy"):
		return
	if String(params.get("_type", "")) == "back_burner":
		finish(0.85)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if params.has("debug_accuracy"):
		return
	if String(params.get("_type", "")) == "back_burner":
		var s: Rect2 = slot_rect()
		PixelDraw.circle(self, s.get_center(), 16, PixelDraw.CREAM)
		PixelDraw.ring(self, s.get_center(), 12, 3, PixelDraw.HONEY, -PI * 0.5, -PI * 0.5 + TAU * clampf(elapsed / 4.0, 0.0, 1.0))
		PixelDraw.text(self, s.get_center() + Vector2(-3, 3), "O", PixelDraw.OUTLINE, 8)
		return
	var area: Rect2 = safe_rect()
	var card := Rect2(area.get_center() - Vector2(90, 40), Vector2(180, 80))
	PixelDraw.rounded_rect(self, card, 4, PixelDraw.CREAM)
	PixelDraw.text(self, card.position + Vector2(8, 14), "%s (stand-in)" % String(params.get("_type", "?")).to_upper(), PixelDraw.OUTLINE, 8)
	var track := Rect2(card.position + Vector2(12, 40), Vector2(156, 12))
	var inner: Rect2 = PixelDraw.meter(self, track, 0.0, PixelDraw.SAGE)
	var half: float = 0.08 * window_scale()
	PixelDraw.meter_band(self, inner, 0.5 - half * 2.0, 0.5 + half * 2.0, PixelDraw.HONEY_LIGHT)
	PixelDraw.meter_band(self, inner, 0.5 - half, 0.5 + half, PixelDraw.SAGE)
	PixelDraw.paw(self, Vector2(inner.get_center().x, inner.position.y - 5), 3, PixelDraw.OUTLINE)
	var mx: float = inner.position.x + inner.size.x * _marker
	PixelDraw.outlined_rect(self, Rect2(mx - 2, track.position.y - 3, 4, track.size.y + 6), PixelDraw.HONEY)
	PixelDraw.text(self, card.position + Vector2(8, 70), "Tap in the paw zone!", PixelDraw.OUTLINE, 8)
