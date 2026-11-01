extends CanvasLayer

## "Purr-fect Timing" test panel over the live cafe. F12 shows / hides it.
## Recipe list (keys 1-4 also start them), leniency, sound, hold->toggle, reduced motion and
## the input-offset calibration slider (-100..+100 ms). Works while the cafe runs.

signal start_requested(index: int)
signal resume_requested

const RecipesScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTRecipes.gd")
const JudgeScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTJudge.gd")
const PX := preload("res://Scripts/minigame_demos/purrfect_timing/PTPixel.gd")

const COL_CREAM := Color("#FFF6EA")
const COL_OAK := Color("#C9A27A")
const COL_OAK_DARK := Color("#A87C55")
const COL_INK := Color("#4A3426")
const COL_SAGE := Color("#8FBF9F")
const COL_HONEY := Color("#E8B04B")

## Set by the demo root; used to ignore hotkeys while an order is open.
var overlay: Node = null

var settings: Dictionary = {"leniency_idx": 0, "audio": true, "hold_toggle": false, "offset_ms": 0.0, "reduced_motion": false}

var _panel: PanelContainer
var _recipe_buttons: Array[Button] = []
var _leniency: OptionButton
var _audio: CheckBox
var _toggle: CheckBox
var _motion: CheckBox
var _art: OptionButton
var _offset: HSlider
var _offset_label: Label
var _resume_btn: Button
var _last: Label


func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func get_settings() -> Dictionary:
	return settings.duplicate()


func is_panel_visible() -> bool:
	return _panel != null and _panel.visible


func set_panel_visible(on: bool) -> void:
	if _panel != null:
		_panel.visible = on


## Art style A..F (shared minigame outline options). Applies to the play area and window chrome.
func set_art_style(letter: String) -> void:
	PX.set_style(letter)
	if _art != null:
		_art.select(maxi(0, PX.STYLE_ORDER.find(PX.style)))
	if overlay != null:
		overlay.call("apply_art_style")


func set_offset_ms(v: float) -> void:
	_offset.value = clampf(v, -100.0, 100.0)


func on_order_closed(res: Dictionary) -> void:
	_resume_btn.visible = false
	var c: Dictionary = res.get("counts", {})
	_last.text = "Last: %s  grade %s  (+$%d)\nPurr-fect %d  Good %d  Ok %d   best combo %d" % [
		str(res.get("name", "")), str(res.get("grade", "")), int(res.get("money", 0)),
		int(c.get("purrfect", 0)), int(c.get("good", 0)), int(c.get("ok", 0)), int(res.get("best_combo", 0))]
	_last.visible = true


func on_order_opened(_i: int) -> void:
	_resume_btn.visible = false


func on_parked() -> void:
	var nm: String = ""
	if overlay != null:
		nm = str((overlay.get("recipe") as Dictionary).get("name", ""))
	_resume_btn.text = "Resume parked: %s" % nm
	_resume_btn.visible = true
	_panel.visible = true


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_F12:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()
		return
	var busy: bool = overlay != null and bool(overlay.get("is_open"))
	if busy or not _panel.visible:
		return
	if k.keycode >= KEY_1 and k.keycode <= KEY_4:
		var i: int = int(k.keycode - KEY_1)
		if i < _recipe_buttons.size():
			start_requested.emit(i)
			get_viewport().set_input_as_handled()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PurrfectTimingPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CREAM
	sb.border_color = COL_OAK
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0.1, 0.06, 0.04, 0.3)
	sb.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(16, 150)
	_panel.custom_minimum_size = Vector2(330, 0)
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)

	var title := _label("Purr-fect Timing", 24, COL_INK)
	vb.add_child(title)
	vb.add_child(_label("Cozy rhythm cooking test panel   (F12 hide)", 13, COL_OAK_DARK))

	var recipes: Array = RecipesScript.all()
	for i in recipes.size():
		var r: Dictionary = recipes[i]
		var stars: String = ""
		for s in 4:
			stars += "*" if s < int(r.get("tier", 1)) else "."
		var b := _button("%d   %s     %s   $%d" % [i + 1, str(r.get("name", "")), stars, int(r.get("price", 0))], i == 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = str(r.get("blurb", ""))
		var idx: int = i
		b.pressed.connect(func() -> void: start_requested.emit(idx))
		vb.add_child(b)
		_recipe_buttons.append(b)

	_resume_btn = _button("Resume parked order", true)
	_resume_btn.visible = false
	_resume_btn.pressed.connect(func() -> void: resume_requested.emit())
	vb.add_child(_resume_btn)

	vb.add_child(HSeparator.new())
	var hl := HBoxContainer.new()
	hl.add_child(_label("Leniency", 15, COL_INK))
	_leniency = OptionButton.new()
	_leniency.focus_mode = Control.FOCUS_NONE
	for n in JudgeScript.LENIENCY_NAMES:
		_leniency.add_item(n)
	_leniency.select(0)
	_leniency.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leniency.item_selected.connect(func(i: int) -> void: settings["leniency_idx"] = i)
	hl.add_child(_leniency)
	vb.add_child(hl)
	vb.add_child(_label("Cozy = +-120 ms Purr-fect, +-220 ms Good", 12, COL_OAK_DARK))

	_audio = _check("Sound: soft beat + chimes", true)
	_audio.toggled.connect(func(on: bool) -> void: settings["audio"] = on)
	vb.add_child(_audio)
	_toggle = _check("Steam: click to start / stop (no holding)", false)
	_toggle.toggled.connect(func(on: bool) -> void: settings["hold_toggle"] = on)
	vb.add_child(_toggle)
	_motion = _check("Reduced motion", false)
	_motion.toggled.connect(func(on: bool) -> void: settings["reduced_motion"] = on)
	vb.add_child(_motion)

	var ha := HBoxContainer.new()
	ha.add_child(_label("Art style", 15, COL_INK))
	_art = OptionButton.new()
	_art.name = "ArtStyle"
	_art.focus_mode = Control.FOCUS_NONE
	for l in PX.STYLE_ORDER:
		_art.add_item("%s   %s" % [l, str(PX.STYLES[l]["desc"])])
	_art.select(maxi(0, PX.STYLE_ORDER.find(PX.style)))
	_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_art.tooltip_text = "Outline / shape style options (A = current art). Switches live, even mid-order."
	_art.item_selected.connect(func(i: int) -> void: set_art_style(PX.STYLE_ORDER[i]))
	ha.add_child(_art)
	vb.add_child(ha)

	_offset_label = _label("Input offset: +0 ms", 15, COL_INK)
	vb.add_child(_offset_label)
	_offset = HSlider.new()
	_offset.min_value = -100
	_offset.max_value = 100
	_offset.step = 5
	_offset.value = 0
	_offset.focus_mode = Control.FOCUS_NONE
	_offset.custom_minimum_size = Vector2(280, 20)
	_offset.value_changed.connect(_on_offset)
	vb.add_child(_offset)
	vb.add_child(_label("Hits feel late? slide right (+). Early? left (-).", 12, COL_OAK_DARK))

	_last = _label("", 13, COL_OAK_DARK)
	_last.visible = false
	vb.add_child(_last)


func _on_offset(v: float) -> void:
	settings["offset_ms"] = v
	_offset_label.text = "Input offset: %+d ms" % int(v)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _check(text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 14)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		c.add_theme_color_override(k, COL_INK)
	return c


func _button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	var base := COL_HONEY if primary else COL_OAK
	for state in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = base if state == "normal" else (base.lightened(0.12) if state == "hover" else base.darkened(0.12))
		s.border_color = COL_INK
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, s)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, COL_INK)
	return b
