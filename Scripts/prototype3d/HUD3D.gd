extends CanvasLayer

## Cozy HUD for MainLevel3D (B13): top status chips (money, reputation, cats on floor,
## day + clock), cat-drought toast, Build button + upward build panel (bottom-left), placing
## hint bar, cat inspector card and decor inspector card (right side), controls help,
## F7 debug panel for cat rendering (top-left under the chips).
## Reads the level through its run-state fields/signals and DecorPlacement3D's signals.

const UPDATE_INTERVAL_SEC: float = 0.25
const OPEN_HOUR: float = 8.0
const CLOSE_HOUR: float = 20.0
const MARGIN: float = 16.0
const CARD_WIDTH: float = 340.0
const REFUND_RATIO: float = 0.5
const HELP_FULL_SEC: float = 20.0
const HELP_MIN_SEC: float = 3.0
const HELP_REST_ALPHA: float = 0.7
const BUILD_ROW_H: float = 60.0
const BUILD_ROW_SEP: float = 6.0
const THUMB_PX: int = 96
const DEBUG_WIDTH: float = 290.0
const CatPixelFaceScript := preload("res://Scripts/prototype3d/CatPixelFace.gd")

const COL_TEXT := Color("#4A3426")
const COL_MUTED := Color("#8D6E57")
const COL_GOOD := Color("#5E8C61")
const COL_BAD := Color("#C0563A")
const COL_TRUST := Color("#8FBF9F")
const COL_LOW := Color("#8FBF9F")
const COL_MID := Color("#E8B04B")
const COL_HIGH := Color("#E07A3F")
const COL_BORDER := Color("#C9A27A")

const CAT_STATE_TEXT: Dictionary = {
	"idle": "Lounging around",
	"wander": "Exploring the cafe",
	"interacting": "Visiting with patrons",
	"retreating": "Overwhelmed - heading for a nap",
	"rest": "Napping in the Cat Nap Zone",
	"returning": "Rested - coming back out",
}
const TRUST_TEXT: Dictionary = {
	"fearful": "Fearful",
	"warming": "Warming up",
	"bonded": "Bonded",
	"adoptable": "Adoptable",
}
const TRUST_COLORS: Dictionary = {
	"fearful": Color("#B9A6C9"),
	"warming": Color("#E8C27A"),
	"bonded": Color("#8FBF9F"),
	"adoptable": Color("#E79AA0"),
}
const RARITY_COLORS: Dictionary = {
	"common": Color("#EFE3CF"),
	"uncommon": Color("#CFE3D2"),
	"rare": Color("#E8D3F0"),
}

var level: Node = null
var placement: Node = null

var _tick: float = 0.0
var _last_money: int = -1
var _selected_cat: Node3D = null
var _inspected_cell: Vector2i = Vector2i(-9999, -9999)
var _inspected_info: Dictionary = {}
var _selection_ring: MeshInstance3D
var _ring_t: float = 0.0
var _toast_tween: Tween
var _build_rows: Dictionary = {}

@onready var ui_root: Control = $Root

var _money_label: Label
var _money_chip: PanelContainer
var _rep_label: Label
var _cats_label: Label
var _day_label: Label
var _clock_label: Label
var _day_bar: ProgressBar
var _day_icon: HudIcon
var _toast: PanelContainer
var _toast_label: Label
var _build_button: Button
var _build_panel: PanelContainer
var _build_scroll: ScrollContainer
var _build_list: VBoxContainer
var _build_money_label: Label
var _hold_bar: PanelContainer
var _hold_swatch: Panel
var _hold_label: Label
var _cat_card: PanelContainer
var _cat_name: Label
var _cat_rarity: PanelContainer
var _cat_rarity_label: Label
var _cat_state: Label
var _trust_bar: ProgressBar
var _trust_fill: StyleBoxFlat
var _trust_value: Label
var _trust_tag: PanelContainer
var _trust_tag_label: Label
var _overstim_bar: ProgressBar
var _overstim_fill: StyleBoxFlat
var _overstim_value: Label
var _traits_flow: HFlowContainer
var _ready_panel: PanelContainer
var _decor_card: PanelContainer
var _decor_name: Label
var _decor_meta: Label
var _decor_effects: VBoxContainer
var _decor_footer: Label
var _decor_remove: Button
var _decor_viewport: SubViewport
var _decor_preview_root: Node3D
var _decor_cam: Camera3D
var _help: PanelContainer
var _day_end_saved: bool = false
var _help_chip: Button
var _help_expanded: bool = true
var _help_age: float = 0.0
var _help_user_toggled: bool = false
var _adopt_button: Button
var _build_fade: TextureRect
var _thumb_cache: Dictionary = {}
var _thumb_vp: SubViewport
var _thumb_root: Node3D
var _thumb_cam: Camera3D
var _thumbs_started: bool = false
var _debug_panel: PanelContainer
var _dbg_pixel: Button
var _dbg_smooth: Button
var _dbg_density: OptionButton
var _dbg_rig_proc: Button
var _dbg_rig_fallback: Button
var _dbg_eye: OptionButton
var _dbg_expr: OptionButton
var _dbg_syncing: bool = false

func _ready() -> void:
	level = get_parent()
	_build_ui()
	call_deferred("_late_init")

func _late_init() -> void:
	if level == null:
		return
	placement = level.get_node_or_null("DecorPlacement3D")
	if placement != null:
		_connect_if(placement, "hold_changed", _on_hold_changed)
		_connect_if(placement, "cat_clicked", _on_cat_clicked)
		_connect_if(placement, "decor_clicked", _on_decor_clicked)
		_connect_if(placement, "empty_clicked", _on_empty_clicked)
	_connect_if(level, "economy_changed", _on_economy_changed)
	_connect_if(level, "cat_drought_changed", _on_cat_drought_changed)
	_connect_if(level, "day_changed", _on_day_changed)
	_connect_if(level, "run_saved", _on_run_saved)
	_connect_if(level, "decor_changed", _on_decor_changed)
	_connect_if(level, "cat_trust_changed", _on_cat_trust_changed)
	_connect_if(level, "cat_adopted", _on_cat_adopted)
	_connect_if(level, "debug_settings_changed", _sync_debug_panel)
	_create_selection_ring()
	_rebuild_build_list()
	_refresh_all()
	var drought = level.get("cat_drought")
	_on_cat_drought_changed(bool(drought) if drought is bool else false)

func _connect_if(obj: Object, sig: String, cb: Callable) -> void:
	if obj != null and obj.has_signal(sig) and not obj.is_connected(sig, cb):
		obj.connect(sig, cb)

func _process(delta: float) -> void:
	if level == null:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = UPDATE_INTERVAL_SEC
		_refresh_all()
	_update_selection_ring(delta)
	_update_help(delta)

## V3: the controls panel collapses to a small chip after the first input or HELP_FULL_SEC.
func _input(event: InputEvent) -> void:
	if not _help_expanded or _help_user_toggled or _help_age < HELP_MIN_SEC:
		return
	var pressed: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode != KEY_F1)
	if pressed:
		_set_help_expanded(false)

func _update_help(delta: float) -> void:
	_help_age += delta
	if _help_expanded and not _help_user_toggled and _help_age >= HELP_FULL_SEC:
		_set_help_expanded(false)

func _set_help_expanded(on: bool) -> void:
	_help_expanded = on
	_apply_help_visibility()

func _apply_help_visibility() -> void:
	if _help == null:
		return
	var holding: bool = _hold_bar != null and _hold_bar.visible
	_help.visible = _help_expanded and not holding
	_help_chip.visible = not _help_expanded and not holding

func _toggle_help() -> void:
	_help_user_toggled = true
	_set_help_expanded(not _help_expanded)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_B:
		_toggle_build_panel()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_F1:
		_toggle_help()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_F7:
		toggle_debug_panel()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ESCAPE:
		var any_open: bool = _build_panel.visible or _cat_card.visible or _decor_card.visible or _debug_panel.visible
		_close_cards()
		_build_panel.visible = false
		_debug_panel.visible = false
		if any_open:
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- public

func is_build_panel_open() -> bool:
	return _build_panel != null and _build_panel.visible

## Short informational toast (used by the level for F6 / F9 / save feedback).
func show_notice(text: String, seconds: float = 2.5) -> void:
	if _toast == null:
		return
	if _toast.visible and _toast.get_meta("sticky", false):
		return
	_show_toast(text, COL_GOOD, maxf(0.5, seconds))

func _on_run_saved(ok: bool, reason: String) -> void:
	if reason == "day_end":
		_day_end_saved = ok
	if not ok and reason != "close":
		show_notice("Could not save the cafe - check the log", 3.0)

# ---------------------------------------------------------------- level helpers

func _lget(prop: String, fallback):
	if level == null:
		return fallback
	var v = level.get(prop)
	return fallback if v == null else v

func _cats() -> Array:
	if level != null and level.has_method("get_cat_nodes"):
		return level.get_cat_nodes()
	return []

# ---------------------------------------------------------------- refresh

func _refresh_all() -> void:
	var money: int = int(_lget("money", 0))
	_money_label.text = "$%d" % money
	if _last_money >= 0 and money > _last_money:
		_flash_chip(_money_chip, Color(0.82, 1.0, 0.82))
	elif _last_money >= 0 and money < _last_money:
		_flash_chip(_money_chip, Color(1.0, 0.86, 0.8))
	_last_money = money
	_rep_label.text = "%d rep" % int(_lget("reputation", 0))
	var cats: Array = _cats()
	var on_floor: int = int(level.get_cats_on_floor_count()) if level.has_method("get_cats_on_floor_count") else cats.size()
	_cats_label.text = "Cats on floor %d/%d" % [on_floor, cats.size()]
	_cats_label.add_theme_color_override("font_color", COL_BAD if (on_floor == 0 and cats.size() > 0) else COL_TEXT)
	var day: int = int(_lget("day", 1))
	var t: float = float(_lget("day_time_sec", 0.0)) / maxf(1.0, float(_lget("day_length_sec", 180.0)))
	t = clampf(t, 0.0, 1.0)
	_day_label.text = "Day %d" % day
	_clock_label.text = _format_clock(t)
	_day_bar.value = t * 100.0
	var evening: bool = t > 0.75
	if _day_icon.kind != ("moon" if evening else "sun"):
		_day_icon.kind = "moon" if evening else "sun"
		_day_icon.queue_redraw()
	_refresh_build_affordability(money)
	if _cat_card.visible:
		_refresh_cat_card()
	_place_toast()

## Keep the toast clear of the right-side cards on narrow windows: centre it in the
## space left of the card instead of the full width.
func _place_toast() -> void:
	if _toast == null:
		return
	var vw: float = get_viewport().get_visible_rect().size.x
	var card_open: bool = (_cat_card != null and _cat_card.visible) or (_decor_card != null and _decor_card.visible)
	var shift: float = 0.0
	if card_open and vw < 1500.0:
		shift = -(CARD_WIDTH + MARGIN * 2.0) * 0.5
	_toast.offset_left = shift
	_toast.offset_right = shift
	# V4: the placing hint bar sits top-centre; push the toast below it while it shows.
	var y: float = 84.0
	if _hold_bar != null and _hold_bar.visible:
		y = _hold_bar.offset_top + maxf(_hold_bar.size.y, 66.0) + 10.0
	_toast.offset_top = y
	_toast.offset_bottom = y

func _format_clock(t: float) -> String:
	var hours: float = OPEN_HOUR + (CLOSE_HOUR - OPEN_HOUR) * t
	var h: int = int(floor(hours))
	var m: int = int(floor((hours - float(h)) * 60.0 / 10.0)) * 10
	var suffix: String = "AM" if h < 12 else "PM"
	var h12: int = h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, suffix]

func _flash_chip(chip: Control, c: Color) -> void:
	if chip == null:
		return
	chip.self_modulate = c
	var tw := create_tween()
	tw.tween_property(chip, "self_modulate", Color.WHITE, 0.6)

# ---------------------------------------------------------------- signals

func _on_economy_changed(_money: int, _rep: int) -> void:
	_refresh_all()

func _on_day_changed(_day: int) -> void:
	_refresh_all()
	var suffix: String = "  ·  progress saved" if _day_end_saved else ""
	_day_end_saved = false
	_show_toast("Day %d begins - the cafe is open!%s" % [_day, suffix], COL_GOOD, 3.0)
	# CR-7: the day toast replaces a sticky drought warning; bring it back afterwards.
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.tween_callback(func():
			if bool(_lget("cat_drought", false)):
				_on_cat_drought_changed(true))

## CR-10: cheer trust milestones (warming / bonded / ready).
func _on_cat_trust_changed(cat, old_id: StringName, new_id: StringName) -> void:
	if cat == null or not is_instance_valid(cat):
		return
	var order: Array[StringName] = [&"fearful", &"warming", &"bonded", &"adoptable"]
	if order.find(new_id) <= order.find(old_id):
		return
	var name_s: String = str(cat.get("display_name"))
	match new_id:
		&"warming":
			show_notice("%s is warming up to people" % name_s, 3.0)
		&"bonded":
			show_notice("%s has bonded with the cafe" % name_s, 3.0)
		&"adoptable":
			show_notice("%s is ready for adoption! Click them to find a home" % name_s, 4.0)

func _on_cat_adopted(cat_name: String, gain: int) -> void:
	show_notice("%s went home with a loving family!  +%d rep  ·  a new rescue arrived" % [cat_name, gain], 4.0)

func _on_decor_changed(_id: String, _anchor: Vector2i, placed: bool) -> void:
	if not placed and _decor_card.visible and level.has_method("get_decor_inspection_data"):
		if (level.get_decor_inspection_data(_inspected_cell) as Dictionary).is_empty():
			_close_cards()

func _on_cat_drought_changed(active: bool) -> void:
	if active:
		_show_toast("Cat drought! Every cat is resting - give them a quiet moment.", COL_HIGH, 0.0)
	elif _toast.visible and _toast.get_meta("sticky", false):
		_hide_toast()

func _on_hold_changed(decor_id: String) -> void:
	if decor_id.is_empty():
		_hold_bar.visible = false
		_apply_help_visibility()
		_place_toast()
		return
	var name_s: String = _decor_name_of(decor_id)
	var cost: int = int(level.get_decor_cost(decor_id)) if level.has_method("get_decor_cost") else 0
	_hold_label.text = "Placing %s  ·  $%d" % [name_s, cost]
	_set_swatch(_hold_swatch, _decor_tint_of(decor_id))
	_hold_bar.visible = true
	_apply_help_visibility()
	_build_panel.visible = false
	_place_toast()

func _on_cat_clicked(cat) -> void:
	if cat == null or not is_instance_valid(cat):
		return
	_selected_cat = cat
	_decor_card.visible = false
	_cat_card.visible = true
	_refresh_cat_card()

func _on_decor_clicked(cell: Vector2i, info: Dictionary) -> void:
	_selected_cat = null
	_cat_card.visible = false
	_inspected_cell = cell
	_inspected_info = info
	_fill_decor_card(info)
	_decor_card.visible = true

func _on_empty_clicked() -> void:
	_close_cards()
	_build_panel.visible = false

func _close_cards() -> void:
	_selected_cat = null
	_cat_card.visible = false
	_decor_card.visible = false
	_inspected_cell = Vector2i(-9999, -9999)

# ---------------------------------------------------------------- toast

func _show_toast(text: String, color: Color, seconds: float) -> void:
	_toast_label.text = text
	var sb := _toast.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if sb != null:
		sb.bg_color = Color(color, 0.97)
		sb.border_color = color.darkened(0.3)
		_toast.add_theme_stylebox_override("panel", sb)
	_toast.set_meta("sticky", seconds <= 0.0)
	_toast.visible = true
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.25)
	if seconds > 0.0:
		_toast_tween.tween_interval(seconds)
		_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
		_toast_tween.tween_callback(func(): _toast.visible = false)

func _hide_toast() -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(func(): _toast.visible = false)

# ---------------------------------------------------------------- build panel

func _toggle_build_panel() -> void:
	if _build_panel.visible:
		_build_panel.visible = false
		return
	_close_cards()
	# The debug panel shares the left column; never stack the two.
	_debug_panel.visible = false
	_rebuild_build_list()
	_fit_build_scroll()
	_build_panel.visible = true

func _fit_build_scroll() -> void:
	var vh: float = ui_root.get_viewport_rect().size.y
	var pitch: float = BUILD_ROW_H + BUILD_ROW_SEP
	var wanted: float = float(_build_list.get_child_count()) * pitch
	# V10: whole rows only, so no row is cut through its text.
	var rows: float = maxf(2.0, floor(clampf(minf(wanted, vh - 260.0), 160.0, 470.0) / pitch))
	_build_scroll.custom_minimum_size = Vector2(0, rows * pitch - BUILD_ROW_SEP)
	_update_build_fade()

func _update_build_fade() -> void:
	if _build_fade == null or _build_scroll == null:
		return
	var sb: VScrollBar = _build_scroll.get_v_scroll_bar()
	var more: bool = sb != null and sb.value < sb.max_value - sb.page - 1.0
	_build_fade.visible = more

func _decor_name_of(id: String) -> String:
	if level != null and level.has_method("get_decor_display_name"):
		return String(level.get_decor_display_name(id))
	return id.capitalize()

func _decor_tint_of(id: String) -> Color:
	if level != null and level.has_method("get_decor_tint"):
		return level.get_decor_tint(id)
	return COL_BORDER

func _decor_category_of(id: String) -> String:
	var ui_map = _lget("decor_ui_by_id", {})
	if ui_map is Dictionary:
		var ui: Dictionary = (ui_map as Dictionary).get(id, {})
		if ui.has("category_label"):
			return String(ui["category_label"])
	var data_map = _lget("decor_data_by_id", {})
	if data_map is Dictionary:
		return String((data_map as Dictionary).get(id, {}).get("category", "")).capitalize()
	return ""

func _rebuild_build_list() -> void:
	if _build_list == null or level == null or not level.has_method("get_available_decor_ids"):
		return
	for child in _build_list.get_children():
		child.queue_free()
	_build_rows.clear()
	var ids: Array = level.get_available_decor_ids()
	for i in range(ids.size()):
		var id: String = String(ids[i])
		_build_list.add_child(_make_build_row(id, i))
	_refresh_build_affordability(int(_lget("money", 0)))
	if not _thumbs_started:
		_thumbs_started = true
		_render_thumbnails.call_deferred(ids.duplicate())

## V9: renders each decor once through a small SubViewport and caches the image.
func _render_thumbnails(ids: Array) -> void:
	if DisplayServer.get_name() == "headless" or _thumb_vp == null:
		return
	for raw_id in ids:
		var id: String = String(raw_id)
		var scene_path: String = ""
		var scale_v: Vector3 = Vector3.ONE
		var mesh_map = _lget("decor_mesh_by_id", {})
		if mesh_map is Dictionary:
			scene_path = String((mesh_map as Dictionary).get(id, {}).get("mesh_scene", ""))
		if level.has_method("get_decor_scale"):
			scale_v = level.get_decor_scale(id)
		if not _stage_preview(scene_path, scale_v, _thumb_root, _thumb_cam, _thumb_vp, 1.08):
			continue
		_thumb_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return
		var img: Image = _thumb_vp.get_texture().get_image()
		if img == null or img.is_empty():
			continue
		var tex := ImageTexture.create_from_image(img)
		_thumb_cache[id] = tex
		var rec: Dictionary = _build_rows.get(id, {})
		var tr = rec.get("thumb", null)
		if tr is TextureRect and is_instance_valid(tr):
			(tr as TextureRect).texture = tex
	for child in _thumb_root.get_children():
		child.queue_free()

func _make_build_row(id: String, index: int) -> Button:
	var btn := Button.new()
	btn.theme_type_variation = &"BuildRow"
	btn.custom_minimum_size = Vector2(0, BUILD_ROW_H)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_build_item_pressed.bind(id))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -12
	row.add_theme_constant_override("separation", 10)
	btn.add_child(row)
	# V9: a rendered thumbnail of the decor; the tint swatch is the fallback.
	var sw := Panel.new()
	sw.custom_minimum_size = Vector2(44, 44)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_set_swatch(sw, _decor_tint_of(id).lightened(0.35))
	row.add_child(sw)
	var thumb := TextureRect.new()
	thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture = _thumb_cache.get(id, null)
	sw.add_child(thumb)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -2)
	row.add_child(col)
	var name_l := Label.new()
	name_l.text = _decor_name_of(id)
	name_l.add_theme_font_size_override("font_size", 17)
	col.add_child(name_l)
	var cat_l := Label.new()
	cat_l.theme_type_variation = &"MutedLabel"
	cat_l.text = _decor_category_of(id) + ("   ·   key %d" % (index + 1) if index < 9 else "")
	cat_l.add_theme_font_size_override("font_size", 13)
	col.add_child(cat_l)
	var cost_l := Label.new()
	var cost: int = int(level.get_decor_cost(id)) if level.has_method("get_decor_cost") else 0
	cost_l.text = "$%d" % cost
	cost_l.add_theme_font_size_override("font_size", 18)
	cost_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cost_l)
	_ignore_mouse(row)
	_build_rows[id] = {"button": btn, "cost_label": cost_l, "cost": cost, "thumb": thumb}
	return btn

func _refresh_build_affordability(money: int) -> void:
	if _build_money_label != null:
		_build_money_label.text = "You have $%d" % money
	for id in _build_rows.keys():
		var rec: Dictionary = _build_rows[id]
		var btn: Button = rec["button"]
		if not is_instance_valid(btn):
			continue
		var affordable: bool = money >= int(rec["cost"])
		btn.disabled = not affordable
		btn.tooltip_text = "" if affordable else "Need $%d more" % (int(rec["cost"]) - money)
		(rec["cost_label"] as Label).add_theme_color_override("font_color", COL_GOOD if affordable else COL_BAD)
		btn.modulate.a = 1.0 if affordable else 0.7

func _on_build_item_pressed(id: String) -> void:
	_build_panel.visible = false
	if placement != null and placement.has_method("begin_hold"):
		placement.call("begin_hold", id)

func _on_cancel_hold_pressed() -> void:
	if placement != null and placement.has_method("cancel_hold"):
		placement.call("cancel_hold")

# ---------------------------------------------------------------- cat card

func _refresh_cat_card() -> void:
	if _selected_cat == null or not is_instance_valid(_selected_cat) or _selected_cat.is_queued_for_deletion():
		_close_cards()
		return
	var info: Dictionary = {}
	if _selected_cat.has_method("get_hud_info"):
		var v = _selected_cat.call("get_hud_info")
		info = v if v is Dictionary else {}
	var name_s: String = String(info.get("name", _selected_cat.get("display_name") if _selected_cat.get("display_name") != null else "Cat"))
	_cat_name.text = name_s if not name_s.is_empty() else "Cat"
	var rarity: String = String(info.get("rarity", "common"))
	_cat_rarity_label.text = rarity.capitalize()
	_set_tag_color(_cat_rarity, RARITY_COLORS.get(rarity, RARITY_COLORS["common"]))
	var state_s: String = String(info.get("state", str(_selected_cat.get("state"))))
	_cat_state.text = CAT_STATE_TEXT.get(state_s, state_s.capitalize())
	var trust: float = float(info.get("trust", 0.0))
	var trust_max: float = maxf(1.0, float(info.get("trust_max", 100.0)))
	_trust_bar.max_value = trust_max
	_trust_bar.value = trust
	_trust_value.text = "%d / %d" % [int(round(trust)), int(trust_max)]
	var ts: String = String(info.get("trust_state", "fearful"))
	_trust_tag_label.text = TRUST_TEXT.get(ts, ts.capitalize())
	var tcol: Color = TRUST_COLORS.get(ts, COL_TRUST)
	_set_tag_color(_trust_tag, tcol.lightened(0.45))
	_trust_fill.bg_color = tcol
	var o: float = float(info.get("overstim", 0.0))
	var omax: float = maxf(1.0, float(info.get("overstim_max", 100.0)))
	_overstim_bar.max_value = omax
	_overstim_bar.value = o
	_overstim_value.text = "%d / %d" % [int(round(o)), int(omax)]
	var r: float = clampf(o / omax, 0.0, 1.0)
	_overstim_fill.bg_color = COL_LOW.lerp(COL_MID, r / 0.5) if r < 0.5 else COL_MID.lerp(COL_HIGH, (r - 0.5) / 0.5)
	var traits: Array = info.get("traits", []) if info.get("traits", []) is Array else []
	var key: String = ",".join(PackedStringArray(traits.map(func(x): return str(x))))
	if _traits_flow.get_meta("key", "~") != key:
		_traits_flow.set_meta("key", key)
		for c in _traits_flow.get_children():
			c.queue_free()
		if traits.is_empty():
			var none := Label.new()
			none.theme_type_variation = &"MutedLabel"
			none.text = "No notable traits"
			_traits_flow.add_child(none)
		for tr in traits:
			_traits_flow.add_child(_make_tag(String(tr).capitalize() if not String(tr).contains(" ") else String(tr), Color("#F3DFC6")))
	_ready_panel.visible = bool(info.get("ready", false))
	var can_adopt: bool = _ready_panel.visible and level != null and level.has_method("adopt_cat")
	_adopt_button.visible = can_adopt
	if can_adopt:
		var base: float = 1.0
		var bal = _lget("balance", {})
		if bal is Dictionary:
			base = float((bal as Dictionary).get("economy", {}).get("adoption_reputation", 1))
		var mult: float = float(level.get_adoption_reputation_mult()) if level.has_method("get_adoption_reputation_mult") else 1.0
		_adopt_button.text = "Find a home  (+%d rep)" % maxi(1, roundi(base * mult))

func _on_adopt_pressed() -> void:
	if level == null or _selected_cat == null or not is_instance_valid(_selected_cat):
		return
	if level.has_method("adopt_cat") and int(level.adopt_cat(_selected_cat)) >= 0:
		_close_cards()

# ---------------------------------------------------------------- decor card

func _fill_decor_card(info: Dictionary) -> void:
	var id: String = String(info.get("id", ""))
	_decor_name.text = String(info.get("name", id.capitalize()))
	var cat_s: String = _decor_category_of(id)
	var color_s: String = String(info.get("color", ""))
	_decor_meta.text = "  ·  ".join(PackedStringArray([cat_s, color_s].filter(func(x): return not String(x).is_empty())))
	for c in _decor_effects.get_children():
		c.queue_free()
	var def: Dictionary = {}
	var data_map = _lget("decor_data_by_id", {})
	if data_map is Dictionary:
		def = (data_map as Dictionary).get(id, {})
	var buffs = def.get("buffs", {})
	var lines: Array[String] = []
	if buffs is Dictionary:
		for bk in (buffs as Dictionary).keys():
			lines.append(_describe_buff(String(bk), buffs[bk]))
	if lines.is_empty():
		lines.append("Purely decorative")
	for line in lines:
		var l := Label.new()
		l.text = "•  " + line
		l.add_theme_font_size_override("font_size", 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(CARD_WIDTH - 40.0, 0)
		_decor_effects.add_child(l)
	var aura: int = int(def.get("aura_radius", 0))
	var parts: PackedStringArray = []
	if aura > 0:
		parts.append("Aura %d tile%s" % [aura, "" if aura == 1 else "s"])
	parts.append("Durability %d" % int(info.get("durability", 100)))
	_decor_footer.text = "  ·  ".join(parts)
	var refund: int = _refund_of(info)
	_decor_remove.text = "Put away  (+$%d)" % refund if refund > 0 else "Put away"
	_render_decor_preview(String(info.get("mesh_scene", "")), info.get("scale", Vector3.ONE))

func _describe_buff(key: String, v) -> String:
	var f: float = float(v) if (v is float or v is int) else 0.0
	var pct: int = int(round(absf(f - 1.0) * 100.0))
	var more: bool = f >= 1.0
	match key:
		"patron_stay_mult":
			return "Patrons stay %d%% %s" % [pct, "longer" if more else "shorter"]
		"tip_mult":
			return "Tips %s%d%%" % ["+" if more else "-", pct]
		"patron_turnover_mult":
			return "Patron turnover %s%d%%" % ["+" if more else "-", pct]
		"interaction_mult":
			return "Cat stress from patrons %s%d%%" % ["+" if more else "-", pct]
		"mid_rest_reduction":
			return "Cats perched here unwind faster (-%d stress/s)" % int(f)
		"line_of_sight_break":
			return "Screens cats from patrons behind it (-%d%% stress)" % int(round(f * 100.0))
		"pathing_speed_mult":
			return "Cats move %d%% %s nearby" % [pct, "faster" if more else "slower"]
		"trust_gain_mult":
			return "Cats build trust %d%% faster" % pct
		"overstim_decay_mult":
			return "Cats calm down %d%% faster" % pct
		"adoption_reputation_mult":
			return "Adoptions give %d%% more reputation" % pct
	if key.ends_with("_spawn_bias"):
		var who: String = key.trim_suffix("_spawn_bias").capitalize()
		if who == "Hyper":
			who = "Hyper Toddlers"
		elif who == "Gentle Reader":
			who = "Gentle Readers"
		return "%s %s" % ["More" if f > 0.0 else "Fewer", who + " visit"]
	return "%s %s" % [key.capitalize(), str(v)]

## GP-04: refund half of what was actually paid (starter decor was free, so it refunds 0).
func _refund_of(info: Dictionary) -> int:
	if info.has("refund"):
		return int(info["refund"])
	return int(floor(float(info.get("paid", 0)) * REFUND_RATIO))

func _on_remove_pressed() -> void:
	if level == null or _inspected_cell.x <= -9999 or not level.has_method("remove_decor"):
		return
	var refund: int = _refund_of(_inspected_info)
	if bool(level.remove_decor(_inspected_cell)):
		if refund > 0 and level.has_method("add_money"):
			level.add_money(refund, "refund")
		_close_cards()

func _render_decor_preview(scene_path: String, scale_v) -> void:
	_stage_preview(scene_path, scale_v, _decor_preview_root, _decor_cam, _decor_viewport, 1.18)

## Instances scene_path under root and frames cam on it (decor card preview and V9 thumbs).
func _stage_preview(scene_path: String, scale_v, root: Node3D, cam: Camera3D, vp: SubViewport, pad: float) -> bool:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return false
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return false
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		inst.free()
		return false
	var n3 := inst as Node3D
	n3.scale = scale_v if scale_v is Vector3 else Vector3.ONE
	root.add_child(n3)
	var box: AABB = _collect_aabb(n3, n3.transform)
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	var center: Vector3 = box.get_center()
	var yaw: float = deg_to_rad(35.0)
	var pitch: float = deg_to_rad(28.0)
	var back := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var basis := Basis.looking_at(-back, Vector3.UP)
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for i in range(8):
		var p: Vector3 = box.get_endpoint(i) - center
		var px: float = p.dot(basis.x)
		var py: float = p.dot(basis.y)
		min_x = minf(min_x, px)
		max_x = maxf(max_x, px)
		min_y = minf(min_y, py)
		max_y = maxf(max_y, py)
	var vp_size: Vector2 = Vector2(vp.size)
	var aspect: float = vp_size.x / maxf(1.0, vp_size.y)
	cam.size = maxf(max_y - min_y, (max_x - min_x) / aspect) * pad
	var mid: Vector3 = center + basis.x * ((min_x + max_x) * 0.5) + basis.y * ((min_y + max_y) * 0.5)
	cam.global_transform = Transform3D(basis, mid + back * 12.0)
	return true

func _collect_aabb(node: Node, xform: Transform3D) -> AABB:
	var out := AABB()
	var has: bool = false
	if node is VisualInstance3D and not (node is Light3D):
		var a: AABB = xform * (node as VisualInstance3D).get_aabb()
		out = a
		has = true
	for child in node.get_children():
		if child is Node3D:
			var ca: AABB = _collect_aabb(child, xform * (child as Node3D).transform)
			if ca.size != Vector3.ZERO:
				out = ca if not has else out.merge(ca)
				has = true
	return out

# ---------------------------------------------------------------- selection ring

func _create_selection_ring() -> void:
	if level == null or not (level is Node3D):
		return
	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "CatSelectionRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.36
	torus.rings = 32
	torus.ring_segments = 6
	_selection_ring.mesh = torus
	_selection_ring.scale = Vector3(1.0, 0.15, 0.75)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.93, 0.7, 0.9)
	_selection_ring.material_override = mat
	_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_ring.visible = false
	level.add_child(_selection_ring)

func _update_selection_ring(delta: float) -> void:
	if _selection_ring == null:
		return
	var show: bool = _cat_card.visible and _selected_cat != null and is_instance_valid(_selected_cat)
	_selection_ring.visible = show
	if not show:
		return
	_ring_t += delta
	var s: float = 1.0 + sin(_ring_t * 4.0) * 0.06
	_selection_ring.global_position = _selected_cat.global_position + Vector3(0, 0.03, 0)
	_selection_ring.scale = Vector3(s, 0.15, s * 0.75)

# ---------------------------------------------------------------- UI construction

func _anchor(c: Control, ax: float, ay: float, ox: float, oy: float, gh: int, gv: int) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	c.grow_horizontal = gh
	c.grow_vertical = gv

func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

func _hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

func _vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

func _label(text: String, variation: StringName = &"", size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l

func _icon(kind: String, px: float = 26.0) -> HudIcon:
	var i := HudIcon.new()
	i.kind = kind
	i.custom_minimum_size = Vector2(px, px)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i

func _chip(kind: String) -> Array:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"HUDChip"
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := _hbox(8)
	chip.add_child(h)
	h.add_child(_icon(kind))
	var l := _label("", &"", 20)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return [chip, l]

func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _set_swatch(p: Panel, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = col.darkened(0.3)
	p.add_theme_stylebox_override("panel", sb)

func _set_tag_color(p: PanelContainer, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = col.darkened(0.25)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)

func _make_tag(text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"TagPanel"
	_set_tag_color(p, col)
	p.add_child(_label(text, &"TagLabel"))
	return p

func _bar(fill_col: Color) -> Array:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 14)
	b.min_value = 0.0
	b.max_value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_col
	fill.set_corner_radius_all(7)
	b.add_theme_stylebox_override("fill", fill)
	return [b, fill]

func _card_header(title_label: Label, extra: Control) -> HBoxContainer:
	var h := _hbox(8)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(title_label)
	if extra != null:
		extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(extra)
	var close := Button.new()
	close.theme_type_variation = &"CloseButton"
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(30, 30)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close_cards)
	h.add_child(close)
	return h

func _build_ui() -> void:
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- top-left status chips
	var top_left := _hbox(10)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(top_left)
	_anchor(top_left, 0, 0, MARGIN, MARGIN, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	var m: Array = _chip("coin")
	_money_chip = m[0]
	_money_label = m[1]
	_money_chip.tooltip_text = "Money - patrons tip as they leave"
	top_left.add_child(_money_chip)
	var r: Array = _chip("heart")
	_rep_label = r[1]
	(r[0] as Control).tooltip_text = "Reputation - earned when cats find a home"
	top_left.add_child(r[0])
	var c: Array = _chip("paw")
	_cats_label = c[1]
	(c[0] as Control).tooltip_text = "Cats out on the cafe floor (not resting)"
	top_left.add_child(c[0])

	# --- top-right day chip
	var day_chip := PanelContainer.new()
	day_chip.theme_type_variation = &"HUDChip"
	ui_root.add_child(day_chip)
	_anchor(day_chip, 1, 0, -MARGIN, MARGIN, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	var dh := _hbox(10)
	day_chip.add_child(dh)
	_day_icon = _icon("sun")
	dh.add_child(_day_icon)
	_day_label = _label("Day 1", &"", 20)
	_day_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dh.add_child(_day_label)
	var dcol := _vbox(2)
	dcol.alignment = BoxContainer.ALIGNMENT_CENTER
	dh.add_child(dcol)
	_clock_label = _label("8:00 AM", &"", 16)
	_clock_label.add_theme_color_override("font_color", COL_TEXT)
	_clock_label.custom_minimum_size = Vector2(96, 0)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dcol.add_child(_clock_label)
	var db: Array = _bar(COL_MID)
	_day_bar = db[0]
	_day_bar.custom_minimum_size = Vector2(96, 8)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(COL_BORDER, 0.35)
	track.set_corner_radius_all(4)
	_day_bar.add_theme_stylebox_override("background", track)
	dcol.add_child(_day_bar)

	# --- drought / event toast
	_toast = PanelContainer.new()
	_toast.theme_type_variation = &"ToastPanel"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	ui_root.add_child(_toast)
	_anchor(_toast, 0.5, 0, 0, 84, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	var th := _hbox(10)
	_toast.add_child(th)
	var ti := _icon("paw_white", 24)
	th.add_child(ti)
	_toast_label = _label("", &"ToastLabel")
	_toast_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(_toast_label)
	_ignore_mouse(_toast)

	# --- bottom-left build button
	_build_button = Button.new()
	_build_button.text = "Build"
	_build_button.tooltip_text = "Build menu (B)"
	_build_button.focus_mode = Control.FOCUS_NONE
	_build_button.custom_minimum_size = Vector2(150, 50)
	_build_button.add_theme_font_size_override("font_size", 20)
	_build_button.pressed.connect(_toggle_build_panel)
	ui_root.add_child(_build_button)
	_anchor(_build_button, 0, 1, MARGIN, -MARGIN, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	var bi := _icon("hammer", 22)
	_build_button.add_child(bi)
	bi.position = Vector2(16, 14)
	_build_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_button.add_theme_constant_override("h_separation", 0)
	_build_button.text = "     Build"

	# --- build panel (opens upward)
	_build_panel = PanelContainer.new()
	_build_panel.name = "BuildPanel"
	_build_panel.visible = false
	_build_panel.custom_minimum_size = Vector2(372, 0)
	ui_root.add_child(_build_panel)
	_anchor(_build_panel, 0, 1, MARGIN, -MARGIN - 50 - 10, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	var bcol := _vbox(8)
	_build_panel.add_child(bcol)
	var bt := _label("Build & Decorate", &"TitleLabel")
	var bh := _card_header(bt, null)
	(bh.get_child(bh.get_child_count() - 1) as Button).pressed.connect(func(): _build_panel.visible = false)
	bcol.add_child(bh)
	_build_money_label = _label("You have $0", &"MutedLabel")
	bcol.add_child(_build_money_label)
	var scroll_stack := MarginContainer.new()
	bcol.add_child(scroll_stack)
	_build_scroll = ScrollContainer.new()
	_build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_scroll.custom_minimum_size = Vector2(0, 360)
	scroll_stack.add_child(_build_scroll)
	# V10: bottom fade hints that more items follow.
	var grad := Gradient.new()
	var bg := Color("#FFF6EA")
	grad.set_color(0, Color(bg, 0.0))
	grad.set_color(1, Color(bg, 1.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	gtex.width = 8
	gtex.height = 32
	_build_fade = TextureRect.new()
	_build_fade.texture = gtex
	_build_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_build_fade.stretch_mode = TextureRect.STRETCH_SCALE
	_build_fade.custom_minimum_size = Vector2(0, 16)
	_build_fade.size_flags_vertical = Control.SIZE_SHRINK_END
	_build_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_stack.add_child(_build_fade)
	_build_scroll.get_v_scroll_bar().value_changed.connect(func(_v): _update_build_fade())
	_build_scroll.get_v_scroll_bar().changed.connect(_update_build_fade)
	var list_margin := MarginContainer.new()
	list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_right", 14)
	_build_scroll.add_child(list_margin)
	_build_list = _vbox(6)
	_build_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_child(_build_list)
	bcol.add_child(_label("Pick an item, then click the floor to place it.", &"MutedLabel", 14))

	# --- placing hint bar (top-centre, under the chips: V4)
	_hold_bar = PanelContainer.new()
	_hold_bar.visible = false
	ui_root.add_child(_hold_bar)
	_anchor(_hold_bar, 0.5, 0, 0, MARGIN + 52, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	var hh := _hbox(12)
	_hold_bar.add_child(hh)
	_hold_swatch = Panel.new()
	_hold_swatch.custom_minimum_size = Vector2(26, 26)
	_hold_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hh.add_child(_hold_swatch)
	var hcol := _vbox(0)
	hh.add_child(hcol)
	_hold_label = _label("Placing", &"", 18)
	hcol.add_child(_hold_label)
	hcol.add_child(_label("Click to place  ·  R / Q / E or wheel to rotate  ·  Shift keeps it  ·  Esc cancels", &"MutedLabel", 14))
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_on_cancel_hold_pressed)
	hh.add_child(cancel)

	# --- cat inspector card (right)
	_cat_card = PanelContainer.new()
	_cat_card.name = "CatCard"
	_cat_card.visible = false
	_cat_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	ui_root.add_child(_cat_card)
	_anchor(_cat_card, 1, 0, -MARGIN, 84, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	var cc := _vbox(8)
	_cat_card.add_child(cc)
	_cat_name = _label("Cat", &"TitleLabel")
	_cat_rarity = PanelContainer.new()
	_cat_rarity.theme_type_variation = &"TagPanel"
	_cat_rarity_label = _label("Common", &"TagLabel")
	_cat_rarity.add_child(_cat_rarity_label)
	var chead := _card_header(_cat_name, _cat_rarity)
	chead.add_child(_icon("paw", 0))
	chead.move_child(chead.get_child(chead.get_child_count() - 1), 0)
	(chead.get_child(0) as Control).custom_minimum_size = Vector2(24, 24)
	cc.add_child(chead)
	_cat_state = _label("", &"MutedLabel")
	cc.add_child(_cat_state)
	cc.add_child(HSeparator.new())
	var trow := _hbox(8)
	trow.add_child(_label("Trust", &"", 17))
	trow.add_child(_spacer())
	_trust_value = _label("0 / 100", &"MutedLabel")
	_trust_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(_trust_value)
	_trust_tag = PanelContainer.new()
	_trust_tag.theme_type_variation = &"TagPanel"
	_trust_tag_label = _label("Fearful", &"TagLabel")
	_trust_tag.add_child(_trust_tag_label)
	_trust_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(_trust_tag)
	cc.add_child(trow)
	var tb: Array = _bar(COL_TRUST)
	_trust_bar = tb[0]
	_trust_fill = tb[1]
	cc.add_child(_trust_bar)
	var orow := _hbox(8)
	orow.add_child(_label("Overstimulation", &"", 17))
	orow.add_child(_spacer())
	_overstim_value = _label("0 / 100", &"MutedLabel")
	orow.add_child(_overstim_value)
	cc.add_child(orow)
	var ob: Array = _bar(COL_LOW)
	_overstim_bar = ob[0]
	_overstim_fill = ob[1]
	cc.add_child(_overstim_bar)
	cc.add_child(_label("Traits", &"", 17))
	_traits_flow = HFlowContainer.new()
	_traits_flow.add_theme_constant_override("h_separation", 6)
	_traits_flow.add_theme_constant_override("v_separation", 6)
	cc.add_child(_traits_flow)
	_ready_panel = PanelContainer.new()
	_ready_panel.theme_type_variation = &"TagPanel"
	_set_tag_color(_ready_panel, Color("#F6D3D6"))
	var rh := _hbox(8)
	rh.alignment = BoxContainer.ALIGNMENT_CENTER
	_ready_panel.add_child(rh)
	rh.add_child(_icon("heart", 20))
	rh.add_child(_label("Ready for adoption!", &"", 17))
	_ready_panel.visible = false
	cc.add_child(_ready_panel)
	_adopt_button = Button.new()
	_adopt_button.text = "Find a home"
	_adopt_button.focus_mode = Control.FOCUS_NONE
	_adopt_button.visible = false
	_adopt_button.pressed.connect(_on_adopt_pressed)
	cc.add_child(_adopt_button)

	# --- decor inspector card (right)
	_decor_card = PanelContainer.new()
	_decor_card.name = "DecorCard"
	_decor_card.visible = false
	_decor_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	ui_root.add_child(_decor_card)
	_anchor(_decor_card, 1, 0, -MARGIN, 84, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	var dc := _vbox(8)
	_decor_card.add_child(dc)
	_decor_name = _label("Decor", &"TitleLabel")
	dc.add_child(_card_header(_decor_name, null))
	_decor_meta = _label("", &"MutedLabel")
	dc.add_child(_decor_meta)
	var pv_panel := PanelContainer.new()
	pv_panel.theme_type_variation = &"TagPanel"
	_set_tag_color(pv_panel, Color("#F3E6D3"))
	dc.add_child(pv_panel)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(CARD_WIDTH - 50.0, 160)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv_panel.add_child(svc)
	_decor_viewport = SubViewport.new()
	_decor_viewport.own_world_3d = true
	_decor_viewport.transparent_bg = true
	_decor_viewport.msaa_3d = Viewport.MSAA_4X
	_decor_viewport.size = Vector2i(int(CARD_WIDTH - 50.0), 160)
	_decor_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(_decor_viewport)
	var world := Node3D.new()
	_decor_viewport.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#FFE6CC")
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color("#FFE2BF")
	sun.light_energy = 1.2
	world.add_child(sun)
	_decor_preview_root = Node3D.new()
	world.add_child(_decor_preview_root)
	_decor_cam = Camera3D.new()
	_decor_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_decor_cam.size = 3.0
	_decor_cam.current = true
	_decor_cam.far = 50.0
	world.add_child(_decor_cam)
	dc.add_child(_label("Effects", &"", 17))
	_decor_effects = _vbox(2)
	dc.add_child(_decor_effects)
	_decor_footer = _label("", &"MutedLabel")
	dc.add_child(_decor_footer)
	_decor_remove = Button.new()
	_decor_remove.text = "Put away"
	_decor_remove.focus_mode = Control.FOCUS_NONE
	_decor_remove.pressed.connect(_on_remove_pressed)
	dc.add_child(_decor_remove)

	# --- offscreen thumbnail renderer for the build list (V9)
	_thumb_vp = SubViewport.new()
	_thumb_vp.own_world_3d = true
	_thumb_vp.transparent_bg = true
	_thumb_vp.msaa_3d = Viewport.MSAA_4X
	_thumb_vp.size = Vector2i(THUMB_PX, THUMB_PX)
	_thumb_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_thumb_vp)
	var tworld := Node3D.new()
	_thumb_vp.add_child(tworld)
	var tenv := WorldEnvironment.new()
	tenv.environment = e
	tworld.add_child(tenv)
	var tsun := DirectionalLight3D.new()
	tsun.rotation_degrees = Vector3(-50, 30, 0)
	tsun.light_color = Color("#FFE2BF")
	tsun.light_energy = 1.2
	tworld.add_child(tsun)
	_thumb_root = Node3D.new()
	tworld.add_child(_thumb_root)
	_thumb_cam = Camera3D.new()
	_thumb_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_thumb_cam.size = 3.0
	_thumb_cam.current = true
	_thumb_cam.far = 50.0
	tworld.add_child(_thumb_cam)

	# --- controls help (bottom-right); collapses to a "? Controls" chip (V3)
	_help_chip = Button.new()
	_help_chip.text = "?  Controls"
	_help_chip.tooltip_text = "Show controls (F1)"
	_help_chip.focus_mode = Control.FOCUS_NONE
	_help_chip.custom_minimum_size = Vector2(110, 34)
	_help_chip.add_theme_font_size_override("font_size", 14)
	_help_chip.modulate = Color(1, 1, 1, 0.85)
	_help_chip.visible = false
	_help_chip.pressed.connect(_toggle_help)
	ui_root.add_child(_help_chip)
	_anchor(_help_chip, 1, 1, -MARGIN, -MARGIN, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	_help = PanelContainer.new()
	_help.theme_type_variation = &"HUDChip"
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.modulate = Color(1, 1, 1, HELP_REST_ALPHA)
	ui_root.add_child(_help)
	_anchor(_help, 1, 1, -MARGIN, -MARGIN, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	var hv := _vbox(0)
	_help.add_child(hv)
	hv.add_child(_label("WASD / middle-drag  pan   ·   Wheel  zoom   ·   Home  overview", &"MutedLabel", 13))
	hv.add_child(_label("Click a cat or decor to inspect   ·   B  build", &"MutedLabel", 13))
	hv.add_child(_label("Saves at day end & on quit   ·   F9 ×2  new game   ·   F1  hide help", &"MutedLabel", 13))
	hv.add_child(_label("F7  debug panel   ·   F8  pixel / smooth cats   ·   F6  cat rig", &"MutedLabel", 13))
	_ignore_mouse(_help)

	_build_debug_panel()

# ---------------------------------------------------------------- debug panel (F7)

func is_debug_panel_open() -> bool:
	return _debug_panel != null and _debug_panel.visible

## F7: small cat-rendering debug panel (top-left, under the status chips).
func toggle_debug_panel() -> void:
	set_debug_panel_open(not _debug_panel.visible)

func set_debug_panel_open(on: bool) -> void:
	if on:
		_build_panel.visible = false
		_sync_debug_panel()
	_debug_panel.visible = on

func _build_debug_panel() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.name = "DebugPanel"
	_debug_panel.visible = false
	_debug_panel.custom_minimum_size = Vector2(DEBUG_WIDTH, 0)
	ui_root.add_child(_debug_panel)
	_anchor(_debug_panel, 0, 0, MARGIN, 84, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	var col := _vbox(7)
	_debug_panel.add_child(col)
	var head := _hbox(8)
	var title := _label("Debug", &"TitleLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var key := _label("F7", &"MutedLabel", 13)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(key)
	var close := Button.new()
	close.theme_type_variation = &"CloseButton"
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(30, 30)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): _debug_panel.visible = false)
	head.add_child(close)
	col.add_child(head)
	var pair: Array = _debug_toggle_pair("Pixel", "Smooth", func(first: bool) -> void:
		level.call("set_cat_render_mode", first, _density_choice()))
	_dbg_pixel = pair[1]
	_dbg_smooth = pair[2]
	_dbg_pixel.tooltip_text = "Pixel-art cats (F8 flips)"
	_dbg_smooth.tooltip_text = "Smooth vector cats (F8 flips)"
	col.add_child(_debug_row("Cats", pair[0]))
	_dbg_density = _debug_option([])
	for d in [48, 56, 64, 80, 96]:
		_dbg_density.add_item("%d px" % d, d)
	_dbg_density.tooltip_text = "Pixel density (art pixels across the cat sprite)"
	_dbg_density.item_selected.connect(func(_i: int) -> void:
		if not _dbg_syncing:
			level.call("set_cat_render_mode", true, _density_choice()))
	col.add_child(_debug_row("Density", _dbg_density))
	var rig: Array = _debug_toggle_pair("Procedural", "Sprite", func(first: bool) -> void:
		level.call("set_viewport_rig", first))
	_dbg_rig_proc = rig[1]
	_dbg_rig_fallback = rig[2]
	_dbg_rig_fallback.tooltip_text = "Fallback sprite (F6)"
	col.add_child(_debug_row("Rig", rig[0]))
	var shapes: Array = ["Random (genome)"]
	shapes.append_array(CatPixelFaceScript.EYE_SHAPES)
	_dbg_eye = _debug_option(shapes)
	for i in range(1, _dbg_eye.item_count):
		_dbg_eye.set_item_tooltip(i, str(CatPixelFaceScript.EYE_SHAPE_INFO.get(_dbg_eye.get_item_text(i), "")))
	_dbg_eye.tooltip_text = "Show one eye shape on every cat (Random = each cat's own)"
	_dbg_eye.item_selected.connect(func(i: int) -> void:
		if not _dbg_syncing:
			level.call("set_cat_eye_override", "" if i == 0 else _dbg_eye.get_item_text(i)))
	col.add_child(_debug_row("Eyes", _dbg_eye))
	_dbg_expr = _debug_option(["Auto", "open", "happy", "stressed", "sleepy", "angry", "worried", "sad", "surprised", "smug"])
	_dbg_expr.tooltip_text = "Force a face expression on every cat"
	_dbg_expr.item_selected.connect(func(i: int) -> void:
		if not _dbg_syncing:
			level.call("set_cat_expression_override", "" if i == 0 else _dbg_expr.get_item_text(i)))
	col.add_child(_debug_row("Face", _dbg_expr))
	col.add_child(_label("Debug only - saved separately from the cafe.", &"MutedLabel", 12))

func _debug_row(text: String, control: Control) -> HBoxContainer:
	var h := _hbox(8)
	var l := _label(text, &"MutedLabel", 15)
	l.custom_minimum_size = Vector2(62, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h

# Two-state segmented toggle. on_pick(first: bool) runs when the user picks.
func _debug_toggle_pair(a: String, b: String, on_pick: Callable) -> Array:
	var h := _hbox(4)
	var group := ButtonGroup.new()
	var out: Array = [h]
	for t in [a, b]:
		var btn := Button.new()
		btn.text = t
		btn.toggle_mode = true
		btn.button_group = group
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 15)
		var first: bool = t == a
		btn.toggled.connect(func(on: bool) -> void:
			if on and not _dbg_syncing:
				on_pick.call(first))
		h.add_child(btn)
		out.append(btn)
	return out

func _debug_option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Vector2(0, 32)
	o.add_theme_font_size_override("font_size", 15)
	for it in items:
		o.add_item(str(it))
	var pm: PopupMenu = o.get_popup()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#FFF6EA")
	sb.set_border_width_all(2)
	sb.border_color = COL_BORDER
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6)
	pm.add_theme_stylebox_override("panel", sb)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("#F3DFC4")
	hover.set_corner_radius_all(6)
	pm.add_theme_stylebox_override("hover", hover)
	pm.add_theme_color_override("font_color", COL_TEXT)
	pm.add_theme_color_override("font_hover_color", COL_TEXT)
	pm.add_theme_font_size_override("font_size", 15)
	return o

func _density_choice() -> int:
	return _dbg_density.get_item_id(maxi(0, _dbg_density.selected))

# Reflects the level's current debug settings (also after F6 / F8).
func _sync_debug_panel() -> void:
	if _debug_panel == null or level == null or not level.has_method("get_debug_settings"):
		return
	var d: Dictionary = level.call("get_debug_settings")
	_dbg_syncing = true
	var pixel: bool = bool(d.get("pixel_art", true))
	_dbg_pixel.button_pressed = pixel
	_dbg_smooth.button_pressed = not pixel
	var dens: int = int(d.get("pixel_density", 56))
	var idx: int = _dbg_density.get_item_index(dens)
	if idx < 0:
		_dbg_density.add_item("%d px" % dens, dens)
		idx = _dbg_density.get_item_index(dens)
	_dbg_density.select(idx)
	_dbg_density.disabled = not pixel
	var rig: bool = bool(d.get("viewport_rig", true))
	_dbg_rig_proc.button_pressed = rig
	_dbg_rig_fallback.button_pressed = not rig
	var es: String = str(d.get("eye_shape", ""))
	var ei: int = CatPixelFaceScript.EYE_SHAPES.find(es)
	_dbg_eye.select(ei + 1 if ei >= 0 else 0)
	var ex: String = str(d.get("expression", ""))
	var xi: int = 0
	for i in range(1, _dbg_expr.item_count):
		if _dbg_expr.get_item_text(i) == ex:
			xi = i
	_dbg_expr.select(xi)
	_dbg_syncing = false


## Small procedural HUD icon (no imported textures).
class HudIcon extends Control:
	var kind: String = "coin"

	func _draw() -> void:
		var s: Vector2 = size
		var c: Vector2 = s * 0.5
		var r: float = minf(s.x, s.y) * 0.5
		var outline := Color("#4A3426")
		match kind:
			"coin":
				draw_circle(c, r * 0.92, Color("#B8862F"), true, -1.0, true)
				draw_circle(c, r * 0.78, Color("#F2C14E"), true, -1.0, true)
				draw_circle(c, r * 0.5, Color("#E3A93A"), true, -1.0, true)
				draw_arc(c + Vector2(-r * 0.12, -r * 0.12), r * 0.55, PI * 1.05, PI * 1.45, 8, Color(1, 1, 1, 0.75), r * 0.14, true)
			"heart":
				var col := Color("#E07A82")
				var pts := PackedVector2Array()
				for i in range(48):
					var t: float = TAU * float(i) / 48.0
					var x: float = 16.0 * pow(sin(t), 3)
					var y: float = -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
					pts.append(c + Vector2(x, y + 1.5) * (r / 17.5))
				draw_colored_polygon(pts, col)
				pts.append(pts[0])
				draw_polyline(pts, col.darkened(0.35), maxf(1.0, r * 0.1), true)
				draw_circle(c + Vector2(-r * 0.38, -r * 0.3), r * 0.15, Color(1, 1, 1, 0.6), true, -1.0, true)
			"paw", "paw_white":
				var col: Color = Color("#FFF6EA") if kind == "paw_white" else Color("#C98A5E")
				draw_circle(c + Vector2(0, r * 0.3), r * 0.42, col, true, -1.0, true)
				draw_circle(c + Vector2(-r * 0.62, -r * 0.12), r * 0.2, col, true, -1.0, true)
				draw_circle(c + Vector2(-r * 0.24, -r * 0.5), r * 0.21, col, true, -1.0, true)
				draw_circle(c + Vector2(r * 0.24, -r * 0.5), r * 0.21, col, true, -1.0, true)
				draw_circle(c + Vector2(r * 0.62, -r * 0.12), r * 0.2, col, true, -1.0, true)
			"sun":
				var col := Color("#F2B544")
				for i in range(8):
					var a: float = TAU * float(i) / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * r * 0.62, c + Vector2(cos(a), sin(a)) * r * 0.95, col.darkened(0.1), maxf(1.5, r * 0.16), true)
				draw_circle(c, r * 0.48, col, true, -1.0, true)
			"moon":
				draw_circle(c, r * 0.8, Color("#8E86B8"), true, -1.0, true)
				draw_circle(c + Vector2(r * 0.38, -r * 0.3), r * 0.66, Color("#FFF6EA"), true, -1.0, true)
			"hammer":
				var wood := Color("#9C6B4A")
				var steel := Color("#6E7378")
				var a := c + Vector2(-r * 0.55, r * 0.6)
				var b := c + Vector2(r * 0.25, -r * 0.2)
				draw_line(a, b, wood, r * 0.32, true)
				var head := PackedVector2Array([
					c + Vector2(-r * 0.05, -r * 0.85), c + Vector2(r * 0.85, r * 0.05),
					c + Vector2(r * 0.55, r * 0.35), c + Vector2(-r * 0.35, -r * 0.55)])
				draw_colored_polygon(head, steel)
				head.append(head[0])
				draw_polyline(head, outline, 1.0, true)
			_:
				draw_circle(c, r * 0.6, outline, true, -1.0, true)
