extends CanvasLayer

## Purr-fect Timing overlay: a cream window over the paused cafe with the 320x180 play area.
## Self-contained on purpose (does not use the in-progress cooking MinigameHost); see
## Docs/minigames/PURRFECT_TIMING.md for how it maps onto the shared host later.
##
## Responsibilities: pause/unpause the cafe, dim it, own the order clock + judge + synth,
## capture input (mouse-first, keyboard optional) with clock timestamps, Esc pause / park,
## and apply rewards exactly once when the dish is served.

signal order_closed(result: Dictionary)
signal order_parked
signal order_opened(recipe_index: int)

const GameScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTGame.gd")
const ClockScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTClock.gd")
const JudgeScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTJudge.gd")
const SynthScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTSynth.gd")
const RecipesScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTRecipes.gd")
const PX := preload("res://Scripts/minigame_demos/purrfect_timing/PTPixel.gd")

const PLAY_W := 320
const PLAY_H := 180
const HEADER_H := 76
const FOOTER_H := 50
const SIDE_PAD := 20
const SERVE_GUARD_SEC := 0.6
const COL_CREAM := Color("#FFF6EA")
const COL_OAK := Color("#C9A27A")
const COL_OAK_DARK := Color("#A87C55")
const COL_INK := Color("#4A3426")
const COL_SAGE := Color("#8FBF9F")
const COL_HONEY := Color("#E8B04B")

## The cafe level (MainLevel3D). Rewards go through add_money / HUD show_notice if present.
var level: Node = null
var settings: Dictionary = {"leniency_idx": 0, "audio": true, "hold_toggle": false, "offset_ms": 0.0, "reduced_motion": false}
## Probe / capture tools: drive the order clock by hand (clock.manual_t).
var force_manual_clock: bool = false

var game: Node2D
var clock: RefCounted
var judge: RefCounted
var synth: Node
var recipe_index: int = -1
var recipe: Dictionary = {}
var is_open: bool = false
var is_parked: bool = false
var paused_menu: bool = false
var current_result: Dictionary = {}
var rewards_applied: bool = false
var rewards_applied_count: int = 0
var last_reward: int = 0

var _prev_tree_paused: bool = false
var _prev_accum: bool = true
var _holding_mouse: bool = false
var _result_t: float = 0.0
var _k: int = 3

var _root: Control
var _dim: ColorRect
var _window: Panel
var _title: Label
var _sub: Label
var _btn_sound: Button
var _btn_pause: Button
var _container: SubViewportContainer
var _subvp: SubViewport
var _footer: Label
var _btn_serve: Button
var _pause_card: PanelContainer
var _btn_resume: Button
var _btn_park: Button
var _labels: Array[Label] = []
var _buttons: Array[Button] = []
## B..F chrome: ink outline (+ cream halo in E) panels drawn behind the window / pause card.
var _backers: Array = []   # {target: Control, panels: Array[Panel], grow: Array[float]}


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	synth = SynthScript.new()
	synth.name = "PTSynth"
	add_child(synth)
	game.set("synth", synth)
	game.connect("finished", _on_finished)
	game.connect("step_changed", _on_step_changed)
	_root.visible = false
	# build the decorative cats once at boot (their facing settles off-screen)
	game.call("setup_cats", _cafe_genomes())
	get_viewport().size_changed.connect(_layout)
	if not PX.legacy():
		apply_art_style()
	_layout()


# ============================================================== public API

func open_recipe(idx: int) -> void:
	if is_open:
		return
	var all: Array = RecipesScript.all()
	recipe_index = clampi(idx, 0, all.size() - 1)
	recipe = all[recipe_index]
	is_parked = false
	clock = ClockScript.new(force_manual_clock)
	judge = JudgeScript.new()
	var li: int = clampi(int(settings.get("leniency_idx", 0)), 0, 2)
	judge.set("leniency", JudgeScript.LENIENCY_VALUES[li])
	judge.set("offset_ms", float(settings.get("offset_ms", 0.0)))
	game.set("reduced_motion", bool(settings.get("reduced_motion", false)))
	game.call("setup_cats", _cafe_genomes())
	current_result = {}
	rewards_applied = false
	paused_menu = false
	_pause_card.visible = false
	_btn_serve.visible = false
	_show()
	synth.set("enabled", bool(settings.get("audio", true)))
	synth.call("start", clock)
	game.call("start_order", recipe, clock, judge, bool(settings.get("hold_toggle", false)))
	_title.text = str(recipe.get("name", ""))
	_sub.text = "Tier %d  -  %s" % [int(recipe.get("tier", 1)), str(recipe.get("blurb", ""))]
	_update_footer()
	order_opened.emit(recipe_index)


## Esc / pause button: open or close the pause card. Clock and beat freeze, cafe stays paused.
func toggle_pause() -> void:
	if not is_open or not current_result.is_empty():
		return
	paused_menu = not paused_menu
	if paused_menu:
		clock.call("pause")
		game.call("suspend_holds")
		synth.call("set_frozen", true)
	else:
		clock.call("resume")
		synth.call("set_frozen", false)
		if str(game.get("step_type")) == "beat":
			game.call("restart_current_step")  # fresh count-in after a pause
	_holding_mouse = false
	_pause_card.visible = paused_menu
	_update_footer()


## Leave the order for later with no loss: cafe unpauses, the order clock stays frozen.
func park() -> void:
	if not is_open or not current_result.is_empty():
		return
	clock.call("pause")
	game.call("suspend_holds")
	synth.call("stop")
	paused_menu = false
	_pause_card.visible = false
	is_parked = true
	_hide_overlay()
	order_parked.emit()


func resume_parked() -> void:
	if not is_parked or is_open:
		return
	is_parked = false
	paused_menu = false
	_pause_card.visible = false
	_show()
	clock.call("resume")
	synth.set("enabled", bool(settings.get("audio", true)))
	synth.call("start", clock)
	synth.set("beat_t0", game.get("t_order0"))
	synth.set("beat_period", game.get("beat_period"))
	synth.set("metronome_on", true)
	game.call("restart_current_step")
	_update_footer()
	order_opened.emit(recipe_index)


## Close the result card: unpause first, then pay exactly once.
func serve() -> void:
	if not is_open or current_result.is_empty():
		return
	var res: Dictionary = current_result
	synth.call("stop")
	game.call("stop")
	_hide_overlay()
	_apply_rewards(res)
	current_result = {}
	order_closed.emit(res)


func set_audio(on: bool) -> void:
	settings["audio"] = on
	if synth != null:
		synth.set("enabled", on)
	_update_sound_button()


func play_area_rect() -> Rect2:
	return _container.get_global_rect()


# ============================================================== internals

func _show() -> void:
	_prev_tree_paused = get_tree().paused
	get_tree().paused = true
	_prev_accum = Input.use_accumulated_input
	Input.use_accumulated_input = false
	_root.visible = true
	is_open = true
	_holding_mouse = false
	_layout()
	_update_sound_button()


func _hide_overlay() -> void:
	_root.visible = false
	is_open = false
	_holding_mouse = false
	get_tree().paused = _prev_tree_paused
	Input.use_accumulated_input = _prev_accum


func _apply_rewards(res: Dictionary) -> void:
	if rewards_applied:
		return
	rewards_applied = true
	rewards_applied_count += 1
	var m: int = int(res.get("money", 0))
	last_reward = m
	if level == null or not is_instance_valid(level):
		return
	if level.has_method("add_money"):
		level.call("add_money", m, "order")
	var hud: Node = level.get_node_or_null("HUD3D")
	if hud != null and hud.has_method("show_notice"):
		var g: String = str(res.get("grade", "C"))
		var tail: String = "Still tasty!" if g == "C" else str(res.get("title", "")).capitalize()
		hud.call("show_notice", "%s served - grade %s, %s  +$%d" % [str(res.get("name", "Order")), g, tail, m], 3.0)


func _on_finished(res: Dictionary) -> void:
	current_result = res
	_result_t = clock.call("now")
	_btn_serve.visible = true
	_update_footer()


func _on_step_changed(_i: int) -> void:
	_update_footer()


func _cafe_genomes() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	var defs: Array = []
	for c in get_tree().get_nodes_in_group("cats"):
		var d: Variant = c.get("cat_def")
		if d is Dictionary and not (d as Dictionary).is_empty():
			defs.append(d)
	defs.shuffle()
	for d in defs:
		if out.size() >= 2:
			break
		out.append(d)
	return out


func _update_footer() -> void:
	if _footer == null:
		return
	if not current_result.is_empty():
		_footer.text = "Click, Space or Enter to serve"
		return
	if paused_menu:
		_footer.text = "Paused.  Esc / Space: keep cooking"
		return
	var t: String = "Mouse: click / hold the play area     Keys: Space (Z/X)   Oven: click ring or O     Esc: pause     M: sound"
	_footer.text = t


func _update_sound_button() -> void:
	if _btn_sound != null:
		_btn_sound.text = "Sound: on" if bool(settings.get("audio", true)) else "Sound: off"


func _on_escape() -> void:
	if not current_result.is_empty():
		if clock.call("now") - _result_t >= SERVE_GUARD_SEC:
			serve()
		return
	toggle_pause()


func _input(event: InputEvent) -> void:
	if not is_open or clock == null:
		return
	var t: float = clock.call("now")
	if event is InputEventKey:
		var k := event as InputEventKey
		var code: Key = k.keycode
		if code >= KEY_F1 and code <= KEY_F12:
			return  # let the launcher / debug keys through
		get_viewport().set_input_as_handled()
		if k.echo:
			return
		match code:
			KEY_ESCAPE:
				if k.pressed:
					_on_escape()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_Z, KEY_X, KEY_J, KEY_K:
				if paused_menu:
					if k.pressed and code != KEY_Z and code != KEY_X:
						toggle_pause()
					return
				if not current_result.is_empty():
					if k.pressed and t - _result_t >= SERVE_GUARD_SEC:
						serve()
					return
				if k.pressed:
					game.call("input_press", t)
				else:
					game.call("input_release", t)
			KEY_O, KEY_TAB:
				if k.pressed and not paused_menu:
					game.call("input_oven", t)
			KEY_M:
				if k.pressed:
					set_audio(not bool(settings.get("audio", true)))
			KEY_P:
				if k.pressed:
					toggle_pause()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if paused_menu:
				return
			var r: Rect2 = _container.get_global_rect()
			if not r.has_point(mb.position):
				return
			get_viewport().set_input_as_handled()
			if not current_result.is_empty():
				if t - _result_t >= SERVE_GUARD_SEC:
					serve()
				return
			var p: Vector2 = (mb.position - r.position) / (r.size / Vector2(PLAY_W, PLAY_H))
			if bool(game.call("is_oven_hit", p)):
				game.call("input_oven", t)
			else:
				_holding_mouse = true
				game.call("input_press", t)
		elif _holding_mouse:
			_holding_mouse = false
			game.call("input_release", t)


# ============================================================== UI construction

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "PTRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.12, 0.08, 0.06, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_window = Panel.new()
	_window.name = "Window"
	_window.add_theme_stylebox_override("panel", window_box())
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_window)

	_title = _label(30, COL_INK)
	_title.name = "Title"
	_window.add_child(_title)
	_sub = _label(16, COL_OAK_DARK)
	_sub.name = "Sub"
	_window.add_child(_sub)

	_btn_sound = _button("Sound: on")
	_btn_sound.pressed.connect(func() -> void: set_audio(not bool(settings.get("audio", true))))
	_window.add_child(_btn_sound)
	_btn_pause = _button("Pause  (Esc)")
	_btn_pause.pressed.connect(toggle_pause)
	_window.add_child(_btn_pause)

	var frame := Panel.new()
	frame.name = "PlayFrame"
	frame.add_theme_stylebox_override("panel", frame_box())
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(frame)

	_container = SubViewportContainer.new()
	_container.name = "PlayArea"
	_container.stretch = true
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_container)
	_subvp = SubViewport.new()
	_subvp.name = "PlayViewport"
	_subvp.size = Vector2i(PLAY_W, PLAY_H)
	_subvp.disable_3d = true
	_subvp.msaa_2d = Viewport.MSAA_DISABLED
	_subvp.snap_2d_transforms_to_pixel = true
	_subvp.snap_2d_vertices_to_pixel = true
	_subvp.gui_disable_input = true
	_subvp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_subvp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_container.add_child(_subvp)
	game = GameScript.new()
	game.name = "PTGame"
	_subvp.add_child(game)

	_footer = _label(16, COL_OAK_DARK)
	_footer.name = "Footer"
	_window.add_child(_footer)
	_btn_serve = _button("Serve!  (Enter)", true)
	_btn_serve.pressed.connect(serve)
	_btn_serve.visible = false
	_window.add_child(_btn_serve)

	_pause_card = PanelContainer.new()
	_pause_card.name = "PauseCard"
	_pause_card.add_theme_stylebox_override("panel", pause_box())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_pause_card.add_child(vb)
	var pl := _label(30, COL_INK)
	pl.text = "Paused - the cats will wait"
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(pl)
	var pl2 := _label(17, COL_OAK_DARK)
	pl2.text = "Nothing is lost. Park the order to wander the cafe\nand pick it up again from the Purr-fect Timing panel."
	pl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(pl2)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	_btn_resume = _button("Keep cooking", true)
	_btn_resume.pressed.connect(toggle_pause)
	hb.add_child(_btn_resume)
	_btn_park = _button("Park order (no loss)")
	_btn_park.pressed.connect(park)
	hb.add_child(_btn_park)
	_pause_card.visible = false
	_window.add_child(_pause_card)


func _layout() -> void:
	if _window == null:
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var kx: float = (vs.x * 0.80 - SIDE_PAD * 2.0) / float(PLAY_W)
	var ky: float = (vs.y * 0.80 - HEADER_H - FOOTER_H) / float(PLAY_H)
	_k = maxi(1, floori(minf(kx, ky)))
	var pw: float = float(PLAY_W * _k)
	var ph: float = float(PLAY_H * _k)
	var ww: float = pw + SIDE_PAD * 2.0
	var wh: float = ph + HEADER_H + FOOTER_H
	_window.position = ((vs - Vector2(ww, wh)) / 2.0).round()
	_window.size = Vector2(ww, wh)
	_title.position = Vector2(SIDE_PAD + 4, 6)
	_title.size = Vector2(ww * 0.5, 38)
	_sub.position = Vector2(SIDE_PAD + 6, 44)
	_sub.size = Vector2(ww * 0.62, 22)
	_btn_pause.size = Vector2(150, 36)
	_btn_pause.position = Vector2(ww - SIDE_PAD - 150, 18)
	_btn_sound.size = Vector2(130, 36)
	_btn_sound.position = Vector2(ww - SIDE_PAD - 150 - 12 - 130, 18)
	var frame: Control = _window.get_node("PlayFrame")
	frame.position = Vector2(SIDE_PAD - 4, HEADER_H - 4)
	frame.size = Vector2(pw + 8, ph + 8)
	_container.stretch_shrink = _k
	_container.position = Vector2(SIDE_PAD, HEADER_H)
	_container.size = Vector2(pw, ph)
	_footer.position = Vector2(SIDE_PAD + 4, HEADER_H + ph + 14)
	_footer.size = Vector2(pw - 220, 24)
	_btn_serve.size = Vector2(200, 38)
	_btn_serve.position = Vector2(ww - SIDE_PAD - 200, HEADER_H + ph + 8)
	_pause_card.reset_size()
	var pcs: Vector2 = _pause_card.get_combined_minimum_size()
	_pause_card.size = pcs
	_pause_card.position = Vector2(SIDE_PAD + (pw - pcs.x) / 2.0, HEADER_H + (ph - pcs.y) / 2.0).round()
	if not _backers.is_empty():
		_sync_backers()


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels.append(l)
	return l


func _button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	b.set_meta("pt_primary", primary)
	style_button(b, primary)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, COL_INK)
	_buttons.append(b)
	return b


# ============================================================== art style (chrome)
# Static so the option-sheet renderer can build the same chrome. Style A returns exactly the
# original values.

static func window_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CREAM
	sb.border_color = COL_OAK
	sb.set_border_width_all(8)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0.1, 0.06, 0.04, 0.35)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	if not PX.legacy():
		if PX.chunky():
			sb.set_corner_radius_all(6)
			sb.corner_detail = 3
		if bool(PX.S["drop_shadow"]):
			sb.shadow_size = 0
	return sb


static func frame_box() -> StyleBoxFlat:
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = COL_INK
	fsb.set_corner_radius_all(4)
	if not PX.legacy() and PX.chunky():
		fsb.set_corner_radius_all(0)
	return fsb


static func pause_box() -> StyleBoxFlat:
	var psb := StyleBoxFlat.new()
	psb.bg_color = COL_CREAM
	psb.border_color = COL_OAK_DARK
	psb.set_border_width_all(6)
	psb.set_corner_radius_all(12)
	psb.set_content_margin_all(26)
	if not PX.legacy() and PX.chunky():
		psb.set_corner_radius_all(5)
		psb.corner_detail = 3
	return psb


## Ink outline panel (B..F) placed behind a chrome panel; E adds a cream halo panel outside it
## and F gives the outline a hard cocoa drop shadow.
static func backer_box(radius: int, col: Color, drop: bool) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	b.set_corner_radius_all(radius)
	b.corner_detail = 3 if PX.chunky() else 8
	if drop:
		b.shadow_color = PX.DROP_COL
		b.shadow_size = 1
		b.shadow_offset = Vector2(5, 6)
	return b


static func ui_font() -> Font:
	if PX.legacy() or float(PX.S.get("ui_embolden", 0.0)) <= 0.0:
		return null
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = float(PX.S["ui_embolden"])  # 0.6 ~ weight 700 (shared text rule)
	return fv


## Shared text rule on system-font chrome text (labels, buttons): D 1px outline, E + cream
## halo, F 2px outline + cocoa drop shadow. Dark text gets a cream outline (as the pixel font).
static func style_ui_text(c: Control, col: Color) -> void:
	for k in ["outline_size", "shadow_outline_size", "shadow_offset_x", "shadow_offset_y"]:
		c.remove_theme_constant_override(k)
	for k in ["font_outline_color", "font_shadow_color"]:
		c.remove_theme_color_override(k)
	if PX.legacy():
		return
	var ring: int = int(PX.S.get("text_ring", 0))
	var small: bool = c.get_theme_font_size("font_size") < 20
	if small:
		ring = mini(ring, 1)  # small print: 1px outline, no halo (as pixel text below scale 2)
	var dark: bool = col.get_luminance() < 0.6
	if ring > 0:
		c.add_theme_constant_override("outline_size", ring * 2)
		c.add_theme_color_override("font_outline_color", COL_CREAM if dark else COL_INK)
	if bool(PX.S.get("text_halo", false)) and ring > 0 and not dark and not small:
		c.add_theme_color_override("font_shadow_color", COL_CREAM)
		c.add_theme_constant_override("shadow_offset_x", 0)
		c.add_theme_constant_override("shadow_offset_y", 0)
		c.add_theme_constant_override("shadow_outline_size", ring * 2 + 2)
	if bool(PX.S.get("text_shadow", false)):
		c.add_theme_color_override("font_shadow_color", PX.DROP_COL)
		c.add_theme_constant_override("shadow_offset_x", 1)
		c.add_theme_constant_override("shadow_offset_y", 1)
		c.add_theme_constant_override("shadow_outline_size", ring * 2)


static func style_button(b: Button, primary: bool) -> void:
	var base := COL_HONEY if primary else COL_OAK
	var bw: int = 2
	var rad: int = 8
	var lip: int = 0
	if not PX.legacy():
		bw = 2 + int(PX.S["panel_border_px"]) - 1
		if PX.chunky():
			rad = 4
			lip = 2
	for state in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = base if state == "normal" else (base.lightened(0.12) if state == "hover" else base.darkened(0.12))
		s.border_color = COL_INK
		s.set_border_width_all(bw)
		s.set_corner_radius_all(rad)
		s.set_content_margin_all(8)
		if lip > 0:
			# chunky "pressable" lip: thicker bottom border (moves to the top when pressed)
			s.border_width_bottom = bw + (lip if state != "pressed" else 0)
			if state == "pressed":
				s.border_width_top = bw + lip
			s.corner_detail = 3
		if bool(PX.S["drop_shadow"]) and state != "pressed":
			s.shadow_color = PX.DROP_COL
			s.shadow_size = 1
			s.shadow_offset = Vector2(2, 3)
		b.add_theme_stylebox_override(state, s)


## Live style switch (test panel "Art style"): rebuild chrome + re-wire the play area FX.
func apply_art_style() -> void:
	if _window == null:
		return
	_window.add_theme_stylebox_override("panel", window_box())
	(_window.get_node("PlayFrame") as Panel).add_theme_stylebox_override("panel", frame_box())
	_pause_card.add_theme_stylebox_override("panel", pause_box())
	var f: Font = ui_font()
	for b in _buttons:
		style_button(b, bool(b.get_meta("pt_primary", false)))
		if f != null:
			b.add_theme_font_override("font", f)
		else:
			b.remove_theme_font_override("font")
		style_ui_text(b, COL_INK)
	for l in _labels:
		if f != null:
			l.add_theme_font_override("font", f)
		else:
			l.remove_theme_font_override("font")
		style_ui_text(l, l.get_theme_color("font_color"))
	for bk in _backers:
		for pnl in bk["panels"]:
			(pnl as Node).get_parent().remove_child(pnl)
			(pnl as Node).queue_free()
	_backers.clear()
	var pb: int = int(PX.S["panel_border_px"])
	if not PX.legacy() and pb > 0:
		_add_backers(_window, _root, 6 if PX.chunky() else 14, pb)
		_add_backers(_pause_card, _window, 5 if PX.chunky() else 12, pb)
	if game != null:
		game.call("apply_art_style")
	_layout()


func _add_backers(target: Control, parent: Control, radius: int, pb: int) -> void:
	var panels: Array = []
	var grows: Array = []
	if bool(PX.S["halo"]):
		var h := Panel.new()
		h.name = str(target.name) + "Halo"
		h.add_theme_stylebox_override("panel", backer_box(radius + pb + 2, COL_CREAM, false))
		panels.append(h)
		grows.append(float(pb + 2))
	var o := Panel.new()
	o.name = str(target.name) + "Outline"
	o.add_theme_stylebox_override("panel", backer_box(radius + pb, COL_INK, bool(PX.S["drop_shadow"])))
	panels.append(o)
	grows.append(float(pb))
	for pnl in panels:
		(pnl as Panel).mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(pnl)
		parent.move_child(pnl, target.get_index())
	_backers.append({"target": target, "panels": panels, "grow": grows})
	if not target.visibility_changed.is_connected(_sync_backers):
		target.visibility_changed.connect(_sync_backers)


func _sync_backers() -> void:
	for bk in _backers:
		var t: Control = bk["target"]
		for i in (bk["panels"] as Array).size():
			var pnl: Panel = bk["panels"][i]
			var g: float = bk["grow"][i]
			pnl.position = t.position - Vector2(g, g)
			pnl.size = t.size + Vector2(g, g) * 2.0
			pnl.visible = t.visible
