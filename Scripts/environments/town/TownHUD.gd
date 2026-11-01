extends CanvasLayer

## Minimal Town HUD (res://UI/cozy_theme.tres): a "Town" chip with the time of day, a
## controls hint, a hotspot prompt card with Go / Not now buttons, and a toast.
## Signals go back to Town.gd, which owns all hotspot behaviour.

signal go_pressed(hotspot_id: StringName)
signal card_closed(hotspot_id: StringName)

const THEME_PATH := "res://UI/cozy_theme.tres"

var root: Control
var chip_time: Label
var card: PanelContainer
var card_title: Label
var card_sub: Label
var card_desc: Label
var card_tags: HBoxContainer
var card_go: Button
var card_close: Button
var card_icon: Control
var toast: PanelContainer
var toast_label: Label
var hint: PanelContainer

var current_id: StringName = &""
var _toast_t: float = 0.0
var _card_tween: Tween

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(THEME_PATH):
		root.theme = load(THEME_PATH)
	add_child(root)
	_build_chip()
	_build_hint()
	_build_card()
	_build_toast()

func _build_chip() -> void:
	var chip := PanelContainer.new()
	chip.name = "TownChip"
	chip.theme_type_variation = &"HUDChip"
	chip.position = Vector2(16, 14)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chip)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	chip.add_child(hb)
	var icon := TownIcon.new()
	icon.kind = "house"
	icon.custom_minimum_size = Vector2(24, 24)
	hb.add_child(icon)
	var l := Label.new()
	l.text = "Town"
	hb.add_child(l)
	chip_time = Label.new()
	chip_time.theme_type_variation = &"MutedLabel"
	chip_time.text = "· Autumn evening"
	hb.add_child(chip_time)

func _build_hint() -> void:
	hint = PanelContainer.new()
	hint.name = "Hint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(hint)
	var sb = hint.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var s2: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
		s2.bg_color.a = 0.8
		s2.shadow_size = 0
		hint.add_theme_stylebox_override("panel", s2)
	var l := Label.new()
	l.theme_type_variation = &"MutedLabel"
	l.text = "Click a glowing spot to see what's there\nWASD / middle-drag pan  ·  Wheel zoom  ·  Home overview  ·  T time of day"
	hint.add_child(l)

func _build_card() -> void:
	card = PanelContainer.new()
	card.name = "HotspotCard"
	card.custom_minimum_size = Vector2(400, 0)
	card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_left = -200
	card.offset_right = 200
	card.offset_bottom = -28
	card.visible = false
	root.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	card_icon = TownIcon.new()
	card_icon.custom_minimum_size = Vector2(44, 44)
	top.add_child(card_icon)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	top.add_child(tv)
	card_title = Label.new()
	card_title.theme_type_variation = &"TitleLabel"
	tv.add_child(card_title)
	card_sub = Label.new()
	card_sub.theme_type_variation = &"MutedLabel"
	tv.add_child(card_sub)
	card_close = Button.new()
	card_close.theme_type_variation = &"CloseButton"
	card_close.text = "x"
	card_close.focus_mode = Control.FOCUS_NONE
	card_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card_close.pressed.connect(close_card)
	top.add_child(card_close)
	card_desc = Label.new()
	card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_desc.custom_minimum_size = Vector2(372, 0)
	card_desc.add_theme_font_size_override("font_size", 16)
	vb.add_child(card_desc)
	card_tags = HBoxContainer.new()
	card_tags.add_theme_constant_override("separation", 6)
	vb.add_child(card_tags)
	vb.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var later := Button.new()
	later.text = "Not now"
	later.focus_mode = Control.FOCUS_NONE
	later.pressed.connect(close_card)
	row.add_child(later)
	card_go = Button.new()
	card_go.text = "Go"
	card_go.focus_mode = Control.FOCUS_NONE
	card_go.custom_minimum_size = Vector2(120, 0)
	card_go.pressed.connect(_on_go)
	row.add_child(card_go)

func _build_toast() -> void:
	toast = PanelContainer.new()
	toast.name = "Toast"
	toast.theme_type_variation = &"ToastPanel"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.offset_top = 70
	toast.visible = false
	root.add_child(toast)
	toast_label = Label.new()
	toast_label.theme_type_variation = &"ToastLabel"
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(toast_label)

## def: id, title, subtitle, desc, verb, tags (Array[String]), icon
func show_card(def: Dictionary) -> void:
	current_id = StringName(def.get("id", ""))
	card_title.text = String(def.get("title", ""))
	card_sub.text = String(def.get("subtitle", ""))
	card_desc.text = String(def.get("desc", ""))
	card_go.text = String(def.get("verb", "Go"))
	(card_icon as TownIcon).kind = String(def.get("icon", "paw"))
	card_icon.queue_redraw()
	for c in card_tags.get_children():
		c.queue_free()
	for t in def.get("tags", []):
		var tp := PanelContainer.new()
		tp.theme_type_variation = &"TagPanel"
		var tl := Label.new()
		tl.theme_type_variation = &"TagLabel"
		tl.text = String(t)
		tp.add_child(tl)
		card_tags.add_child(tp)
	card.visible = true
	card.modulate.a = 0.0
	if _card_tween != null:
		_card_tween.kill()
	_card_tween = create_tween()
	_card_tween.tween_property(card, "modulate:a", 1.0, 0.15)

func is_card_open() -> bool:
	return card != null and card.visible

func close_card() -> void:
	if not card.visible:
		return
	card.visible = false
	var id: StringName = current_id
	current_id = &""
	card_closed.emit(id)

func _on_go() -> void:
	var id: StringName = current_id
	card.visible = false
	current_id = &""
	go_pressed.emit(id)

func show_toast(text: String, sec: float = 2.6) -> void:
	toast_label.text = text
	toast.visible = true
	toast.modulate.a = 1.0
	_toast_t = sec
	# Re-centre after the label resizes.
	toast.reset_size()
	toast.offset_left = -toast.get_combined_minimum_size().x * 0.5
	toast.offset_right = toast.get_combined_minimum_size().x * 0.5

func toast_text() -> String:
	return toast_label.text if toast != null and toast.visible else ""

func set_time_label(text: String) -> void:
	if chip_time != null:
		chip_time.text = "· " + text

## True when the mouse is over an interactive HUD panel (card).
func is_mouse_over_ui() -> bool:
	if card != null and card.visible:
		return card.get_global_rect().has_point(card.get_global_mouse_position())
	return false

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t < 0.4:
			toast.modulate.a = maxf(0.0, _toast_t / 0.4)
		if _toast_t <= 0.0:
			toast.visible = false


## Tiny vector icons for the chip and the card (no image files).
class TownIcon extends Control:
	var kind: String = "paw"
	const C_BG := Color("F2C14E")
	const C_FG := Color("4A3426")

	func _draw() -> void:
		var s: Vector2 = size
		var c: Vector2 = s * 0.5
		var r: float = minf(s.x, s.y) * 0.5
		draw_circle(c, r, Color("C9A27A"))
		draw_circle(c, r - 2.0, C_BG)
		var u: float = r * 0.62
		match kind:
			"house":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-u, -0.05 * u), c + Vector2(0, -u), c + Vector2(u, -0.05 * u)]), C_FG)
				draw_rect(Rect2(c + Vector2(-u * 0.7, -0.1 * u), Vector2(u * 1.4, u * 0.95)), C_FG)
				draw_rect(Rect2(c + Vector2(-u * 0.18, u * 0.3), Vector2(u * 0.36, u * 0.55)), C_BG)
			"cat":
				draw_circle(c + Vector2(0, u * 0.15), u * 0.75, C_FG)
				for sx in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([c + Vector2(sx * u * 0.75, -u * 0.05), c + Vector2(sx * u * 0.7, -u * 0.95), c + Vector2(sx * u * 0.15, -u * 0.5)]), C_FG)
					draw_circle(c + Vector2(sx * u * 0.3, u * 0.05), u * 0.12, C_BG)
			"bone":
				draw_rect(Rect2(c + Vector2(-u * 0.6, -u * 0.15), Vector2(u * 1.2, u * 0.3)), C_FG)
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						draw_circle(c + Vector2(sx * u * 0.65, sy * u * 0.2), u * 0.22, C_FG)
			"tree":
				draw_rect(Rect2(c + Vector2(-u * 0.12, u * 0.2), Vector2(u * 0.24, u * 0.7)), C_FG)
				draw_circle(c + Vector2(0, -u * 0.15), u * 0.6, Color("C9643A"))
			"bread":
				draw_circle(c + Vector2(0, u * 0.05), u * 0.8, Color("C98A4B"))
				draw_rect(Rect2(c + Vector2(-u * 0.8, u * 0.05), Vector2(u * 1.6, u * 0.6)), Color("C98A4B"))
				for i in range(3):
					draw_line(c + Vector2(-u * 0.45 + float(i) * u * 0.45, -u * 0.3), c + Vector2(-u * 0.25 + float(i) * u * 0.45, u * 0.2), C_FG, 2.0)
			"box":
				draw_rect(Rect2(c + Vector2(-u * 0.75, -u * 0.2), Vector2(u * 1.5, u * 0.95)), Color("A7805A"))
				draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.75, -u * 0.2), c + Vector2(-u * 0.35, -u * 0.75), c + Vector2(0, -u * 0.2)]), Color("C9A27A"))
				draw_circle(c + Vector2(u * 0.3, -u * 0.35), u * 0.3, C_FG)
			"search":
				draw_arc(c + Vector2(-u * 0.15, -u * 0.15), u * 0.5, 0.0, TAU, 20, C_FG, 3.0)
				draw_line(c + Vector2(u * 0.22, u * 0.22), c + Vector2(u * 0.75, u * 0.75), C_FG, 4.0)
			_:
				draw_circle(c + Vector2(0, u * 0.25), u * 0.45, C_FG)
				for i in range(4):
					var a: float = deg_to_rad(-60.0 + 40.0 * float(i))
					draw_circle(c + Vector2(sin(a) * u * 0.7, -cos(a) * u * 0.55 - u * 0.05), u * 0.18, C_FG)
