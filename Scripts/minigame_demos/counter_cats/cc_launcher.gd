extends CanvasLayer

## "Counter Cats" test panel (F11 toggles). Picks recipe (difficulty), cat chaos,
## leniency, hold->toggle and the counter cat, then asks the demo to open the
## overlay. Also has two test helpers that stir up / bond the live cafe cats so
## every branch (fizzy bat, frazzled loaf, helper paw) can be tried quickly.

signal start_requested(opts: Dictionary)
signal resume_requested
signal fizz_requested
signal bond_requested

const Art := preload("res://Scripts/minigame_demos/counter_cats/cc_art.gd")
const R := preload("res://Scripts/minigame_demos/counter_cats/cc_recipes.gd")
const THEME_PATH := "res://UI/cozy_theme.tres"

var panel: PanelContainer
var recipe_opt: OptionButton
var chaos_opt: OptionButton
var len_opt: OptionButton
var toggle_chk: CheckBox
var cat_opt: OptionButton
var style_opt: OptionButton
var _root_ctl: Control
var _icon: TextureRect
var start_btn: Button
var resume_btn: Button
var last_lbl: Label
var cats_lbl: Label
var _cat_ids: Array = []          # instance ids in cat_opt order (index 0 = auto)

func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func is_shown() -> bool:
	return panel.visible

func set_shown(on: bool) -> void:
	panel.visible = on
	if on:
		start_btn.grab_focus()

func set_parked(on: bool) -> void:
	resume_btn.visible = on
	start_btn.text = "Start new order" if on else "Start cooking!"

func set_last_result(text: String) -> void:
	last_lbl.text = text
	last_lbl.visible = text != ""

## cats: Array of {id, name, mood, overstim, trust, resting}
func set_cats(cats: Array) -> void:
	var keep: int = cat_opt.selected
	var keep_id: int = _cat_ids[keep] if keep >= 0 and keep < _cat_ids.size() else 0
	cat_opt.clear()
	_cat_ids = [0]
	cat_opt.add_item("Auto (most frazzled cat)")
	var lines: PackedStringArray = []
	for c in cats:
		var tag: String = "%s - %s, overstim %d, trust %d%s" % [c["name"], c["mood"], int(c["overstim"]), int(c["trust"]), " (resting)" if bool(c.get("resting", false)) else ""]
		lines.append(tag)
		if bool(c.get("resting", false)):
			continue
		cat_opt.add_item(str(c["name"]))
		_cat_ids.append(int(c["id"]))
	cats_lbl.text = "\n".join(lines) if not lines.is_empty() else "No cats in the cafe right now."
	var sel: int = maxi(0, _cat_ids.find(keep_id))
	cat_opt.select(sel)

func options() -> Dictionary:
	var ri: int = maxi(0, recipe_opt.selected)
	return {
		"recipe_id": R.recipe_by_index(ri)["id"],
		"recipe_name": R.recipe_by_index(ri)["name"],
		"chaos": maxi(0, chaos_opt.selected),
		"leniency": R.LENIENCY[maxi(0, len_opt.selected)],
		"toggle": toggle_chk.button_pressed,
		"preferred_cat": _cat_ids[cat_opt.selected] if cat_opt.selected >= 0 and cat_opt.selected < _cat_ids.size() else 0,
	}

func select_cat_id(id: int) -> void:
	var i: int = _cat_ids.find(id)
	if i >= 0:
		cat_opt.select(i)

## For probes: set options directly.
func apply_options(o: Dictionary) -> void:
	for i in range(R.RECIPES.size()):
		if R.RECIPES[i]["id"] == str(o.get("recipe_id", "")):
			recipe_opt.select(i)
	if o.has("chaos"):
		chaos_opt.select(clampi(int(o["chaos"]), 0, 2))
	if o.has("leniency"):
		len_opt.select(maxi(0, R.LENIENCY.find(float(o["leniency"]))))
	if o.has("toggle"):
		toggle_chk.button_pressed = bool(o["toggle"])
	if o.has("art_style"):
		set_art_style(str(o["art_style"]))

## Art style A-F (cc_art.gd STYLES): one switch for every Counter Cats draw
## helper. Takes effect immediately on this panel and on the next order opened.
func set_art_style(letter: String) -> void:
	Art.set_style(letter)
	var i: int = Art.STYLE_ORDER.find(Art.style)
	if style_opt != null and i >= 0 and style_opt.selected != i:
		style_opt.select(i)
	_restyle()

func _panel_sb() -> StyleBox:
	if not Art.is_a():
		return Art.chrome_box(Art.CREAM, Art.OAK, 3, 15, Vector4(18, 14, 18, 16))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Art.CREAM
	sb.border_color = Art.OAK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0.09, 0.05, 0.03, 0.25)
	sb.shadow_size = 8
	return sb

func _restyle() -> void:
	if ResourceLoader.exists(THEME_PATH):
		_root_ctl.theme = Art.ui_theme(THEME_PATH)
	panel.add_theme_stylebox_override("panel", _panel_sb())
	_icon.texture = Art.paw(Art.OAK_DARK, "paw_oak")

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_ctl = root
	if ResourceLoader.exists(THEME_PATH):
		root.theme = Art.ui_theme(THEME_PATH)
	add_child(root)
	panel = PanelContainer.new()
	panel.name = "CounterCatsPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_right = -20
	panel.offset_top = -250
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", _panel_sb())
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var icon := TextureRect.new()
	_icon = icon
	icon.texture = Art.paw(Art.OAK_DARK, "paw_oak")
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(30, 26)
	head.add_child(icon)
	var t := Label.new()
	t.text = "Counter Cats"
	t.add_theme_font_size_override("font_size", 24)
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var f := Label.new()
	f.text = "F11"
	f.add_theme_font_size_override("font_size", 14)
	f.add_theme_color_override("font_color", Art.MUTED)
	head.add_child(f)
	var sub := Label.new()
	sub.text = "Whisker Kitchen - minigame demo test panel"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Art.MUTED)
	vb.add_child(sub)

	recipe_opt = _row(vb, "Recipe")
	for r in R.RECIPES:
		recipe_opt.add_item("%s  (%s)" % [r["name"], r["difficulty"]])
	chaos_opt = _row(vb, "Cat chaos")
	chaos_opt.add_item("Off (cat just purrs)")
	chaos_opt.add_item("Cozy (1 visit)")
	chaos_opt.add_item("Lively (2 visits)")
	chaos_opt.select(1)
	len_opt = _row(vb, "Leniency")
	len_opt.add_item("x1")
	len_opt.add_item("x1.5")
	len_opt.add_item("x2")
	toggle_chk = CheckBox.new()
	toggle_chk.text = "Tap instead of hold (pour + pet)"
	toggle_chk.add_theme_font_size_override("font_size", 15)
	vb.add_child(toggle_chk)
	cat_opt = _row(vb, "Counter cat")
	cat_opt.add_item("Auto (most frazzled cat)")
	_cat_ids = [0]
	style_opt = _row(vb, "Art style")
	for l in Art.STYLE_ORDER:
		style_opt.add_item("%s  %s" % [l, Art.STYLES[l]["desc"]])
	style_opt.select(maxi(0, Art.STYLE_ORDER.find(Art.style)))
	style_opt.tooltip_text = "Pixel-art style option sheet A-F (A = current art). Applies to the next order."
	style_opt.item_selected.connect(func(i: int) -> void: set_art_style(Art.STYLE_ORDER[i]))

	start_btn = Button.new()
	start_btn.text = "Start cooking!"
	start_btn.custom_minimum_size = Vector2(0, 42)
	start_btn.pressed.connect(func() -> void: start_requested.emit(options()))
	vb.add_child(start_btn)
	resume_btn = Button.new()
	resume_btn.text = "Resume parked order"
	resume_btn.visible = false
	resume_btn.pressed.connect(func() -> void: resume_requested.emit())
	vb.add_child(resume_btn)

	last_lbl = Label.new()
	last_lbl.add_theme_font_size_override("font_size", 15)
	last_lbl.add_theme_color_override("font_color", Art.SAGE_DARK)
	last_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	last_lbl.custom_minimum_size = Vector2(300, 0)
	last_lbl.visible = false
	vb.add_child(last_lbl)

	var sep := HSeparator.new()
	vb.add_child(sep)
	var cats_t := Label.new()
	cats_t.text = "Cafe cats (live)"
	cats_t.add_theme_font_size_override("font_size", 15)
	vb.add_child(cats_t)
	cats_lbl = Label.new()
	cats_lbl.add_theme_font_size_override("font_size", 13)
	cats_lbl.add_theme_color_override("font_color", Art.MUTED)
	cats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cats_lbl.custom_minimum_size = Vector2(300, 0)
	vb.add_child(cats_lbl)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	vb.add_child(tools)
	var fizz := Button.new()
	fizz.text = "Fizz up cats"
	fizz.tooltip_text = "Test helper: raise every cafe cat's overstim to 45-90 (fizzy / frazzled moods)"
	fizz.add_theme_font_size_override("font_size", 14)
	fizz.pressed.connect(func() -> void: fizz_requested.emit())
	tools.add_child(fizz)
	var bond := Button.new()
	bond.text = "Bond a cat (helper)"
	bond.tooltip_text = "Test helper: set the selected (or first) cat to trust 75 and calm, so it lends a paw"
	bond.add_theme_font_size_override("font_size", 14)
	bond.pressed.connect(func() -> void: bond_requested.emit())
	tools.add_child(bond)

func _row(parent: Control, label: String) -> OptionButton:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	parent.add_child(hb)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(100, 0)
	l.add_theme_font_size_override("font_size", 15)
	hb.add_child(l)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_size_override("font_size", 15)
	hb.add_child(o)
	return o
