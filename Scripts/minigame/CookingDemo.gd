extends Node

## "Paw & Pour" Test Kitchen: the real cafe (MainLevel3D, unmodified) runs as the live background
## and a small launcher panel (top-right, F10 hides it) opens any recipe in MinigameHost over the
## paused cafe. Scene: res://Scenes/Minigames/CookingDemo.tscn. Docs: Docs/MINIGAMES.md.
##
## The level is a child (not the current scene), so it never reads or writes the player's save.
## After a dish is served: result card -> unpause -> level.add_money(x, "order") and a HUD toast
## (both guarded, so the demo also runs without the level).
##
## Optional user args (after `--`, also work through Tools/capture_screenshot.gd):
##   open=<recipe_id>          open that recipe on boot (ticket first)
##   step=<recipe_id>:<k>      open at step k (earlier steps count as perfect) - verb screenshots
##   result=<recipe_id>        cook instantly (injected accuracies) and show the result card
##   resultc=<recipe_id>       same, but a sloppy + slow cook -> C "Still tasty!" card
##   serve=<recipe_id>         cook instantly and stop at the Serve bell
##   park=<recipe_id>          open it and show the park prompt
##   queue                     start the order-queue simulation (1 open + 2 pending tickets)
##   mod=<modifier_id>         to_go | take_your_time | kid_size
##   lenient=<1|1.5|2>         Gentle Paws leniency       collapsed / hidden   launcher state
##   --ck-art-style=<A..F>     art style (A = today's art; B..F = the shared minigame outline
##                             options). The launcher's "Art style" option switches it live.

const LEVEL_SCENE := "res://Scenes/Prototype3D/MainLevel3D.tscn"
const HOST_SCENE := "res://UI/Minigame/MinigameHost.tscn"
const COOKING_GAME := "res://Scripts/minigame/cooking/CookingGame.gd"
const DEBUG_STEP := "res://Scripts/minigame/cooking/steps/DebugInstantStep.gd"
const RECIPES_PATH := "res://Data/recipes.json"
const THEME_PATH := "res://UI/cozy_theme.tres"
const StepRegistry = preload("res://Scripts/minigame/cooking/StepRegistry.gd")
const PixelDraw = preload("res://Scripts/minigame/cooking/PixelDraw.gd")
const KitchenArt = preload("res://Scripts/minigame/cooking/KitchenArt.gd")
const KitchenChrome = preload("res://Scripts/minigame/cooking/KitchenChrome.gd")
const CookingGame = preload("res://Scripts/minigame/cooking/CookingGame.gd")

const MODIFIER_IDS: Array[String] = ["", "to_go", "take_your_time", "kid_size"]
const MODIFIER_NAMES: Array[String] = ["None", "To go!", "Take your time", "Kid size"]
const PATRON_FOR_MOD: Dictionary = {
	"": "Foodie Friend", "to_go": "Busy Remote Worker", "take_your_time": "Gentle Reader", "kid_size": "Hyper Toddler",
}
const LENIENCY: Array[float] = [1.0, 1.5, 2.0]
const LENIENCY_NAMES: Array[String] = ["Cozy x1.0", "Relaxed x1.5", "Sleepy x2.0"]
const PANEL_W := 452.0
const PANEL_TOP := 76.0
const LAUNCHER_LAYER := 8

const C_INK := Color("#4A3426")
const C_CREAM := Color("#FFF6EA")
const C_CREAM_DARK := Color("#F1E2CC")
const C_OAK := Color("#C9A27A")
const C_OAK_DARK := Color("#A57C55")
const C_HONEY_LIGHT := Color("#F4D58D")
const C_SAGE := Color("#8FBF9F")

var level: Node = null
var host: CanvasLayer
var recipes: Array = []
## Pending tickets (contexts). Parked orders go to the front; the order queue appends.
var pending: Array = []
var served: int = 0
var local_money: int = 0
var _rep_carry: float = 0.0
var _last_result: Dictionary = {}

var _launcher: CanvasLayer
var _panel: PanelContainer
var _body: VBoxContainer
var _collapse_btn: Button
var _mod_opt: OptionButton
var _len_opt: OptionButton
var _seed_opt: OptionButton
var _seed_spin: SpinBox
var _toggle_chk: CheckBox
var _noclock_chk: CheckBox
var _reduced_chk: CheckBox
var _art_opt: OptionButton
var _pending_box: VBoxContainer
var _pending_title: Label
var _recipe_scroll: ScrollContainer
var _status: Label
var _wallet: Label
var _auto_serve: bool = false
var _force_slow: bool = false


func _ready() -> void:
	_spawn_level()
	host = get_node_or_null("MinigameHost") as CanvasLayer
	if host == null:
		host = (load(HOST_SCENE) as PackedScene).instantiate() as CanvasLayer
		add_child(host)
	host.connect("finished", _on_finished)
	host.connect("parked", _on_parked)
	host.connect("aborted", _on_aborted)
	host.connect("opened", _on_opened)
	recipes = _load_recipes()
	_build_launcher()
	_refresh_panel()
	_start_helper_timer()
	get_viewport().size_changed.connect(_layout_panel)
	_layout_panel.call_deferred()
	_handle_args.call_deferred()


func _spawn_level() -> void:
	if not ResourceLoader.exists(LEVEL_SCENE):
		push_warning("CookingDemo: %s missing; running without the cafe background" % LEVEL_SCENE)
		return
	var ps: PackedScene = load(LEVEL_SCENE) as PackedScene
	if ps == null:
		return
	level = ps.instantiate()
	level.name = "Cafe"
	add_child(level)
	move_child(level, 0)


func _load_recipes() -> Array:
	var f: FileAccess = FileAccess.open(RECIPES_PATH, FileAccess.READ)
	if f == null:
		push_error("CookingDemo: cannot open %s" % RECIPES_PATH)
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if data is Array else []


func _recipe(id: String) -> Dictionary:
	for r in recipes:
		if String((r as Dictionary).get("id", "")) == id:
			return r
	return {}


func _settings() -> Dictionary:
	return {
		"leniency": LENIENCY[maxi(_len_opt.selected, 0)],
		"hold_to_toggle": _toggle_chk.button_pressed,
		"no_clock": _noclock_chk.button_pressed,
		"reduced_motion": _reduced_chk.button_pressed,
	}


func _seed() -> int:
	return int(_seed_spin.value) if _seed_opt.selected == 1 else randi()


## Builds a cooking context the way the cafe integration will (see Docs/MINIGAMES.md).
## mod = null uses the launcher's patron modifier.
func make_context(id: String, mod: Variant = null) -> Dictionary:
	var m: String = MODIFIER_IDS[maxi(_mod_opt.selected, 0)] if mod == null else String(mod)
	return {
		"recipe": _recipe(id),
		"seed": _seed(),
		"modifier": m,
		"patron_name": String(PATRON_FOR_MOD.get(m, "Foodie Friend")),
		"settings": _settings(),
		"allow_stand_ins": true,
	}


func cook(id: String, ctx: Dictionary = {}) -> void:
	if host.call("is_open"):
		return
	if _recipe(id).is_empty():
		_set_status("Unknown recipe '%s'" % id)
		return
	var c: Dictionary = ctx if not ctx.is_empty() else make_context(id)
	_open_ctx(c)


func _open_ctx(c: Dictionary) -> void:
	if host.call("is_open"):
		return
	# Options can change while a ticket waits; the latest Gentle Paws settings always apply.
	c["settings"] = _settings()
	c["has_next_order"] = not pending.is_empty()
	_cancel_decor_placement()
	host.call("open", load(COOKING_GAME), c)


## The launcher stays clickable while the cafe is in Build / placement mode: drop the held decor
## first so its cursor UI isn't frozen under (or over) the paused kitchen.
func _cancel_decor_placement() -> void:
	if level == null:
		return
	var placement: Node = level.find_child("DecorPlacement3D", true, false)
	if placement != null and placement.has_method("is_holding") and placement.has_method("cancel_hold"):
		if bool(placement.call("is_holding")):
			placement.call("cancel_hold")


func random_order() -> void:
	if recipes.is_empty():
		return
	var r: Dictionary = recipes[randi() % recipes.size()]
	var m: String = MODIFIER_IDS[randi() % MODIFIER_IDS.size()]
	cook(String(r.get("id", "")), make_context(String(r.get("id", "")), m))


## Order-queue simulation: one ticket opens now, two wait (Next order > walks the queue).
func start_queue() -> void:
	if host.call("is_open") or recipes.is_empty():
		return
	var ids: Array = []
	for r in recipes:
		ids.append(String((r as Dictionary).get("id", "")))
	ids.shuffle()
	for k in range(3):
		var m: String = MODIFIER_IDS[randi() % MODIFIER_IDS.size()]
		var ctx: Dictionary = make_context(String(ids[k % ids.size()]), m)
		ctx["ticket_no"] = served + k + 1
		pending.append(ctx)
	cook_next()


func cook_next() -> void:
	if pending.is_empty() or host.call("is_open"):
		return
	var ctx: Dictionary = pending.pop_front()
	_open_ctx(ctx)
	_refresh_panel()


func _cook_pending(i: int) -> void:
	if i < 0 or i >= pending.size() or host.call("is_open"):
		return
	var ctx: Dictionary = pending[i]
	pending.remove_at(i)
	_open_ctx(ctx)
	_refresh_panel()


# --- Host signals (all after the cafe unpauses) ------------------------------------------------

func _on_opened(_ctx: Dictionary) -> void:
	_refresh_panel()


func _on_finished(_ctx: Dictionary, result: Dictionary) -> void:
	_last_result = result
	var m: int = int(result.get("money", 0))
	served += 1
	if level != null and level.has_method("add_money"):
		level.call("add_money", m, "order")
	else:
		local_money += m
	_rep_carry += float(result.get("rep", 0.0))
	var whole: int = int(floorf(_rep_carry))
	if whole > 0 and level != null and level.has_method("add_reputation"):
		level.call("add_reputation", whole)
		_rep_carry -= float(whole)
	var line: String = "%s - %s %s  +$%d" % [String(result.get("display_name", "")), String(result.get("grade", "")), String(result.get("grade_text", "")), m]
	_toast(line)
	_set_status("Served %s  (precision %.2f, speed %.2f, score %.3f, %s / par %s)" % [
		line, float(result.get("precision", 0.0)), float(result.get("speed", 0.0)), float(result.get("score", 0.0)),
		_fmt(float(result.get("time_sec", 0.0))), _fmt(float(result.get("par_sec", 0.0)))])
	if bool(result.get("next_order", false)):
		cook_next.call_deferred()
	_refresh_panel()


func _on_parked(ctx: Dictionary) -> void:
	# Demo-only debug keys must not survive a park (the order resumes from its real progress).
	for k in ["start_step", "pace", "step_override", "skip_intro"]:
		ctx.erase(k)
	ctx["parked"] = true
	pending.push_front(ctx)
	var nm: String = String((ctx.get("recipe", {}) as Dictionary).get("display_name", ""))
	_toast("%s parked on the counter" % nm)
	var kept: int = CookingGame.resume_step_count(ctx)
	_set_status("Parked %s - same seed (%d)%s when you resume." % [nm, int(ctx.get("seed", 0)), (", %d finished step%s kept" % [kept, "" if kept == 1 else "s"]) if kept > 0 else ""])
	_refresh_panel()


func _on_aborted(_ctx: Dictionary) -> void:
	_set_status("Kitchen closed without serving.")
	_refresh_panel()


func _toast(text: String) -> void:
	var hud: Node = level.get_node_or_null("HUD3D") if level != null else null
	if hud != null and hud.has_method("show_notice"):
		hud.call("show_notice", text, 3.0)


func _set_status(t: String) -> void:
	if _status != null:
		_status.text = t


static func _fmt(sec: float) -> String:
	var s: int = int(floorf(maxf(sec, 0.0)))
	return "%d:%02d" % [int(s / 60.0), s % 60]


# --- Launcher UI --------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_F10 and not host.call("is_open"):
			_panel.visible = not _panel.visible
			get_viewport().set_input_as_handled()


## Live art-style switch (launcher "Art style" option; also callable from tests): sets the
## PixelDraw style, rebuilds the launcher in it (keeping every option) and restyles the host.
func set_art_style(letter: String) -> void:
	PixelDraw.set_style(letter)
	apply_art_style()


func apply_art_style() -> void:
	if _panel != null:
		var keep: Dictionary = {
			"mod": _mod_opt.selected, "len": _len_opt.selected, "seed": _seed_opt.selected,
			"seed_v": _seed_spin.value, "toggle": _toggle_chk.button_pressed,
			"noclock": _noclock_chk.button_pressed, "reduced": _reduced_chk.button_pressed,
			"collapsed": not _body.visible, "visible": _panel.visible,
		}
		_launcher.queue_free()
		_launcher = null
		_panel = null
		_build_launcher()
		_mod_opt.select(int(keep["mod"]))
		_len_opt.select(int(keep["len"]))
		_seed_opt.select(int(keep["seed"]))
		_seed_spin.value = float(keep["seed_v"])
		_seed_spin.editable = int(keep["seed"]) == 1
		_toggle_chk.button_pressed = bool(keep["toggle"])
		_noclock_chk.button_pressed = bool(keep["noclock"])
		_reduced_chk.button_pressed = bool(keep["reduced"])
		_panel.visible = bool(keep["visible"])
		if bool(keep["collapsed"]):
			toggle_collapsed()
		_refresh_panel()
		_layout_panel.call_deferred()
	if host != null and host.has_method("apply_art_style"):
		host.call("apply_art_style")


func toggle_collapsed() -> void:
	_body.visible = not _body.visible
	_collapse_btn.text = "+" if not _body.visible else "-"
	_layout_panel()


## A: StyleBoxFlat (unchanged); B..F: the shared pixel panel (KitchenChrome.box).
func _style(bg: Color, border: Color, bw: int, radius: int, pad: Vector4) -> StyleBox:
	if not PixelDraw.legacy():
		return KitchenChrome.box(bg, border, bw, radius, pad)
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


func _lbl(text: String, size: int, color: Color = C_INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not PixelDraw.legacy():
		KitchenChrome.style_text(l, color)
	return l


func _btn(text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, C_INK)
	var bg: Color = C_HONEY_LIGHT if primary else C_CREAM
	b.add_theme_stylebox_override("normal", _style(bg, C_OAK, 2, 8, Vector4(12, 5, 12, 5)))
	b.add_theme_stylebox_override("hover", _style(bg.lightened(0.3), C_OAK_DARK, 2, 8, Vector4(12, 5, 12, 5)))
	b.add_theme_stylebox_override("pressed", _style(bg.darkened(0.08), C_OAK_DARK, 2, 8, Vector4(12, 6, 12, 4)))
	b.add_theme_stylebox_override("disabled", _style(C_CREAM_DARK, C_CREAM_DARK.darkened(0.1), 2, 8, Vector4(12, 5, 12, 5)))
	if not PixelDraw.legacy():
		KitchenChrome.style_text(b, C_INK)
	b.pressed.connect(cb)
	return b


func _chk(text: String, parent: Control, tip: String = "") -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 15)
	c.add_theme_color_override("font_color", C_INK)
	c.add_theme_color_override("font_hover_color", C_INK)
	c.add_theme_color_override("font_pressed_color", C_INK)
	if not PixelDraw.legacy():
		KitchenChrome.style_text(c, C_INK)
	parent.add_child(c)
	return c


func _opt(items: Array, parent: Control) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 15)
	for it in items:
		o.add_item(String(it))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(o)
	return o


func _build_launcher() -> void:
	_launcher = CanvasLayer.new()
	_launcher.name = "TestKitchenLauncher"
	_launcher.layer = LAUNCHER_LAYER
	_launcher.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_launcher)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	if ResourceLoader.exists(THEME_PATH):
		_panel.theme = KitchenChrome.ui_theme(THEME_PATH)
	var psb: StyleBox = _style(Color(C_CREAM, 0.97), C_OAK, 3, 12, Vector4(14, 10, 14, 12))
	if psb is StyleBoxFlat:
		(psb as StyleBoxFlat).shadow_color = Color(0.09, 0.05, 0.03, 0.25)
		(psb as StyleBoxFlat).shadow_size = 8
		(psb as StyleBoxFlat).shadow_offset = Vector2(0, 3)
	_panel.add_theme_stylebox_override("panel", psb)
	_launcher.add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)

	# Header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(30, 30)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	KitchenChrome.art_canvas(badge, func(ci: CanvasItem) -> void:
		ci.draw_set_transform(Vector2(0, 0), 0.0, Vector2(3, 3))
		KitchenArt.verb_icon(ci, Vector2.ZERO, "serve")
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE), 3.0)
	head.add_child(badge)
	var tbox := VBoxContainer.new()
	tbox.add_theme_constant_override("separation", -2)
	tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tbox)
	tbox.add_child(_lbl("Test Kitchen", 22))
	tbox.add_child(_lbl("Paw & Pour minigame demo  -  F10 hides", 15, C_OAK_DARK))
	_collapse_btn = _btn("-", toggle_collapsed)
	_collapse_btn.custom_minimum_size = Vector2(36, 32)
	_collapse_btn.tooltip_text = "Collapse / expand"
	head.add_child(_collapse_btn)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 7)
	root.add_child(_body)

	# Per-run options
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 5)
	_body.add_child(grid)
	grid.add_child(_lbl("Patron", 15))
	_mod_opt = _opt(MODIFIER_NAMES, grid)
	grid.add_child(_lbl("Gentle Paws", 15))
	_len_opt = _opt(LENIENCY_NAMES, grid)
	grid.add_child(_lbl("Seed", 15))
	var seed_row := HBoxContainer.new()
	seed_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(seed_row)
	_seed_opt = _opt(["Random", "Fixed"], seed_row)
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 999999
	_seed_spin.value = 1234
	_seed_spin.custom_minimum_size = Vector2(110, 0)
	_seed_spin.editable = false
	seed_row.add_child(_seed_spin)
	_seed_opt.item_selected.connect(func(i: int) -> void: _seed_spin.editable = i == 1)
	grid.add_child(_lbl("Art style", 15))
	var art_names: Array = []
	for l in PixelDraw.STYLE_ORDER:
		art_names.append("%s  %s" % [l, String(PixelDraw.STYLES[l]["name"])])
	_art_opt = _opt(art_names, grid)
	_art_opt.tooltip_text = "Pixel-art outline options (same letters in every minigame). A = today's art."
	_art_opt.select(PixelDraw.STYLE_ORDER.find(PixelDraw.style))
	_art_opt.item_selected.connect(func(i: int) -> void: set_art_style.call_deferred(PixelDraw.STYLE_ORDER[i]))

	var chk_row := HFlowContainer.new()
	chk_row.add_theme_constant_override("h_separation", 6)
	_body.add_child(chk_row)
	_toggle_chk = _chk("Hold > Toggle", chk_row, "Holds become tap-to-start / tap-to-stop")
	_noclock_chk = _chk("No-Clock", chk_row, "No par clock; speed never lowers the grade")
	_reduced_chk = _chk("Reduced motion", chk_row)

	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 8)
	_body.add_child(act)
	var rnd := _btn("Random order", random_order, true)
	rnd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(rnd)
	var q := _btn("Order queue (3)", start_queue)
	q.tooltip_text = "Opens one ticket now with two waiting: try [Next order >] on the result card"
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(q)

	_pending_title = _lbl("", 15, C_OAK_DARK)
	_body.add_child(_pending_title)
	_pending_box = VBoxContainer.new()
	_pending_box.add_theme_constant_override("separation", 4)
	_body.add_child(_pending_box)

	_body.add_child(_lbl("Recipes", 17))
	_recipe_scroll = ScrollContainer.new()
	_recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_recipe_scroll.custom_minimum_size = Vector2(0, 300)
	_body.add_child(_recipe_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	_recipe_scroll.add_child(list)
	for r in recipes:
		list.add_child(_recipe_row(r))

	_wallet = _lbl("", 15)
	_body.add_child(_wallet)
	_status = _lbl("Click a recipe to cook. In the kitchen: LMB / Space = pour, hold, tap. O = back burner. Enter = serve. F1 = hint. Esc = park.", 15, C_OAK_DARK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PANEL_W - 30.0, 0)
	_body.add_child(_status)


func _recipe_row(r: Dictionary) -> Button:
	var id: String = String(r.get("id", ""))
	var b := _btn("", cook.bind(id))
	b.name = "Recipe_" + id
	b.custom_minimum_size = Vector2(0, 80)
	b.tooltip_text = "station: %s   unlock: %s   par bonus %ss" % [String(r.get("station", "")), JSON.stringify(r.get("unlock", {})), str(r.get("par_bonus_sec", 3))]
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 6)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	b.add_child(m)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 8)
	m.add_child(hb)
	var dish := Control.new()
	dish.custom_minimum_size = Vector2(64, 56)
	dish.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dd: Dictionary = r.get("dish", {}) if r.get("dish", {}) is Dictionary else {}
	KitchenChrome.art_canvas(dish, func(ci: CanvasItem) -> void:
		ci.draw_set_transform(Vector2(0, 0), 0.0, Vector2.ONE)
		KitchenArt.dish(ci, Vector2(32, 54), id, dd, {"great": true, "reduced": true, "fx": false}), 1.0)
	hb.add_child(dish)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	var nm := _lbl(String(r.get("display_name", id)), 16)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var tier: int = clampi(int(r.get("tier", 1)), 1, 3)
	top.add_child(_lbl("%s%s  $%d" % ["★".repeat(tier), "☆".repeat(3 - tier), int(r.get("base_price", 0))], 15, C_OAK_DARK))
	var verbs: Array = []
	for s in r.get("steps", []):
		verbs.append(String((s as Dictionary).get("type", "")))
	var icons := Control.new()
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# B..F: thicker outlines need a wider gap between the 10px icons (else they merge)
	var pitch: int = 11 if PixelDraw.legacy() else 13
	icons.custom_minimum_size = Vector2(verbs.size() * pitch * 2, 20 if PixelDraw.legacy() else 24)
	icons.tooltip_text = " > ".join(PackedStringArray(verbs))
	KitchenChrome.art_canvas(icons, func(ci: CanvasItem) -> void:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(2, 2))
		for k in range(verbs.size()):
			KitchenArt.verb_icon(ci, Vector2(k * pitch, 0 if PixelDraw.legacy() else 1), String(verbs[k]))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE), 2.0)
	vb.add_child(icons)
	var names: Array = []
	for v in verbs:
		names.append(String(KitchenArt.VERB_NAMES.get(String(v), String(v))).to_lower())
	var vl := _lbl(" > ".join(PackedStringArray(names)), 14, C_OAK_DARK)
	vl.clip_text = true
	vl.custom_minimum_size = Vector2(260, 0)
	vb.add_child(vl)
	return b


func _refresh_panel() -> void:
	if _pending_box == null:
		return
	for c in _pending_box.get_children():
		_pending_box.remove_child(c)
		c.queue_free()
	_pending_title.text = "Pending tickets (%d)" % pending.size() if not pending.is_empty() else "No pending tickets"
	for i in range(pending.size()):
		var ctx: Dictionary = pending[i]
		var nm: String = String((ctx.get("recipe", {}) as Dictionary).get("display_name", "?"))
		var mod: String = String(ctx.get("modifier", ""))
		var tag: String = "parked" if bool(ctx.get("parked", false)) else String(PATRON_FOR_MOD.get(mod, ""))
		var b := _btn("%s  -  %s%s" % [nm, tag, ("  (" + MODIFIER_NAMES[MODIFIER_IDS.find(mod)] + ")") if mod != "" and MODIFIER_IDS.has(mod) else ""], _cook_pending.bind(i), i == 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		_pending_box.add_child(b)
	_update_wallet()
	_layout_panel()


func _update_wallet() -> void:
	if _wallet == null:
		return
	var money: int = int(level.get("money")) if level != null and level.get("money") != null else local_money
	var rep: Variant = level.get("reputation") if level != null else null
	_wallet.text = "Cafe wallet $%d   rep %s   served %d" % [money, str(rep) if rep != null else "-", served]


func _layout_panel() -> void:
	if _panel == null:
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var max_h: float = vs.y - PANEL_TOP - 130.0
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	if _recipe_scroll != null:
		# recipe list gets whatever height is left (min 200)
		var other: float = 360.0 + float(pending.size()) * 34.0
		_recipe_scroll.custom_minimum_size = Vector2(0, clampf(max_h - other, 200.0, 560.0))
	_panel.reset_size()
	_panel.position = Vector2(vs.x - PANEL_W - 16.0, PANEL_TOP).round()


# --- Command-line hooks (screenshots / quick tries) ---------------------------------------

func _handle_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("mod="):
			var idx: int = MODIFIER_IDS.find(a.substr(4))
			if idx >= 0:
				_mod_opt.select(idx)
		elif a.begins_with("lenient="):
			var li: int = LENIENCY.find(float(a.substr(8)))
			if li >= 0:
				_len_opt.select(li)
		elif a == "collapsed":
			toggle_collapsed()
		elif a == "hidden":
			_panel.visible = false
	for a in args:
		if a.begins_with("open="):
			cook(a.substr(5))
		elif a.begins_with("step="):
			var parts: PackedStringArray = a.substr(5).split(":")
			var ctx: Dictionary = make_context(parts[0])
			ctx["start_step"] = int(parts[1]) if parts.size() > 1 else 0
			ctx["pace"] = 0.2
			cook(parts[0], ctx)
		elif a.begins_with("result=") or a.begins_with("resultc=") or a.begins_with("serve="):
			var id: String = a.get_slice("=", 1)
			var ctx2: Dictionary = make_context(id)
			ctx2["skip_intro"] = true
			ctx2["pace"] = 0.05
			var sloppy: bool = a.begins_with("resultc=")
			var acc: Array = [0.4, 0.5, 0.4, 0.45, 0.4, 0.4, 0.5, 0.4] if sloppy else [1.0, 0.95, 1.0, 0.95, 1.0, 1.0, 1.0, 0.95]
			ctx2["step_override"] = {"script": DEBUG_STEP, "accuracy": acc, "time": 1.0}
			if pending.is_empty():
				pending.append(make_context(String((recipes[0] as Dictionary).get("id", "")), "to_go"))
				_refresh_panel()
			cook(id, ctx2)
			_auto_serve = not a.begins_with("serve=")
			_force_slow = sloppy
		elif a.begins_with("park="):
			cook(a.substr(5))
			_park_soon.call_deferred()
		elif a == "queue":
			start_queue()


func _park_soon() -> void:
	await get_tree().create_timer(1.5, true, false, true).timeout
	host.call("request_park")


# Helper ticks that ignore pause: `result=` auto-serve and the wallet line.
func _start_helper_timer() -> void:
	var t := Timer.new()
	t.wait_time = 0.1
	t.autostart = true
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	t.timeout.connect(_tick_helpers)
	add_child(t)


func _tick_helpers() -> void:
	_update_wallet()
	if not _auto_serve or host == null or not host.call("is_open"):
		return
	var g: Node = host.call("get_game")
	if g == null or not g.has_method("press_serve") or not bool(g.call("is_ready_to_serve")):
		return
	if _force_slow:
		g.set("clock", float(g.get("par_sec")) * 1.9)
	if bool(g.call("press_serve")):
		_auto_serve = false
