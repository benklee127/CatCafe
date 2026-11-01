extends Node2D

## Counter cat cameo for the Counter Cats demo. A copy of a REAL cafe cat drawn by
## the existing Cat2D rig (existing poses/expressions only) through the existing
## CatPixelPipeline, shown as a Sprite2D on the 320x180 counter. Gestures are
## whole-rig tweens plus simple procedural props (bubble, hand, hearts, swipe arc).
## The node's position is the cat's feet on the counter.

const Art := preload("res://Scripts/minigame_demos/counter_cats/cc_art.gd")
const Cat2DScene := preload("res://Scenes/Prototype3D/Cat2D.tscn")
const CatPixelPipelineScript := preload("res://Scripts/prototype3d/CatPixelPipeline.gd")

const VP: int = 56
const FOOT_Y: int = 53
const RIG_VIEW_UNITS: float = 76.8

var info: Dictionary = {}          # name, mood, trust, helper, shy, ...
var cat2d: Node2D = null
var pet_progress: float = 0.0      # 0..1 ring while a pet is held
var swipe_t: float = -1.0          # >= 0 while the paw-swipe arc shows
var swipe_dir: float = -1.0
var glint: bool = false            # helper gold collar glint
var assist_glow: bool = false      # paw icon glows (Paw Assist offer)
var sniffing: bool = false
var purring: float = 0.0

var _vp: SubViewport
var _pipe: Node
var _sprite: Sprite2D
var _rig: Node2D                   # sprite + props, tweened for hops/lunges
var _bubble: Sprite2D
var _hand: Sprite2D
var _fx: Node2D
var _t: float = 0.0
var _move_tw: Tween
var _gest_tw: Tween

func setup(p_info: Dictionary) -> void:
	info = p_info
	_rig = Node2D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_vp = SubViewport.new()
	_vp.name = "CatVP"
	_vp.size = Vector2i(VP, VP)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	_vp.snap_2d_transforms_to_pixel = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	cat2d = Cat2DScene.instantiate()
	cat2d.position = Vector2(VP / 2.0, FOOT_Y)
	cat2d.scale = Vector2.ONE * (float(VP) / RIG_VIEW_UNITS)
	_vp.add_child(cat2d)
	var def = info.get("cat_def", {})
	if def is Dictionary and not (def as Dictionary).is_empty() and cat2d.has_method("apply_genome"):
		var g: Dictionary = def.get("genome", {}) if def.get("genome", {}) is Dictionary else {}
		if g.is_empty() and def.get("visual", {}) is Dictionary:
			g = def.get("visual", {})
		cat2d.call("apply_genome", g if not g.is_empty() else def)
	if cat2d.has_method("set_pixel_art"):
		cat2d.call("set_pixel_art", true)
	_pipe = CatPixelPipelineScript.new()
	_pipe.call("setup", self, _vp, cat2d)
	_pipe.call("set_pixel", true)
	_pipe.call("set_active", true)
	_sprite = Sprite2D.new()
	_sprite.name = "CatSprite"
	_sprite.centered = false
	_sprite.offset = Vector2(-VP / 2.0, -FOOT_Y)
	_sprite.texture = _pipe.call("get_texture")
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rig.add_child(_sprite)
	_bubble = Sprite2D.new()
	_bubble.name = "Bubble"
	_bubble.position = Vector2(10, -46)
	_bubble.visible = false
	_rig.add_child(_bubble)
	_hand = Sprite2D.new()
	_hand.name = "Hand"
	_hand.texture = Art.hand()
	_hand.visible = false
	_rig.add_child(_hand)
	_fx = Node2D.new()
	_fx.name = "FX"
	add_child(_fx)
	_fx.draw.connect(_draw_fx)
	set_pose("sit")
	set_expression(_mood_face())

func cat_name() -> String:
	return str(info.get("name", "Cat"))

func _mood_face() -> String:
	match str(info.get("mood", "calm")):
		"fizzy":
			return "smug"
		"frazzled":
			return "worried"
	return "open"

func rest_face() -> void:
	set_expression(_mood_face())

# ------------------------------------------------------------------ Cat2D API (existing only)

func set_pose(p: String) -> void:
	if cat2d != null and cat2d.has_method("set_pose"):
		cat2d.call("set_pose", p)
	if cat2d != null and cat2d.has_method("set_move_speed"):
		cat2d.call("set_move_speed", 1.0 if p == "walk" else 0.0)

func set_expression(e: String) -> void:
	if cat2d != null and cat2d.has_method("set_expression"):
		cat2d.call("set_expression", e)

func face_left(on: bool) -> void:
	if cat2d != null and cat2d.has_method("set_facing_left"):
		cat2d.call("set_facing_left", on)

# ------------------------------------------------------------------ motion

func walk_to(x: float, speed: float = 70.0, end_pose: String = "sit") -> Tween:
	return go_to(Vector2(x, position.y), absf(x - position.x) / maxf(speed, 1.0), end_pose)

## Move the whole cameo: walks along the counter, or hops (arc) when the height
## changes (window sill <-> counter). face_after: -1 keep, 0 right, 1 left.
func go_to(dest: Vector2, dur: float, end_pose: String = "sit", face_after: int = -1) -> Tween:
	if _move_tw != null and _move_tw.is_valid():
		_move_tw.kill()
	dur = maxf(0.05, dur)
	var from: Vector2 = position
	if absf(dest.x - from.x) > 1.0:
		face_left(dest.x < from.x)
	_move_tw = create_tween()
	if absf(dest.y - from.y) > 2.0:
		set_pose("idle")
		_move_tw.tween_method(func(k: float) -> void:
			position = from.lerp(dest, k) + Vector2(0, -sin(k * PI) * 16.0), 0.0, 1.0, dur)
	else:
		set_pose("walk")
		_move_tw.tween_property(self, "position", dest, dur)
	_move_tw.tween_callback(func() -> void:
		position = dest
		set_pose(end_pose)
		if face_after >= 0:
			face_left(face_after == 1))
	return _move_tw

func is_moving() -> bool:
	return _move_tw != null and _move_tw.is_valid() and _move_tw.is_running()

func _gesture() -> Tween:
	if _gest_tw != null and _gest_tw.is_valid():
		_gest_tw.kill()
	_rig.position = Vector2.ZERO
	_rig.rotation = 0.0
	_rig.scale = Vector2.ONE
	_gest_tw = create_tween()
	return _gest_tw

## Telegraph: "!" bubble + a double ear-twitch hop of the whole rig.
func telegraph(kind: String = "bang") -> void:
	show_bubble(kind)
	set_expression("surprised")
	var tw := _gesture()
	for i in range(2):
		tw.tween_property(_rig, "position:y", -3.0, 0.08)
		tw.tween_property(_rig, "position:y", 0.0, 0.1)
		tw.tween_interval(0.12)

func lunge(dir: float) -> void:
	swipe_dir = dir
	swipe_t = 0.0
	set_expression("smug")
	var tw := _gesture()
	tw.tween_property(_rig, "position:x", 7.0 * dir, 0.09)
	tw.tween_property(_rig, "position:x", 0.0, 0.22)

func lean(dir: float, on: bool) -> void:
	sniffing = on
	var tw := _gesture()
	if on:
		tw.tween_property(_rig, "position:x", 5.0 * dir, 0.3)
		tw.parallel().tween_property(_rig, "rotation", 0.08 * dir, 0.3)
	else:
		tw.tween_property(_rig, "position:x", 0.0, 0.2)
		tw.parallel().tween_property(_rig, "rotation", 0.0, 0.2)

func happy_bounce() -> void:
	set_expression("happy")
	var tw := _gesture()
	tw.tween_property(_rig, "scale", Vector2(1.08, 0.92), 0.08)
	tw.tween_property(_rig, "scale", Vector2(0.95, 1.06), 0.1)
	tw.tween_property(_rig, "scale", Vector2.ONE, 0.12)

func sneeze() -> void:
	set_expression("surprised")
	var tw := _gesture()
	tw.tween_property(_rig, "position:y", 2.0, 0.06)
	tw.tween_property(_rig, "position:y", -2.0, 0.08)
	tw.tween_property(_rig, "position:y", 0.0, 0.1)

func show_bubble(kind: String) -> void:
	match kind:
		"bang":
			_bubble.texture = Art.bang()
		"pets":
			_bubble.texture = Art.want_pets()
		"paw":
			_bubble.texture = Art.paw(Art.GOLD, "paw_gold")
		_:
			_bubble.texture = Art.bang()
	_bubble.visible = true

func hide_bubble() -> void:
	_bubble.visible = false

## Hit box for pet / boop / assist clicks (generous, in counter space).
func hit(p: Vector2) -> bool:
	var r := Rect2(position + Vector2(-22, -40), Vector2(44, 44))
	return r.has_point(p)

func head_pos() -> Vector2:
	return position + Vector2(0, -34)

func _process(delta: float) -> void:
	_t += delta
	if swipe_t >= 0.0:
		swipe_t += delta
		if swipe_t > 0.35:
			swipe_t = -1.0
	if purring > 0.0:
		purring = maxf(0.0, purring - delta)
	if _bubble.visible:
		_bubble.position.y = -46.0 + roundf(sin(_t * 6.0))
	_hand.visible = pet_progress > 0.0
	if _hand.visible:
		_hand.position = Vector2(roundf(sin(_t * 14.0) * 4.0), -38)
	_fx.queue_redraw()

func _draw_fx() -> void:
	var o: Vector2 = _rig.position
	# pet progress ring
	if pet_progress > 0.0:
		var c: Vector2 = o + Vector2(0, -20)
		if Art.is_a():
			_fx.draw_arc(c, 24.0, 0, TAU, 32, Color(Art.OUTLINE, 0.35), 3.0, false)
		else:
			# art styles B-F: solid dark track with a cream groove (thick outline look)
			_fx.draw_arc(c, 24.0, 0, TAU, 32, Art.OUTLINE, 3.0 + 2.0 * Art.ow(), false)
			_fx.draw_arc(c, 24.0, 0, TAU, 32, Color("#F3E6D3"), 3.0, false)
		_fx.draw_arc(c, 24.0, -PI / 2.0, -PI / 2.0 + TAU * pet_progress, 32, Art.PINK, 3.0, false)
	# paw-swipe arc
	if swipe_t >= 0.0:
		var a: float = swipe_t / 0.35
		var base: Vector2 = o + Vector2(14.0 * swipe_dir, -14)
		for i in range(3):
			var r: float = 6.0 + float(i) * 3.0
			var s0: float = (PI * 0.9 if swipe_dir < 0 else -PI * 0.1)
			_fx.draw_arc(base, r, s0 + a * 0.6, s0 + 1.0 + a * 0.6, 6, Color(Art.CREAM, 1.0 - a), 1.0, false)
	# purr lines
	if purring > 0.0:
		var k: float = fmod(_t * 3.0, 1.0)
		for i in range(2):
			var x: float = -16.0 - float(i) * 4.0
			var y: float = -18.0 - k * 6.0 - float(i) * 3.0
			_fx.draw_line(o + Vector2(x, y), o + Vector2(x - 3, y - 2), Color(Art.OUTLINE, 1.0 - k), 1.0)
			_fx.draw_line(o + Vector2(-x, y), o + Vector2(-x + 3, y - 2), Color(Art.OUTLINE, 1.0 - k), 1.0)
	# helper glint on the collar
	if glint and fmod(_t, 1.6) < 0.25:
		var gp: Vector2 = o + Vector2(6, -16)
		_fx.draw_rect(Rect2(gp + Vector2(-1, -3), Vector2(2, 6)), Art.GOLD)
		_fx.draw_rect(Rect2(gp + Vector2(-3, -1), Vector2(6, 2)), Art.GOLD)
		_fx.draw_rect(Rect2(gp + Vector2(-1, -1), Vector2(2, 2)), Color.WHITE)
	# sniff dots
	if sniffing:
		var k2: float = fmod(_t * 2.5, 1.0)
		for i in range(3):
			var dx: float = (14.0 + float(i) * 4.0 + k2 * 3.0) * (-1.0 if (cat2d != null and bool(cat2d.get("facing_left"))) else 1.0)
			_fx.draw_rect(Rect2(o + Vector2(dx, -26 + (i % 2)), Vector2(2, 2) if Art.chunky() else Vector2(1, 1)), Art.OUTLINE)
