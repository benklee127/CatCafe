extends CanvasLayer

## Generic minigame overlay (cooking now; brushing / laser pointer / nail trim later).
## Scene: res://UI/Minigame/MinigameHost.tscn (CanvasLayer layer 20, PROCESS_MODE_ALWAYS; above
## HUD3D (5) and DecorPlacement3D's PlacementCursorLayer (12)).
## Docs + integration hook points: Docs/MINIGAMES.md.
##
## API
##   open(game, context)  game = Script | PackedScene | "res://...gd|.tscn" path | Node instance
##                        extending MinigameBase. Pauses the tree (remembers the previous state).
##   close()              hard close -> emits aborted(context) if a game was running; if the
##                        result card is up the dish was served, so it emits finished (next_order
##                        false) instead and the order is still paid.
##   is_open() -> bool
##   request_park() / confirm_park() / cancel_park()       (Esc / [x] use these)
##   choose_result(next_order: bool)                      (ResultCard buttons use this)
##   get_game() -> Node
## Signals (all emitted AFTER the tree is unpaused, so handlers can tween / toast / pay):
##   finished(context, result)   result from the game's `scored`, plus result.next_order: bool
##   parked(context)             the order goes back to pending; context keeps its seed
##   aborted(context)            closed without a result (close() or a broken game)
##   opened(context)
##
## Context keys the host reads: settings {reduced_motion, ...}, has_next_order: bool.
## The host writes context["_play_scale"] (logical screen px per art px, rounded) before calling
## game.setup(). The PlayArea itself is upscaled by a whole number of PHYSICAL pixels
## (get_physical_scale()), so the art stays crisp at any window size.

signal finished(context: Dictionary, result: Dictionary)
signal parked(context: Dictionary)
signal aborted(context: Dictionary)
signal opened(context: Dictionary)

const PixelDraw = preload("res://Scripts/minigame/cooking/PixelDraw.gd")
const KitchenArt = preload("res://Scripts/minigame/cooking/KitchenArt.gd")
const KitchenChrome = preload("res://Scripts/minigame/cooking/KitchenChrome.gd")
const THEME_PATH := "res://UI/cozy_theme.tres"
const PLAY_W := 320
const PLAY_H := 180
const HEADER_H := 58
const FOOTER_H := 58
const WIN_MARGIN_X := 16
const WIN_MARGIN_Y := 12
const VSEP := 8
const OPEN_SEC := 0.25
const HOST_LAYER := 20
## The result card ignores Enter for this long after it appears (fast tappers can't skip it).
const RESULT_GUARD_SEC := 0.45
const CONFETTI_SEC := 0.8
## Rough dish heights (art px) so the result card can size the dish area to the sprite.
const DISH_H: Dictionary = {
	"paw_print_cookies": 24, "catpuccino": 40, "purrfect_matcha_latte": 40, "tuxedo_cocoa": 38,
	"not_tuna_taiyaki": 26, "kitten_mochi": 30, "toe_bean_milk_tea": 56, "cat_nap_chamomile": 40,
	"calico_pancake_stack": 32, "tuxedo_affogato": 44,
}
const DISH_SCALE := 4
const FOOTER_FONT := 18

const C_DIM := Color(0.168627, 0.129412, 0.160784, 0.55)  # #2B2129 @ 55%
const C_CREAM := Color("#FFF6EA")
const C_OAK := Color("#C9A27A")
const C_OAK_DARK := Color("#A57C55")
const C_INK := Color("#4A3426")
const C_SAGE := Color("#8FBF9F")
const C_HONEY := Color("#E8B04B")
const C_HONEY_LIGHT := Color("#F4D58D")
const C_CREAM_DARK := Color("#F1E2CC")
const C_BLUSH := Color("#F2B8A8")

const GRADE_STYLE: Dictionary = KitchenArt.GRADE_STAMPS

## Reduced motion: no slide, no stamp pop. context.settings.reduced_motion also enables it.
var reduced_motion: bool = false
## Default settings merged into each context's "settings" (context values win).
var settings: Dictionary = {}

var _open: bool = false
var _context: Dictionary = {}
var _game: Node = null
var _result: Dictionary = {}
var _prev_paused: bool = false
var _play_scale: int = 3
var _phys_k: int = 3
var _result_age: float = 0.0
var _confetti_t: float = -1.0
var _style_cache: Dictionary = {}
var _anim: Tween = null
var _hud: Dictionary = {}

var _root: Control
var _dim: ColorRect
var _window: PanelContainer
var _title: Label
var _header_icon: Control
var _subtitle: Label
var _clock_box: VBoxContainer
var _clock_label: Label
var _clock_bar: Control
var _mood: Control
var _park_sub: Label
var _confetti: Control
var _streak: Label
var _burner_box: HBoxContainer
var _burner_ctrl: Control
var _burner_label: Label
var _close_btn: Button
var _play_stack: Control
var _svc: SubViewportContainer
var _sv: SubViewport
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label
var _stations: HBoxContainer
var _hint: Label
var _esc_label: Label
var _park_prompt: Control
var _result_card: Control
var _result_panel: PanelContainer
var _result_body: VBoxContainer
var _park_panel: PanelContainer
var _frame: Panel
## Art style (A..F) bookkeeping for the live switch: [Button, primary], [Label, colour],
## [Control, updater] (host art wrapped by KitchenChrome.art_canvas for the E / F halo / shadow).
var _buttons: Array = []
var _labels: Array = []
var _art_updaters: Array = []


func _ready() -> void:
	layer = HOST_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false
	get_viewport().size_changed.connect(_layout)
	_layout()


# --- Public API -------------------------------------------------------------------------------

func is_open() -> bool:
	return _open


func get_game() -> Node:
	return _game


func get_play_scale() -> int:
	return _play_scale


## Whole-number physical pixels per art pixel (2 at 1280x720, 3 at 1600x900, 4 at 1920x1080).
func get_physical_scale() -> int:
	return _phys_k


func open(game: Variant, context: Dictionary) -> void:
	if _open:
		push_warning("MinigameHost.open: already open; ignoring")
		return
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_clear_game()
	var node: Node = _instantiate(game)
	if node == null:
		push_error("MinigameHost.open: could not instantiate game %s" % str(game))
		aborted.emit(context)
		return
	_context = context
	var s: Dictionary = settings.duplicate()
	if context.get("settings", {}) is Dictionary:
		s.merge(context.get("settings", {}) as Dictionary, true)
	context["settings"] = s
	_result = {}
	_open = true
	_prev_paused = get_tree().paused
	get_tree().paused = true
	_root.visible = true
	_park_prompt.visible = false
	_result_card.visible = false
	_banner.visible = false
	_layout()
	context["_play_scale"] = _play_scale
	_game = node
	_sv.add_child(node)
	if node.has_signal("scored"):
		node.connect("scored", _on_game_scored)
	if node.has_signal("request_park"):
		node.connect("request_park", request_park)
	if node.has_signal("request_abort"):
		node.connect("request_abort", _on_game_abort)
	if node.has_method("setup"):
		node.call("setup", context)
	_refresh_hud()
	_header_icon.queue_redraw()
	_animate_in()
	opened.emit(context)


## Hard close (no result). Emits aborted(context).
func close() -> void:
	if not _open:
		return
	if not _result.is_empty():
		# Already served (result card up): pay on serve, never forfeit the dish.
		choose_result(false)
		return
	var ctx: Dictionary = _context
	_close_internal()
	aborted.emit(ctx)


func request_park() -> void:
	if not _open or _result_card.visible:
		return
	if _game != null and _game.has_method("can_park") and not bool(_game.call("can_park")):
		return
	var kept: int = 0
	if _game != null and _game.has_method("get_park_state"):
		var st: Variant = _game.call("get_park_state")
		if st is Dictionary and (st as Dictionary).get("resume", {}) is Dictionary:
			var rs: Variant = ((st as Dictionary).get("resume", {}) as Dictionary).get("results", [])
			kept = (rs as Array).size() if rs is Array else 0
	_park_sub.text = ("It'll wait on the counter. Your %d finished step%s stay done." % [kept, "" if kept == 1 else "s"]) if kept > 0 else "It'll wait on the counter. Same order when you come back."
	_park_prompt.visible = true
	if _game != null:
		_game.process_mode = Node.PROCESS_MODE_DISABLED


func cancel_park() -> void:
	if not _park_prompt.visible:
		return
	_park_prompt.visible = false
	if _game != null:
		_game.process_mode = Node.PROCESS_MODE_INHERIT


func confirm_park() -> void:
	if not _open:
		return
	var ctx: Dictionary = _context
	if _game != null and _game.has_method("get_park_state"):
		var st: Variant = _game.call("get_park_state")
		if st is Dictionary:
			ctx.merge(st as Dictionary, true)
	ctx["park_count"] = int(ctx.get("park_count", 0)) + 1
	_close_internal()
	parked.emit(ctx)


## ResultCard buttons: next_order = true for [Next order >].
func choose_result(next_order: bool) -> void:
	if not _open or _result.is_empty():
		return
	var ctx: Dictionary = _context
	var res: Dictionary = _result
	res["next_order"] = next_order
	_close_internal()
	finished.emit(ctx, res)


func is_result_showing() -> bool:
	return _open and _result_card.visible


func is_park_prompt_showing() -> bool:
	return _open and _park_prompt.visible


# --- Internals --------------------------------------------------------------------------------

func _instantiate(game: Variant) -> Node:
	if game is Node:
		return game as Node
	var res: Variant = game
	if game is String:
		if not ResourceLoader.exists(String(game)):
			return null
		res = load(String(game))
	if res is PackedScene:
		return (res as PackedScene).instantiate()
	if res is Script:
		var obj: Object = (res as Script).new()
		if obj is Node:
			return obj as Node
	return null


func _close_internal() -> void:
	_open = false
	_park_prompt.visible = false
	get_tree().paused = _prev_paused
	_animate_out()


func _clear_game() -> void:
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
	_game = null


func _on_game_scored(result: Dictionary) -> void:
	if not _open:
		return
	_result = result.duplicate(true)
	_show_result(_result)


func _on_game_abort(_reason: Variant = null) -> void:
	close()


func _is_reduced_motion() -> bool:
	if reduced_motion:
		return true
	var s: Variant = _context.get("settings", {})
	return s is Dictionary and bool((s as Dictionary).get("reduced_motion", false))


func _animate_in() -> void:
	var target: Vector2 = _window_target_pos()
	if _is_reduced_motion():
		_dim.color = C_DIM
		_window.position = target
		_window.modulate.a = 1.0
		return
	_dim.color = Color(C_DIM, 0.0)
	_window.position = target + Vector2(0, 48)
	_window.modulate.a = 0.0
	_anim = create_tween().set_parallel(true)
	_anim.tween_property(_dim, "color", C_DIM, OPEN_SEC)
	_anim.tween_property(_window, "position", target, OPEN_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_anim.tween_property(_window, "modulate:a", 1.0, OPEN_SEC * 0.6)


func _animate_out() -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_result_card.visible = false
	if _is_reduced_motion() or not is_inside_tree():
		_finish_hide()
		return
	_anim = create_tween().set_parallel(true)
	_anim.tween_property(_dim, "color", Color(C_DIM, 0.0), 0.18)
	_anim.tween_property(_window, "position", _window_target_pos() + Vector2(0, 40), 0.18).set_ease(Tween.EASE_IN)
	_anim.tween_property(_window, "modulate:a", 0.0, 0.18)
	_anim.chain().tween_callback(_finish_hide)


func _finish_hide() -> void:
	if _open:
		return
	_root.visible = false
	_clear_game()


func _process(delta: float) -> void:
	if _open:
		_refresh_hud()
		_result_age += delta
		if _confetti_t >= 0.0:
			_confetti_t += delta
			_confetti.queue_redraw()
			if _confetti_t > CONFETTI_SEC:
				_confetti_t = -1.0


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			if _park_prompt.visible or _result_card.visible:
				get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_ESCAPE:
			if _result_card.visible:
				choose_result(false)
			elif _park_prompt.visible:
				cancel_park()
			else:
				request_park()
			get_viewport().set_input_as_handled()
		elif _result_card.visible:
			# Only Enter confirms (Space also rings the bell, so a fast tapper would skip the card),
			# and not in the first RESULT_GUARD_SEC.
			if (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and _result_guard_over():
				choose_result(_has_next_order())
			get_viewport().set_input_as_handled()
		elif _park_prompt.visible:
			if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
				confirm_park()
			get_viewport().set_input_as_handled()


func _result_guard_over() -> bool:
	return _result_age >= RESULT_GUARD_SEC


func _on_result_button(next_order: bool) -> void:
	if _result_guard_over():
		choose_result(next_order)


func _has_next_order() -> bool:
	return bool(_context.get("has_next_order", false))


# --- Layout --------------------------------------------------------------------------------------

func _layout() -> void:
	if _root == null:
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var max_w: float = maxf(vs.x - 32.0, 360.0)
	var max_h: float = maxf(vs.y - 24.0, 300.0)
	var chrome_h: float = float(WIN_MARGIN_Y * 2 + HEADER_H + FOOTER_H + VSEP * 2)
	var chrome_w: float = float(WIN_MARGIN_X * 2)
	var avail_w: float = minf(maxf(vs.x * 0.72, 680.0), max_w) - chrome_w
	var avail_h: float = minf(vs.y * 0.86, max_h) - chrome_h
	# Integer scale in PHYSICAL pixels: canvas_items stretch multiplies logical units by f, so a
	# logical x3 at 1280x720 would be 2.4 real px per art px (uneven 2/3 px pixels).
	var f: float = _stretch_factor()
	_phys_k = maxi(1, int(floorf(minf(avail_w * f / PLAY_W, avail_h * f / PLAY_H))))
	var s: float = float(_phys_k) / f
	_play_scale = maxi(1, int(roundf(s)))
	var play := Vector2(PLAY_W * s, PLAY_H * s)
	var win_w: float = clampf(maxf(vs.x * 0.70, play.x + chrome_w), 0.0, max_w)
	var win_h: float = play.y + chrome_h
	_svc.stretch_shrink = 1
	_svc.size = Vector2(PLAY_W, PLAY_H)
	_svc.scale = Vector2(s, s)
	_play_stack.custom_minimum_size = play
	_window.custom_minimum_size = Vector2(win_w, win_h)
	_window.size = Vector2(win_w, win_h)
	if _anim == null or not _anim.is_running():
		_window.position = _window_target_pos()
	if _open:
		_context["_play_scale"] = _play_scale


## Physical pixels per logical unit (canvas_items stretch). 1.0 at the 1600x900 base size.
## Headless runs (probes, bots) have a 64x64 dummy window: treat them as the base size.
func _stretch_factor() -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var win: Vector2 = Vector2(get_tree().root.size) if get_tree() != null else vs
	if vs.x <= 0.0 or win.x <= 0.0:
		return 1.0
	return maxf(minf(win.x / vs.x, win.y / vs.y), 0.01)


func _window_target_pos() -> Vector2:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	return ((vs - _window.size) * 0.5).round()


# --- UI construction ----------------------------------------------------------------------------

func _style(bg: Color, border: Color, bw: int, radius: int, pad: Vector4 = Vector4(10, 6, 10, 6)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	return sb


## Chrome panel in the current art style: A = _style() (StyleBoxFlat, unchanged); B..F = pixel
## panel (old border kept as an inner band inside an ink outline; D/E/F rim / halo / shadow).
func _chrome(bg: Color, border: Color, bw: int, radius: int, pad: Vector4 = Vector4(10, 6, 10, 6)) -> StyleBox:
	if PixelDraw.legacy():
		return _style(bg, border, bw, radius, pad)
	return KitchenChrome.box(bg, border, bw, radius, pad)


func _window_box() -> StyleBox:
	var wsb: StyleBox = _chrome(C_CREAM, C_OAK, 3, 12, Vector4(WIN_MARGIN_X, WIN_MARGIN_Y, WIN_MARGIN_X, WIN_MARGIN_Y))
	if wsb is StyleBoxFlat:
		(wsb as StyleBoxFlat).shadow_color = Color(0.09, 0.05, 0.03, 0.3)
		(wsb as StyleBoxFlat).shadow_size = 10
		(wsb as StyleBoxFlat).shadow_offset = Vector2(0, 4)
	return wsb


func _overlay_box() -> StyleBox:
	var psb: StyleBox = _chrome(C_CREAM, C_OAK, 3, 12, Vector4(28, 20, 28, 20))
	if psb is StyleBoxFlat:
		(psb as StyleBoxFlat).shadow_color = Color(0.09, 0.05, 0.03, 0.3)
		(psb as StyleBoxFlat).shadow_size = 8
	return psb


func _frame_box() -> StyleBoxFlat:
	var fsb := StyleBoxFlat.new()
	fsb.draw_center = false
	fsb.border_color = C_INK
	var bw: int = 3 if PixelDraw.legacy() else maxi(3, PixelDraw.chrome_px())
	fsb.set_border_width_all(bw)
	fsb.set_corner_radius_all(4 if PixelDraw.legacy() or not PixelDraw.chunky() else 0)
	fsb.expand_margin_left = bw
	fsb.expand_margin_top = bw
	fsb.expand_margin_right = bw
	fsb.expand_margin_bottom = bw
	if not PixelDraw.legacy() and bool(PixelDraw.S["drop_shadow"]):
		fsb.shadow_color = PixelDraw.DROP_COL
		fsb.shadow_size = 1
		fsb.shadow_offset = Vector2(3, 3)
	return fsb


func _label(text: String, size: int, color: Color = C_INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels.append([l, color])
	if not PixelDraw.legacy():
		KitchenChrome.style_text(l, color)
	return l


## Host pixel art drawn into `ctrl` by draw_fn(ci); E / F wrap it in an FX group (halo / shadow).
func _art(ctrl: Control, draw_fn: Callable, px_scale: float) -> void:
	_art_updaters.append([ctrl, KitchenChrome.art_canvas(ctrl, draw_fn, px_scale)])


func _button(text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", C_INK)
	b.add_theme_color_override("font_hover_color", C_INK)
	b.add_theme_color_override("font_pressed_color", C_INK)
	_style_button(b, primary)
	b.pressed.connect(cb)
	_buttons.append([b, primary])
	return b


func _style_button(b: Button, primary: bool) -> void:
	var bg: Color = C_HONEY_LIGHT if primary else C_CREAM
	b.add_theme_stylebox_override("normal", _chrome(bg, C_OAK, 3, 10, Vector4(18, 8, 18, 8)))
	b.add_theme_stylebox_override("hover", _chrome(bg.lightened(0.25), C_OAK_DARK, 3, 10, Vector4(18, 8, 18, 8)))
	b.add_theme_stylebox_override("pressed", _chrome(bg.darkened(0.08), C_OAK_DARK, 3, 10, Vector4(18, 9, 18, 7)))
	if not PixelDraw.legacy():
		KitchenChrome.style_text(b, C_INK)


## Live art-style switch (Test Kitchen "Art style", or after PixelDraw.set_style): restyles the
## window chrome, buttons, labels, chips, host art and the running game.
func apply_art_style() -> void:
	if _root == null:
		return
	_root.theme = KitchenChrome.ui_theme(THEME_PATH)
	_window.add_theme_stylebox_override("panel", _window_box())
	_frame.add_theme_stylebox_override("panel", _frame_box())
	_banner.add_theme_stylebox_override("panel", _chrome(Color(C_CREAM, 0.95), C_OAK, 3, 10, Vector4(18, 6, 18, 8)))
	_park_panel.add_theme_stylebox_override("panel", _overlay_box())
	for e in _buttons:
		if is_instance_valid(e[0]):
			_style_button(e[0], bool(e[1]))
			KitchenChrome.style_text(e[0], C_INK)
	for e2 in _labels:
		if is_instance_valid(e2[0]):
			KitchenChrome.style_text(e2[0], e2[1])
	var keep: Array = []
	for e3 in _art_updaters:
		if is_instance_valid(e3[0]):
			(e3[1] as Callable).call()
			keep.append(e3)
	_art_updaters = keep
	_style_cache.clear()
	for chip in _stations.get_children():
		chip.set_meta("style_key", "")
	if _open:
		_refresh_hud()
	if _game != null and is_instance_valid(_game) and _game.has_method("apply_art_style"):
		_game.call("apply_art_style")
	if _result_card.visible and not _result.is_empty():
		_show_result(_result)
	_redraw_ui(_root)
	_layout()


func _redraw_ui(n: Node) -> void:
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()
	for c in n.get_children():
		_redraw_ui(c)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(THEME_PATH):
		_root.theme = KitchenChrome.ui_theme(THEME_PATH)
	add_child(_root)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = C_DIM
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_window = PanelContainer.new()
	_window.name = "Window"
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _window_box())
	_root.add_child(_window)
	# Content (e.g. a long station strip) can grow the window after _layout: keep it centred.
	_window.resized.connect(func() -> void:
		if _anim == null or not _anim.is_running():
			_window.position = _window_target_pos())

	var bunting := Control.new()
	bunting.name = "Bunting"
	bunting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bunting.custom_minimum_size = Vector2(0, 12)
	bunting.draw.connect(_draw_bunting.bind(bunting))
	_window.add_child(bunting)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", VSEP)
	_window.add_child(vbox)

	# Header -------------------------------------------------------------
	var header := HBoxContainer.new()
	header.name = "Header"
	header.custom_minimum_size = Vector2(0, HEADER_H)
	header.add_theme_constant_override("separation", 18)
	vbox.add_child(header)
	_header_icon = Control.new()
	_header_icon.name = "DishBadge"
	_header_icon.custom_minimum_size = Vector2(64, 56)
	_header_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art(_header_icon, _draw_header_icon, 1.0)
	header.add_child(_header_icon)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	_title = _label("Kitchen", 28)
	title_box.add_child(_title)
	_subtitle = _label("", 17, C_OAK_DARK)
	title_box.add_child(_subtitle)

	_mood = Control.new()
	_mood.name = "PatronMood"
	_mood.custom_minimum_size = Vector2(54, 48)
	_mood.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mood.tooltip_text = "Patron mood: happy, waiting, then sleepy once you pass par"
	_art(_mood, _draw_mood, 3.0)
	header.add_child(_mood)

	_clock_box = VBoxContainer.new()
	_clock_box.name = "ParClock"
	_clock_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_clock_box.add_theme_constant_override("separation", 4)
	header.add_child(_clock_box)
	_clock_label = _label("par 0:00", 18)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_box.add_child(_clock_label)
	_clock_bar = Control.new()
	_clock_bar.custom_minimum_size = Vector2(170, 14)
	_clock_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_bar.draw.connect(_draw_clock_bar)
	_clock_box.add_child(_clock_bar)

	_streak = _label("", 18, C_HONEY.darkened(0.35))
	_streak.custom_minimum_size = Vector2(120, 0)
	_streak.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_streak)

	_burner_box = HBoxContainer.new()
	_burner_box.name = "BurnerSlot"
	_burner_box.add_theme_constant_override("separation", 6)
	header.add_child(_burner_box)
	_burner_label = _label("burner", 16, C_OAK_DARK)
	_burner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_burner_box.add_child(_burner_label)
	_burner_ctrl = Control.new()
	_burner_ctrl.custom_minimum_size = Vector2(44, 44)
	_burner_ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_burner_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art(_burner_ctrl, _draw_burner, 3.0)
	_burner_box.add_child(_burner_ctrl)

	_close_btn = _button("x", request_park)
	_close_btn.name = "CloseButton"
	_close_btn.tooltip_text = "Park this order (Esc)"
	_close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close_btn.custom_minimum_size = Vector2(44, 44)
	header.add_child(_close_btn)

	# Play area ------------------------------------------------------------
	var center := CenterContainer.new()
	center.name = "PlayArea"
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(center)
	_play_stack = Control.new()
	_play_stack.name = "PlayStack"
	_play_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_stack.custom_minimum_size = Vector2(PLAY_W * 3, PLAY_H * 3)
	center.add_child(_play_stack)
	_svc = SubViewportContainer.new()
	_svc.name = "PlayView"
	_svc.stretch = true
	_svc.stretch_shrink = 1
	_svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_svc.mouse_filter = Control.MOUSE_FILTER_STOP
	_svc.position = Vector2.ZERO
	_svc.size = Vector2(PLAY_W, PLAY_H)
	_svc.scale = Vector2(3, 3)
	_play_stack.add_child(_svc)
	_sv = SubViewport.new()
	_sv.name = "PlayViewport"
	_sv.size = Vector2i(PLAY_W, PLAY_H)
	_sv.transparent_bg = false
	_sv.handle_input_locally = true
	_sv.snap_2d_transforms_to_pixel = true
	_sv.snap_2d_vertices_to_pixel = true
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_svc.add_child(_sv)
	var frame := Panel.new()
	frame.name = "PlayFrame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _frame_box())
	_play_stack.add_child(frame)
	_frame = frame

	_banner = PanelContainer.new()
	_banner.name = "Banner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.add_theme_stylebox_override("panel", _chrome(Color(C_CREAM, 0.95), C_OAK, 3, 10, Vector4(18, 6, 18, 8)))
	_play_stack.add_child(_banner)
	var bvb := VBoxContainer.new()
	bvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bvb.add_theme_constant_override("separation", 0)
	_banner.add_child(bvb)
	_banner_title = _label("", 24)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bvb.add_child(_banner_title)
	_banner_text = _label("", 17, C_OAK_DARK)
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bvb.add_child(_banner_text)

	# Footer ----------------------------------------------------------------
	var footer := VBoxContainer.new()
	footer.name = "Footer"
	footer.custom_minimum_size = Vector2(0, FOOTER_H)
	footer.add_theme_constant_override("separation", 4)
	vbox.add_child(footer)
	_stations = HBoxContainer.new()
	_stations.name = "StationStrip"
	_stations.add_theme_constant_override("separation", 6)
	_stations.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_child(_stations)
	var hint_row := HBoxContainer.new()
	footer.add_child(hint_row)
	_hint = _label("", FOOTER_FONT, C_OAK_DARK)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_row.add_child(_hint)
	_esc_label = _label("F1: hint    Esc: park order", FOOTER_FONT, C_OAK_DARK)
	hint_row.add_child(_esc_label)

	_build_park_prompt()
	_build_result_card()


func _overlay_center(name_: String) -> Array:
	var full := Control.new()
	full.name = name_
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	full.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(full)
	var shade := ColorRect.new()
	shade.color = Color(C_DIM, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full.add_child(shade)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full.add_child(cc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _overlay_box())
	cc.add_child(panel)
	return [full, panel]


func _build_park_prompt() -> void:
	var parts: Array = _overlay_center("ParkPrompt")
	_park_prompt = parts[0]
	var panel: PanelContainer = parts[1]
	_park_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var q := _label("Park this order?", 26)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(q)
	_park_sub = _label("It'll wait on the counter. Same order when you come back.", 18, C_OAK_DARK)
	_park_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_park_sub)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	var keep := _button("Keep cooking", cancel_park, true)
	keep.name = "KeepButton"
	hb.add_child(keep)
	var park := _button("Park", confirm_park)
	park.name = "ParkButton"
	hb.add_child(park)
	_park_prompt.visible = false


func _build_result_card() -> void:
	var parts: Array = _overlay_center("ResultCard")
	_result_card = parts[0]
	_result_panel = parts[1]
	_result_panel.custom_minimum_size = Vector2(560, 0)
	_result_body = VBoxContainer.new()
	_result_body.add_theme_constant_override("separation", 12)
	_result_panel.add_child(_result_body)
	_confetti = Control.new()
	_confetti.name = "Confetti"
	_confetti.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confetti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confetti.draw.connect(_draw_confetti)
	_result_card.add_child(_confetti)
	_result_card.visible = false


# --- HUD refresh ---------------------------------------------------------------------------------

func _refresh_hud() -> void:
	if _game == null or not is_instance_valid(_game) or not _game.has_method("get_hud_info"):
		return
	var info: Variant = _game.call("get_hud_info")
	if not (info is Dictionary):
		return
	_hud = info
	_title.text = String(_hud.get("title", ""))
	_subtitle.text = String(_hud.get("subtitle", ""))
	_subtitle.visible = _subtitle.text != ""
	var show_clock: bool = bool(_hud.get("show_clock", _hud.has("par_sec")))
	_clock_box.visible = show_clock and _hud.has("par_sec")
	if _clock_box.visible:
		_clock_label.text = "%s / par %s" % [_fmt(float(_hud.get("elapsed_sec", 0.0))), _fmt(float(_hud.get("par_sec", 0.0)), true)]
		_clock_bar.queue_redraw()
	_mood.visible = _clock_box.visible
	if _mood.visible:
		_mood.queue_redraw()
	var hs: int = int(_hud.get("hot_streak", 0))
	_streak.text = ("Hot streak x%d ~" % hs) if hs > 0 else ""
	var burner: Dictionary = _hud.get("burner", {}) if _hud.get("burner", {}) is Dictionary else {}
	_burner_box.visible = bool(burner.get("visible", false))
	if _burner_box.visible:
		_burner_label.text = String(burner.get("label", "burner")) if String(burner.get("state", "idle")) != "idle" else "burner"
		_burner_ctrl.queue_redraw()
	_hint.text = String(_hud.get("hint", ""))
	_refresh_stations(_hud.get("stations", []) if _hud.get("stations", []) is Array else [])
	var banner: Dictionary = _hud.get("banner", {}) if _hud.get("banner", {}) is Dictionary else {}
	var bvis: bool = bool(banner.get("visible", false)) and not _result_card.visible
	_banner.visible = bvis
	if bvis:
		_banner_title.text = String(banner.get("title", ""))
		var stars: int = int(banner.get("stars", 0))
		if String(banner.get("style", "")) == "pop" and stars > 0:
			_banner_title.text = "%s  %s" % [_banner_title.text, _stars_text(stars)]
		_banner_text.text = String(banner.get("text", ""))
		_banner_text.visible = _banner_text.text != ""
		_banner.reset_size()
		_banner.position = Vector2((_play_stack.size.x - _banner.size.x) * 0.5, 10.0).round()


func _refresh_stations(list: Array) -> void:
	var want: int = list.size() + (1 if not list.is_empty() else 0)
	if _stations.get_child_count() != want:
		for c in _stations.get_children():
			c.queue_free()
			_stations.remove_child(c)
		for i in range(want):
			var chip := PanelContainer.new()
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 4)
			hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(hb)
			var ic := Control.new()
			ic.name = "Icon"
			ic.custom_minimum_size = Vector2(20, 20)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_art(ic, _draw_station_icon.bind(ic), 2.0)
			hb.add_child(ic)
			hb.add_child(_label("", FOOTER_FONT))
			_stations.add_child(chip)
	for i in range(want):
		var chip: PanelContainer = _stations.get_child(i) as PanelContainer
		var hb: HBoxContainer = chip.get_child(0) as HBoxContainer
		var ic: Control = hb.get_child(0) as Control
		var l: Label = hb.get_child(1) as Label
		var bg: Color = C_CREAM_DARK
		var border: Color = C_OAK
		var text: String = ""
		var verb: String = "serve"
		# Long recipes (Pancake Stack has 8 steps): only the active chip keeps its label.
		var compact: bool = list.size() > 4
		if i < list.size():
			var st: Dictionary = list[i]
			var state: String = String(st.get("state", "todo"))
			text = String(st.get("label", ""))
			verb = String(st.get("type", ""))
			match state:
				"done":
					bg = Color(C_SAGE, 0.45)
					text += " " + _stars_text(int(st.get("stars", 0)))
				"active":
					bg = C_HONEY_LIGHT
					border = C_INK
				"burner":
					bg = Color(C_HONEY_LIGHT, 0.6)
					text += " ~"
		else:
			text = "Serve"
			bg = C_HONEY_LIGHT if String(_hud.get("phase", "")) == "SERVE" else C_CREAM
			border = C_INK if String(_hud.get("phase", "")) == "SERVE" else C_OAK
		if compact and i < list.size():
			var stt: String = String((list[i] as Dictionary).get("state", "todo"))
			if stt == "done":
				text = _stars_text(int((list[i] as Dictionary).get("stars", 0)))
			elif stt != "active":
				text = ""
		l.text = text
		l.visible = text != ""
		if String(ic.get_meta("verb", "")) != verb:
			ic.set_meta("verb", verb)
			ic.queue_redraw()
		# Only touch the theme when the look changes (each override re-sorts the strip).
		var key: String = bg.to_html() + border.to_html() + PixelDraw.style
		if String(chip.get_meta("style_key", "")) != key:
			chip.set_meta("style_key", key)
			if not _style_cache.has(key):
				# B..F: + the ink outline width (and the icon's own outer outline, drawn at 2x past
				# its box) each side so the icon sits inside the chip border.
				var cp: float = 0.0 if PixelDraw.legacy() else float(PixelDraw.chrome_px() + 2 * PixelDraw.ow())
				var cv: float = 0.0 if PixelDraw.legacy() else float(PixelDraw.chrome_px())
				_style_cache[key] = _chrome(bg, border, 2, 8, Vector4(6 + cp, 2 + cv, 8 + cp, 2 + cv))
			chip.add_theme_stylebox_override("panel", _style_cache[key])


func _draw_station_icon(ci: CanvasItem, ic: Control) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(2, 2))
	KitchenArt.verb_icon(ci, Vector2.ZERO, String(ic.get_meta("verb", "counter")))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Header badge: the dish being cooked (great look, no animation).
func _draw_header_icon(ci: CanvasItem) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var rec: Variant = _game.get("recipe")
	if not (rec is Dictionary) or (rec as Dictionary).is_empty():
		return
	var r: Dictionary = rec
	PixelDraw.rounded_rect(ci, Rect2(0, 0, 64, 56), 6, C_CREAM_DARK, C_OAK)
	var dd: Dictionary = r.get("dish", {}) if r.get("dish", {}) is Dictionary else {}
	KitchenArt.dish(ci, Vector2(32, 52), String(r.get("id", "")), dd, {"great": true, "reduced": true, "fx": false})


## Window chrome: a little sage / honey / blush bunting strung inside the window's top margin.
func _draw_bunting(c: Control) -> void:
	var w: float = c.size.x
	var cols: Array = [C_SAGE, C_HONEY, C_BLUSH, C_HONEY_LIGHT]
	var y0: float = -float(WIN_MARGIN_Y) + 3.0
	var lw: float = 2.0 if PixelDraw.legacy() else 3.0
	c.draw_line(Vector2(0, y0), Vector2(w, y0), C_OAK, lw)
	var x: float = 10.0
	var k: int = 0
	while x + 16.0 < w - 10.0:
		var pts := PackedVector2Array([Vector2(x, y0), Vector2(x + 16, y0), Vector2(x + 8, y0 + 10)])
		c.draw_colored_polygon(pts, cols[k % cols.size()])
		c.draw_polyline(PackedVector2Array([pts[0], pts[2], pts[1]]), C_INK, lw)
		x += 24.0
		k += 1


func _stars_text(n: int) -> String:
	var s: String = ""
	for i in range(3):
		s += "★" if i < n else "☆"
	return s


## Clock text. Par rounds up (matches the ticket), elapsed rounds down.
static func _fmt(sec: float, round_up: bool = false) -> String:
	var s: int = int(ceilf(maxf(sec, 0.0) - 0.001)) if round_up else int(floorf(maxf(sec, 0.0)))
	return "%d:%02d" % [int(s / 60.0), s % 60]


func _draw_clock_bar() -> void:
	var r := Rect2(Vector2.ZERO, _clock_bar.size)
	var par: float = maxf(float(_hud.get("par_sec", 1.0)), 0.01)
	var t: float = float(_hud.get("elapsed_sec", 0.0)) / par
	var bw: float = 2.0 if PixelDraw.legacy() else 3.0
	_clock_bar.draw_rect(r, C_INK, true)
	_clock_bar.draw_rect(r.grow(-bw), C_CREAM_DARK, true)
	var col: Color = C_SAGE if t < 0.8 else (C_HONEY if t <= 1.0 else C_OAK_DARK)
	var inner: Rect2 = r.grow(-bw)
	_clock_bar.draw_rect(Rect2(inner.position, Vector2(inner.size.x * clampf(t, 0.0, 1.0), inner.size.y)), col, true)
	# little pastry notch at par
	_clock_bar.draw_rect(Rect2(inner.end.x - bw, inner.position.y - bw, bw, inner.size.y + bw * 2.0), C_INK, true)


## Patron mood bubble next to the par clock (no patron sprite yet: cat art is owner-directed).
## happy (heart) below 80% of par, waiting ("...", wiggling) to par, sleepy ("Zz") after.
func _draw_mood(ci: CanvasItem) -> void:
	var par: float = maxf(float(_hud.get("par_sec", 1.0)), 0.01)
	var t: float = float(_hud.get("elapsed_sec", 0.0)) / par
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var rm: bool = _is_reduced_motion()
	ci.draw_set_transform(Vector2(0, 0), 0.0, Vector2(3, 3))
	var bg: Color = C_CREAM if t < 0.8 else (C_HONEY_LIGHT if t <= 1.0 else C_CREAM_DARK)
	PixelDraw.rounded_rect(ci, Rect2(1, 1, 16, 12), 3, bg, C_INK)
	ci.draw_rect(Rect2(4, 13, 3, 1), C_INK, true)
	ci.draw_rect(Rect2(4, 12, 2, 1), bg, true)
	ci.draw_rect(Rect2(4, 14, 1, 1), C_INK, true)
	if t < 0.8:
		for row in [[6, 4, 2], [10, 4, 2], [5, 5, 8], [5, 6, 8], [6, 7, 6], [7, 8, 4], [8, 9, 2]]:
			ci.draw_rect(Rect2(row[0], row[1], row[2], 1), C_BLUSH.darkened(0.15), true)
	elif t <= 1.0:
		var wig: int = 0 if rm else int(fmod(now * 3.0, 3.0))
		for i in range(3):
			ci.draw_rect(Rect2(4 + i * 4, 7 - (1 if i == wig else 0), 2, 2), C_INK, true)
	else:
		PixelDraw.text(ci, Vector2(4, 11), "Zz", C_OAK_DARK, 8)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## S grade: a short honey + sage confetti burst from the top of the card.
func _draw_confetti() -> void:
	if _confetti_t < 0.0 or not _result_panel.visible:
		return
	var k: float = clampf(_confetti_t / CONFETTI_SEC, 0.0, 1.0)
	var origin: Vector2 = _result_panel.get_global_rect().position - _confetti.get_global_rect().position + Vector2(_result_panel.size.x * 0.5, 70)
	var cols: Array = [C_HONEY, C_SAGE, C_HONEY_LIGHT, C_BLUSH]
	for i in range(12):
		var ang: float = -PI * 0.5 + (float(i) - 5.5) * 0.24
		var spd: float = 260.0 + float((i * 37) % 90)
		var p: Vector2 = origin + Vector2(cos(ang), sin(ang)) * spd * k + Vector2(0, 520.0 * k * k)
		var sz: float = 9.0 if i % 2 == 0 else 6.0
		var c: Color = cols[i % cols.size()]
		c.a = 1.0 - k * k
		_confetti.draw_rect(Rect2(p.round(), Vector2(sz, sz)), c, true)
		_confetti.draw_rect(Rect2(p.round(), Vector2(sz, sz)), Color(C_INK, c.a), false, 2.0)


func _draw_burner(ci: CanvasItem) -> void:
	var b: Dictionary = _hud.get("burner", {}) if _hud.get("burner", {}) is Dictionary else {}
	var c: Vector2 = _burner_ctrl.size * 0.5
	var state: String = String(b.get("state", "idle"))
	var prog: float = clampf(float(b.get("progress", 0.0)), 0.0, 1.0)
	ci.draw_circle(c, 20 if PixelDraw.legacy() else 18 + PixelDraw.chrome_px(), C_INK)
	ci.draw_circle(c, 18, C_CREAM)
	if state == "idle":
		ci.draw_arc(c, 13, 0, TAU, 32, C_CREAM_DARK, 5, false)
		return
	var col: Color = C_HONEY
	match state:
		"ready", "done":
			col = C_SAGE
		"good":
			col = C_HONEY
		"late":
			col = C_OAK_DARK
	ci.draw_arc(c, 13, 0, TAU, 32, C_CREAM_DARK, 5, false)
	ci.draw_arc(c, 13, -PI * 0.5, -PI * 0.5 + TAU * prog, 32, col, 5, false)
	if state == "ready":
		ci.draw_circle(c, 6, C_SAGE)


# --- Result card ---------------------------------------------------------------------------------

func _show_result(r: Dictionary) -> void:
	for c in _result_body.get_children():
		_result_body.remove_child(c)
		c.queue_free()
	var grade: String = String(r.get("grade", "B"))
	var gs: Dictionary = GRADE_STYLE.get(grade, GRADE_STYLE["B"])

	# Card colour per grade: S glows honey, C is a softer, sleepier cream.
	var panel_bg: Color = C_CREAM
	if grade == "S":
		panel_bg = C_CREAM.lerp(C_HONEY_LIGHT, 0.45)
	elif grade == "C":
		panel_bg = C_CREAM.lerp(C_CREAM_DARK, 0.7)
	var psb: StyleBox = _chrome(panel_bg, C_HONEY if grade == "S" else C_OAK, 4 if grade == "S" else 3, 12, Vector4(28, 20, 28, 20))
	if psb is StyleBoxFlat:
		(psb as StyleBoxFlat).shadow_color = Color(0.09, 0.05, 0.03, 0.3)
		(psb as StyleBoxFlat).shadow_size = 8
	_result_panel.add_theme_stylebox_override("panel", psb)
	var rm: bool = _is_reduced_motion()

	var stamp := PanelContainer.new()
	stamp.name = "Stamp"
	stamp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stamp.add_theme_stylebox_override("panel", _chrome(Color(String(gs["bg"])), C_INK, 3, 14, Vector4(22, 8, 22, 10)))
	_result_body.add_child(stamp)
	var shb := HBoxContainer.new()
	shb.add_theme_constant_override("separation", 14)
	stamp.add_child(shb)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(60, 60)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art(icon, _draw_stamp_icon.bind(grade), 3.0)
	shb.add_child(icon)
	# Big tilted grade letter that slams in (a plain Control holder keeps its rotation / scale,
	# containers would reset them).
	var holder := Control.new()
	holder.name = "GradeLetter"
	holder.custom_minimum_size = Vector2(76, 92)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shb.add_child(holder)
	var letter := _label(grade, 84)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_color_override("font_outline_color", C_CREAM)
	letter.add_theme_constant_override("outline_size", 8)
	letter.position = Vector2.ZERO
	letter.size = holder.custom_minimum_size
	letter.pivot_offset = holder.custom_minimum_size * 0.5
	letter.rotation = deg_to_rad(-6.0)
	holder.add_child(letter)
	if not rm:
		letter.scale = Vector2(1.4, 1.4)
		var ltw: Tween = create_tween()
		ltw.tween_interval(0.12)
		ltw.tween_property(letter, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var gt := VBoxContainer.new()
	gt.alignment = BoxContainer.ALIGNMENT_CENTER
	gt.add_theme_constant_override("separation", 0)
	shb.add_child(gt)
	gt.add_child(_label(String(r.get("grade_text", gs["text"])), 32))
	if String(gs["sub"]) != "":
		gt.add_child(_label(String(gs["sub"]), 18, C_OAK_DARK))

	var name_l := _label(String(r.get("display_name", "")), 22, C_OAK_DARK)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_body.add_child(name_l)

	var dish_row := HBoxContainer.new()
	dish_row.name = "DishRow"
	dish_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dish_row.add_theme_constant_override("separation", 28)
	_result_body.add_child(dish_row)
	var dish_ci := Control.new()
	dish_ci.name = "Dish"
	var dish_h: int = int(DISH_H.get(String(r.get("recipe_id", "")), 40))
	dish_ci.custom_minimum_size = Vector2(72 * DISH_SCALE, (dish_h + 8) * DISH_SCALE)
	dish_ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art(dish_ci, _draw_result_dish.bind(r), float(DISH_SCALE))
	dish_row.add_child(dish_ci)
	if not (_result_info(r, 1.0)["art"] as Array).is_empty():
		var art_box := VBoxContainer.new()
		art_box.alignment = BoxContainer.ALIGNMENT_CENTER
		art_box.add_theme_constant_override("separation", 2)
		dish_row.add_child(art_box)
		var art_ci := Control.new()
		art_ci.name = "LatteArt"
		art_ci.custom_minimum_size = Vector2(144, 144)
		art_ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art(art_ci, _draw_result_art.bind(r), 3.0)
		art_box.add_child(art_ci)
		var al := _label("your art", 16, C_OAK_DARK)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_box.add_child(al)
	if not rm:
		var tick := Timer.new()
		tick.wait_time = 0.1
		tick.autostart = true
		tick.timeout.connect(dish_ci.queue_redraw)
		dish_ci.add_child(tick)

	var steps: Array = r.get("steps", []) if r.get("steps", []) is Array else []
	if not steps.is_empty():
		var flow := HFlowContainer.new()
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.add_theme_constant_override("h_separation", 18)
		_result_body.add_child(flow)
		var si: int = 0
		for s in steps:
			var d: Dictionary = s
			var sl: Label = _label("%s %s" % [String(d.get("label", d.get("type", ""))), _stars_text(int(d.get("stars", 1)))], 18)
			flow.add_child(sl)
			if not rm:
				# Stars land one at a time after the stamp.
				sl.modulate = Color(1.6, 1.4, 0.8, 0.0)
				var stw: Tween = create_tween()
				stw.tween_interval(0.35 + 0.15 * float(si))
				stw.tween_property(sl, "modulate", Color.WHITE, 0.14)
			si += 1

	var info_row := HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_row.add_theme_constant_override("separation", 28)
	_result_body.add_child(info_row)
	if r.has("time_sec"):
		if bool(r.get("no_clock", false)):
			info_row.add_child(_label("No-clock kitchen", 18))
		else:
			info_row.add_child(_label("Time %s / par %s" % [_fmt(float(r["time_sec"])), _fmt(float(r.get("par_sec", 0.0)), true)], 18))
	if int(r.get("hot_streak", 0)) > 0:
		info_row.add_child(_label("Hot streak x%d  (+%.2f)" % [int(r["hot_streak"]), float(r.get("hot_streak_bonus", 0.0))], 18, C_HONEY.darkened(0.35)))

	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 12)
	_result_body.add_child(chips)
	if r.has("money"):
		chips.add_child(_chip("+$%d" % int(r["money"]), C_HONEY_LIGHT))
	if r.has("rep") and float(r["rep"]) > 0.0:
		var rep: float = float(r["rep"])
		var rep_txt: String = ("+%d rep" % int(rep)) if is_equal_approx(rep, roundf(rep)) else ("+%.1f rep" % rep)
		chips.add_child(_chip(rep_txt, Color(C_SAGE, 0.55)))
	if String(r.get("modifier_label", "")) != "":
		chips.add_child(_chip(String(r["modifier_label"]), C_CREAM_DARK))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	_result_body.add_child(buttons)
	if _has_next_order():
		var nb := _button("Next order >", _on_result_button.bind(true), true)
		nb.name = "NextButton"
		buttons.add_child(nb)
	var bb := _button("Back to cafe", _on_result_button.bind(false), not _has_next_order())
	bb.name = "BackButton"
	buttons.add_child(bb)

	_banner.visible = false
	_result_card.visible = true
	_result_age = 0.0
	_confetti_t = 0.0 if grade == "S" and not rm else -1.0
	_result_panel.reset_size()
	if not rm:
		stamp.pivot_offset = Vector2(0, 0)
		stamp.scale = Vector2(1.35, 1.35)
		stamp.modulate.a = 0.0
		var tw: Tween = create_tween().set_parallel(true)
		tw.tween_property(stamp, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(stamp, "modulate:a", 1.0, 0.15)
		stamp.resized.connect(func() -> void: stamp.pivot_offset = stamp.size * 0.5, CONNECT_ONE_SHOT)


func _chip(text: String, bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _chrome(bg, C_OAK, 2, 16, Vector4(14, 4, 14, 4)))
	p.add_child(_label(text, 20))
	return p


func _draw_stamp_icon(ci: CanvasItem, grade: String) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(3, 3))
	KitchenArt.grade_stamp(ci, Vector2(10, 10), grade)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _result_info(r: Dictionary, precision: float) -> Dictionary:
	var steps: Array = r.get("steps", []) if r.get("steps", []) is Array else []
	return KitchenArt.dish_info(steps, precision)


func _draw_result_dish(ci: CanvasItem, r: Dictionary) -> void:
	var info: Dictionary = _result_info(r, float(r.get("precision", 1.0)))
	info["t"] = float(Time.get_ticks_msec()) / 1000.0
	info["reduced"] = _is_reduced_motion()
	var dd: Dictionary = r.get("dish", {}) if r.get("dish", {}) is Dictionary else {}
	# Drawn at DISH_SCALE, sized to the sprite (no empty band above short dishes); the quality
	# sparkles are placed around the sprite here instead of KitchenArt's fixed offsets.
	info["fx"] = false
	var rid: String = String(r.get("recipe_id", ""))
	var h: float = float(DISH_H.get(rid, 40))
	var bottom := Vector2(36, h + 6)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(DISH_SCALE, DISH_SCALE))
	KitchenArt.dish(ci, bottom, rid, dd, info)
	if bool(info.get("great", true)):
		var tw: float = 0.0 if bool(info["reduced"]) else roundf(sin(float(info["t"]) * 6.0))
		PixelDraw.sparkle(ci, bottom + Vector2(-30, -h * 0.75 - tw), 2, C_HONEY)
		PixelDraw.sparkle(ci, bottom + Vector2(29, -h * 0.55 + tw), 1, C_HONEY)
		PixelDraw.sparkle(ci, bottom + Vector2(25, -h - 2 - tw), 1, C_HONEY_LIGHT)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_result_art(ci: CanvasItem, r: Dictionary) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(3, 3))
	KitchenArt.latte_art(ci, Vector2(24, 23), 16, _result_info(r, 1.0))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
