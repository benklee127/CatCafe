extends CanvasLayer

## Minimal cozy HUD for the apartment (theme res://UI/cozy_theme.tres):
## - top-left: "Home" title chip + an "Evening" chip
## - bottom-left: hint line
## - bottom-right: "Go to Cafe" button
## - hover tooltip next to the cursor, prompt card for a clicked hotspot, toast, fade.
## Everything is built in code, icons are drawn procedurally (no textures).

signal action_pressed(hotspot_id: String, action_id: String)
signal card_closed(hotspot_id: String)
signal cafe_pressed

const THEME_PATH: String = "res://UI/cozy_theme.tres"
const MARGIN: float = 16.0
const CARD_W: float = 340.0

var root: Control
var card: PanelContainer
var card_title: Label
var card_body: Label
var card_icon: Control
var card_actions: HBoxContainer
var card_hotspot_id: String = ""
var card_buttons: Dictionary = {}
var hover_panel: PanelContainer
var hover_label: Label
var toast_panel: PanelContainer
var toast_label: Label
var fade: ColorRect
var cafe_button: Button
var day_label: Label
var _toast_tween: Tween
var _card_tween: Tween

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.name = "UIRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th = load(THEME_PATH)
	if th is Theme:
		root.theme = th
	add_child(root)
	_build()

# --- builders ------------------------------------------------------------------------------

func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

func _icon(kind: String, px: float) -> Control:
	var i := AptIcon.new()
	i.kind = kind
	i.custom_minimum_size = Vector2(px, px)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i

func _label(text: String, variation: StringName = &"", size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _chip(kind: String, text: String, size: int) -> Array:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"HUDChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := _hbox(8)
	chip.add_child(h)
	h.add_child(_icon(kind, 26))
	var l := _label(text, &"", size)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return [chip, l]

func _build() -> void:
	# Top-left chips.
	var tl := _hbox(10)
	tl.position = Vector2(MARGIN, MARGIN)
	root.add_child(tl)
	var home: Array = _chip("house", "Home", 22)
	(home[0] as Control).name = "TitleChip"
	tl.add_child(home[0])
	var eve: Array = _chip("moon", "Evening", 18)
	day_label = eve[1]
	tl.add_child(eve[0])

	# Bottom-left hint line.
	var hint := PanelContainer.new()
	hint.name = "HintChip"
	hint.theme_type_variation = &"HUDChip"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hl := _label("Hover things to look around  ·  Click to interact  ·  WASD / middle-drag pan  ·  Wheel zoom  ·  Home overview", &"MutedLabel", 15)
	hl.name = "HintLabel"
	hint.add_child(hl)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = MARGIN
	hint.offset_bottom = -MARGIN
	root.add_child(hint)

	# Bottom-right "Go to Cafe".
	cafe_button = Button.new()
	cafe_button.name = "GoToCafeButton"
	cafe_button.focus_mode = Control.FOCUS_NONE
	cafe_button.custom_minimum_size = Vector2(170, 46)
	cafe_button.tooltip_text = "Open the cafe for the day"
	var bh := _hbox(10)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.set_anchors_preset(Control.PRESET_FULL_RECT)
	bh.add_child(_icon("paw", 22))
	var bl := _label("Go to Cafe", &"", 19)
	bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bl.add_theme_color_override("font_color", Color("4A3426"))
	bh.add_child(bl)
	cafe_button.add_child(bh)
	cafe_button.anchor_left = 1.0
	cafe_button.anchor_right = 1.0
	cafe_button.anchor_top = 1.0
	cafe_button.anchor_bottom = 1.0
	cafe_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cafe_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cafe_button.offset_right = -MARGIN
	cafe_button.offset_bottom = -MARGIN
	cafe_button.offset_left = -MARGIN - 170
	cafe_button.offset_top = -MARGIN - 46
	cafe_button.pressed.connect(func(): cafe_pressed.emit())
	root.add_child(cafe_button)

	# Hover tooltip.
	hover_panel = PanelContainer.new()
	hover_panel.name = "HoverTip"
	hover_panel.theme_type_variation = &"CursorPanel"
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label = _label("", &"CursorLabel")
	hover_panel.add_child(hover_label)
	hover_panel.visible = false
	root.add_child(hover_panel)

	# Prompt card.
	card = PanelContainer.new()
	card.name = "PromptCard"
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var head := _hbox(10)
	card_icon = _icon("paw", 34)
	head.add_child(card_icon)
	card_title = _label("", &"TitleLabel")
	card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(card_title)
	var close := Button.new()
	close.name = "CloseButton"
	close.theme_type_variation = &"CloseButton"
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(30, 30)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): hide_card(true))
	head.add_child(close)
	v.add_child(head)
	var sep := HSeparator.new()
	v.add_child(sep)
	card_body = _label("", &"", 16)
	card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_body.custom_minimum_size = Vector2(CARD_W - 32, 0)
	v.add_child(card_body)
	card_actions = _hbox(8)
	card_actions.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(card_actions)
	card.visible = false
	root.add_child(card)

	# Toast (cream chip, top centre).
	toast_panel = PanelContainer.new()
	toast_panel.name = "Toast"
	toast_panel.theme_type_variation = &"HUDChip"
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := _hbox(8)
	th.add_child(_icon("paw", 22))
	toast_label = _label("", &"", 18)
	toast_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(toast_label)
	toast_panel.add_child(th)
	toast_panel.visible = false
	root.add_child(toast_panel)

	# Fade overlay (nap / scene change).
	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0.1, 0.07, 0.1, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)

# --- API --------------------------------------------------------------------------------------

func set_time_text(text: String) -> void:
	if day_label != null:
		day_label.text = text

func show_hover(text: String, mouse_pos: Vector2) -> void:
	hover_label.text = text
	hover_panel.visible = true
	hover_panel.reset_size()
	var vp: Vector2 = root.get_viewport_rect().size
	var p: Vector2 = mouse_pos + Vector2(18, 14)
	p.x = minf(p.x, vp.x - hover_panel.size.x - 8)
	p.y = minf(p.y, vp.y - hover_panel.size.y - 8)
	hover_panel.position = p

func hide_hover() -> void:
	hover_panel.visible = false

## True when p (viewport coords) is over an interactive HUD element.
func is_over_ui(p: Vector2) -> bool:
	if card.visible and card.get_global_rect().grow(6).has_point(p):
		return true
	return cafe_button.visible and cafe_button.get_global_rect().has_point(p)

func is_card_open() -> bool:
	return card.visible

## actions: [{"id","label"}]; the first one is styled as the primary (bold-ish) button.
func show_card(hotspot_id: String, title: String, body: String, icon: String, actions: Array, screen_pos: Vector2) -> void:
	card_hotspot_id = hotspot_id
	card_title.text = title
	card_body.text = body
	(card_icon as AptIcon).kind = icon
	card_icon.queue_redraw()
	for c in card_actions.get_children():
		card_actions.remove_child(c)
		c.queue_free()
	card_buttons.clear()
	for i in range(actions.size()):
		var a: Dictionary = actions[i]
		var b := Button.new()
		b.name = "Action_%s" % str(a.get("id", ""))
		b.text = str(a.get("label", ""))
		b.focus_mode = Control.FOCUS_NONE
		if i == 0:
			b.add_theme_font_size_override("font_size", 18)
		else:
			b.add_theme_font_size_override("font_size", 16)
			b.add_theme_color_override("font_color", Color("8D6B53"))
		var aid: String = str(a.get("id", ""))
		b.pressed.connect(func(): press_action(aid))
		card_actions.add_child(b)
		card_buttons[aid] = b
	card.visible = true
	card.reset_size()
	var vp: Vector2 = root.get_viewport_rect().size
	var sz: Vector2 = card.get_combined_minimum_size()
	var p: Vector2 = screen_pos + Vector2(40, -sz.y * 0.5)
	if p.x + sz.x > vp.x - MARGIN:
		p.x = screen_pos.x - 40 - sz.x
	p.x = clampf(p.x, MARGIN, vp.x - sz.x - MARGIN)
	p.y = clampf(p.y, 70.0, vp.y - sz.y - 80.0)
	card.position = p
	card.pivot_offset = sz * 0.5
	card.scale = Vector2(0.92, 0.92)
	card.modulate.a = 0.0
	if _card_tween != null:
		_card_tween.kill()
	_card_tween = card.create_tween().set_parallel(true)
	_card_tween.tween_property(card, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_card_tween.tween_property(card, "modulate:a", 1.0, 0.12)

func hide_card(user_closed: bool = false) -> void:
	if not card.visible:
		return
	card.visible = false
	var id: String = card_hotspot_id
	card_hotspot_id = ""
	if user_closed:
		card_closed.emit(id)

## Same as clicking a card button (probes call this).
func press_action(action_id: String) -> void:
	var id: String = card_hotspot_id
	hide_card(false)
	action_pressed.emit(id, action_id)

func toast(text: String, seconds: float = 2.8) -> void:
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.reset_size()
	var vp: Vector2 = root.get_viewport_rect().size
	var sz: Vector2 = toast_panel.get_combined_minimum_size()
	toast_panel.position = Vector2((vp.x - sz.x) * 0.5, MARGIN + 2)
	toast_panel.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = toast_panel.create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func(): toast_panel.visible = false)

## Fades to dusk-dark, calls `mid` at the darkest point, fades back.
func fade_cycle(mid: Callable, hold: float = 0.8) -> void:
	var tw := fade.create_tween()
	tw.tween_property(fade, "color:a", 0.88, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(mid)
	tw.tween_interval(hold)
	tw.tween_property(fade, "color:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)

func fade_out(done: Callable) -> void:
	var tw := fade.create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.45)
	tw.tween_callback(done)


## Small procedural icon set (house, moon, paw, bowl, bed, notebook, heart, hanger, door).
class AptIcon extends Control:
	var kind: String = "paw"

	func _draw() -> void:
		var s: Vector2 = size
		var c: Vector2 = s * 0.5
		var r: float = minf(s.x, s.y) * 0.5
		var ink := Color("4A3426")
		var w: float = maxf(1.5, r * 0.12)
		match kind:
			"house":
				var roof := PackedVector2Array([c + Vector2(-r * 0.92, -r * 0.05), c + Vector2(0, -r * 0.88), c + Vector2(r * 0.92, -r * 0.05)])
				draw_rect(Rect2(c + Vector2(-r * 0.62, -r * 0.15), Vector2(r * 1.24, r * 0.98)), Color("F2C9A0"))
				draw_colored_polygon(roof, Color("C9785D"))
				draw_rect(Rect2(c + Vector2(-r * 0.18, r * 0.3), Vector2(r * 0.36, r * 0.53)), Color("9C6B4A"))
				draw_rect(Rect2(c + Vector2(r * 0.25, r * 0.0), Vector2(r * 0.24, r * 0.22)), Color("FFE2B0"))
			"moon":
				draw_circle(c, r * 0.8, Color("8E86B8"), true, -1.0, true)
				draw_circle(c + Vector2(r * 0.38, -r * 0.3), r * 0.66, Color("FFF6EA"), true, -1.0, true)
			"paw":
				var col := Color("C98A5E")
				draw_circle(c + Vector2(0, r * 0.3), r * 0.42, col, true, -1.0, true)
				draw_circle(c + Vector2(-r * 0.62, -r * 0.12), r * 0.2, col, true, -1.0, true)
				draw_circle(c + Vector2(-r * 0.24, -r * 0.5), r * 0.21, col, true, -1.0, true)
				draw_circle(c + Vector2(r * 0.24, -r * 0.5), r * 0.21, col, true, -1.0, true)
				draw_circle(c + Vector2(r * 0.62, -r * 0.12), r * 0.2, col, true, -1.0, true)
			"bowl":
				var bowl := PackedVector2Array([c + Vector2(-r * 0.9, -r * 0.05), c + Vector2(r * 0.9, -r * 0.05), c + Vector2(r * 0.6, r * 0.6), c + Vector2(-r * 0.6, r * 0.6)])
				for i in range(5):
					draw_circle(c + Vector2(-r * 0.5 + r * 0.25 * float(i), -r * 0.12 - r * 0.12 * float(i % 2)), r * 0.17, Color("9A6A44"), true, -1.0, true)
				draw_colored_polygon(bowl, Color("6E8F8A"))
				draw_line(c + Vector2(-r * 0.9, -r * 0.05), c + Vector2(r * 0.9, -r * 0.05), Color("8FB0AA"), w)
			"bed":
				draw_rect(Rect2(c + Vector2(-r * 0.9, -r * 0.55), Vector2(r * 0.2, r * 1.3)), Color("9C6B4A"))
				draw_rect(Rect2(c + Vector2(-r * 0.7, r * 0.05), Vector2(r * 1.6, r * 0.4)), Color("D9A0A0"))
				draw_rect(Rect2(c + Vector2(-r * 0.65, -r * 0.2), Vector2(r * 0.5, r * 0.28)), Color("FFF6EA"))
				draw_rect(Rect2(c + Vector2(-r * 0.9, r * 0.45), Vector2(r * 1.8, r * 0.15)), Color("9C6B4A"))
				draw_string(get_theme_default_font(), c + Vector2(r * 0.15, -r * 0.25), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 0.9), Color("8E86B8"))
			"notebook":
				draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.85), Vector2(r * 1.4, r * 1.7)), Color("C47A5A"))
				draw_rect(Rect2(c + Vector2(-r * 0.5, -r * 0.75), Vector2(r * 1.1, r * 1.5)), Color("FFF8EC"))
				for i in range(4):
					draw_line(c + Vector2(-r * 0.35, -r * 0.4 + r * 0.3 * float(i)), c + Vector2(r * 0.45, -r * 0.4 + r * 0.3 * float(i)), Color("C9B49A"), w * 0.8)
				draw_line(c + Vector2(r * 0.3, r * 0.8), c + Vector2(r * 0.85, r * 0.15), Color("F2C14E"), w * 1.6)
			"heart":
				var col := Color("E07A82")
				var pts := PackedVector2Array()
				for i in range(48):
					var t: float = TAU * float(i) / 48.0
					var x: float = 16.0 * pow(sin(t), 3)
					var y: float = -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
					pts.append(c + Vector2(x, y + 1.5) * (r / 17.5))
				draw_colored_polygon(pts, col)
				draw_circle(c + Vector2(-r * 0.38, -r * 0.3), r * 0.15, Color(1, 1, 1, 0.6), true, -1.0, true)
			"hanger":
				draw_arc(c + Vector2(0, -r * 0.55), r * 0.2, PI, TAU * 1.1, 12, ink, w, true)
				draw_line(c + Vector2(0, -r * 0.35), c + Vector2(-r * 0.9, r * 0.4), ink, w, true)
				draw_line(c + Vector2(0, -r * 0.35), c + Vector2(r * 0.9, r * 0.4), ink, w, true)
				draw_line(c + Vector2(-r * 0.9, r * 0.4), c + Vector2(r * 0.9, r * 0.4), ink, w, true)
				draw_rect(Rect2(c + Vector2(-r * 0.5, r * 0.45), Vector2(r * 1.0, r * 0.4)), Color("E0A84E"))
			"door":
				draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.9), Vector2(r * 1.2, r * 1.8)), Color("B5654A"))
				draw_rect(Rect2(c + Vector2(-r * 0.4, -r * 0.7), Vector2(r * 0.8, r * 0.45)), Color("FFE2B0"))
				draw_circle(c + Vector2(r * 0.35, r * 0.15), r * 0.1, Color("D9B36A"), true, -1.0, true)
			_:
				draw_circle(c, r * 0.6, ink, true, -1.0, true)
