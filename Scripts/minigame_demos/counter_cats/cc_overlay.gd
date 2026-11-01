extends CanvasLayer

## Counter Cats overlay: dims + pauses the live cafe, shows a cream kitchen window
## with the 320x180 play area (SubViewport, nearest filter, integer scale), a step
## ticket, cat chips, a prompt bar, the park prompt and the result card.
## Self-contained on purpose (the shared MinigameHost is still being built); see
## Docs/minigames/COUNTER_CATS.md for how it maps onto that host later.
##
## Rewards are applied exactly once, AFTER unpausing: money via
## level.add_money(x, "order"), cat care deltas onto the real cats (guarded,
## clamped, capped per round), then a HUD notice.

signal closed(result: Dictionary, report: Dictionary)
signal parked
signal opened

const Art := preload("res://Scripts/minigame_demos/counter_cats/cc_art.gd")
const R := preload("res://Scripts/minigame_demos/counter_cats/cc_recipes.gd")
const GameScript := preload("res://Scripts/minigame_demos/counter_cats/cc_game.gd")
const StampScript := preload("res://Scripts/minigame_demos/counter_cats/cc_stamp.gd")
const THEME_PATH := "res://UI/cozy_theme.tres"

const DIM := Color(0.169, 0.129, 0.161, 0.6)    # cocoa #2B2129 @ 60%

var level: Node = null
var game: Node2D = null
var context: Dictionary = {}
var is_open: bool = false
var is_parked: bool = false
var last_result: Dictionary = {}
var last_report: Dictionary = {}
var rewards_applied_count: int = 0

var _was_paused: bool = false
var _scale: int = 3
## screen px per text-rule px for the big floating popups
const POPUP_TEXT_UNIT: int = 2
var _rewarded: bool = false
var _showing_result: bool = false
var _park_open: bool = false

var _root: Control
var _dim: ColorRect
var _window: PanelContainer
var _title: Label
var _diff: Label
var _cat_box: HBoxContainer
var _ticket: HBoxContainer
var _timer_lbl: Label
var _timer_bar: Control
var _play_holder: Control
var _play_rect: TextureRect
var _popups: Control
var _alert_icon: TextureRect
var _hint: Label
var _alert: Label
var _keys: Label
var _vp: SubViewport
var _result: PanelContainer
var _park: PanelContainer
var _stamp: Control
var _res_title: Label
var _res_lines: VBoxContainer
var _serve_btn: Button
var _hud_cache: Dictionary = {}
var _frame: Panel
var _style_rev: int = -1

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false

# ------------------------------------------------------------------ public

func open(ctx: Dictionary) -> void:
	if is_open:
		return
	if is_parked and game != null:
		_resume_parked()
		return
	context = ctx
	_restyle()
	_rewarded = false
	_showing_result = false
	_result.visible = false
	_park.visible = false
	_park_open = false
	if game != null:
		game.queue_free()
		game = null
	game = GameScript.new()
	game.name = "CounterCatsGame"
	_vp.add_child(game)
	game.call("setup", ctx)
	game.connect("scored", _on_scored)
	game.connect("popup", _on_popup)
	_enter()
	opened.emit()

func _enter() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true
	is_open = true
	_root.visible = true
	_layout()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _resume_parked() -> void:
	is_parked = false
	game.process_mode = Node.PROCESS_MODE_INHERIT
	_enter()

func park() -> void:
	if not is_open or _showing_result:
		return
	_close_park_prompt()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	is_parked = true
	_exit()
	parked.emit()
	_notice("Order parked - press F11 to pick it back up", 2.5)

## Leave the order: no money, no loss. Pets that already happened still count.
func leave() -> void:
	if not is_open or game == null:
		return
	_close_park_prompt()
	var res: Dictionary = _partial_result()
	_exit()
	_apply_rewards(res, false)
	closed.emit(res, last_report)

func _exit() -> void:
	is_open = false
	_root.visible = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_tree().paused = _was_paused

func serve() -> void:
	if not _showing_result:
		return
	_showing_result = false
	_result.visible = false
	var res: Dictionary = last_result
	is_parked = false
	_exit()
	_apply_rewards(res, true)
	closed.emit(res, last_report)

func is_result_showing() -> bool:
	return _showing_result

func is_park_prompt_open() -> bool:
	return _park_open

## Game-space (320x180) -> overlay-local position, for probes / popups.
func game_to_screen(p: Vector2) -> Vector2:
	return _play_rect.global_position + p * float(_scale)

# ------------------------------------------------------------------ rewards

func _partial_result() -> Dictionary:
	var cats_out: Array = []
	var stats: Array = game.get("cat_stats")
	var cats: Array = game.get("cats")
	for i in range(cats.size()):
		var info: Dictionary = cats[i].get("info")
		cats_out.append({"name": str(info.get("name", "Cat")), "node_id": int(info.get("node_id", 0)),
			"pets": int(stats[i]["pets"]), "assists": int(stats[i]["assists"]), "booped": int(stats[i]["booped"]),
			"delta": R.care_delta(int(stats[i]["pets"]), int(stats[i]["assists"]))})
	return {"left": true, "money": 0, "grade": "", "cats": cats_out, "recipe_name": context.get("recipe_name", "")}

func _apply_rewards(res: Dictionary, pay: bool) -> void:
	if _rewarded:
		return
	_rewarded = true
	rewards_applied_count += 1
	var report := {"money": 0, "cats": []}
	var money: int = int(res.get("money", 0)) if pay else 0
	if money > 0 and level != null and is_instance_valid(level) and level.has_method("add_money"):
		level.call("add_money", money, "order")
		report["money"] = money
	var calmer: Array[String] = []
	for c in res.get("cats", []):
		var d: Dictionary = c.get("delta", {"overstim": 0.0, "trust": 0.0})
		var entry := {"name": c.get("name", "Cat"), "applied": false, "delta": d}
		var nid: int = int(c.get("node_id", 0))
		var cat: Object = instance_from_id(nid) if nid != 0 else null
		if cat != null and is_instance_valid(cat) and not (cat as Node).is_queued_for_deletion():
			var o_before: float = float(cat.get("overstimulation")) if cat.get("overstimulation") != null else 0.0
			var t_before: float = float(cat.get("trust")) if cat.get("trust") != null else 0.0
			var o_max: float = float(cat.get("overstim_threshold")) if cat.get("overstim_threshold") != null else 100.0
			var od: float = clampf(float(d.get("overstim", 0.0)), R.CAP_OVERSTIM, 0.0)
			var td: float = clampf(float(d.get("trust", 0.0)), 0.0, R.CAP_TRUST)
			if od != 0.0 and cat.get("overstimulation") != null:
				cat.set("overstimulation", clampf(o_before + od, 0.0, o_max))
			if td != 0.0:
				if cat.has_method("add_trust"):
					cat.call("add_trust", td)
				elif cat.get("trust") != null:
					var t_max: float = float(cat.get("trust_max")) if cat.get("trust_max") != null else 100.0
					cat.set("trust", clampf(t_before + td, 0.0, t_max))
			entry["applied"] = true
			entry["overstim_before"] = o_before
			entry["overstim_after"] = float(cat.get("overstimulation")) if cat.get("overstimulation") != null else 0.0
			entry["trust_before"] = t_before
			entry["trust_after"] = float(cat.get("trust")) if cat.get("trust") != null else 0.0
			if int(c.get("pets", 0)) > 0:
				calmer.append(str(c.get("name", "Cat")))
		report["cats"].append(entry)
	last_report = report
	var msg: String
	if pay:
		msg = "Served %s (%s) +$%d" % [res.get("recipe_name", "order"), res.get("grade_text", ""), money]
	else:
		msg = "Left the order - no harm done"
	if not calmer.is_empty():
		msg += "  -  %s feels calmer" % ", ".join(calmer)
	_notice(msg, 3.0)

func _notice(text: String, sec: float) -> void:
	if level == null or not is_instance_valid(level):
		return
	if level.has_method("show_notice"):
		level.call("show_notice", text, sec)
		return
	var hud: Node = level.get_node_or_null("HUD3D")
	if hud != null and hud.has_method("show_notice"):
		hud.call("show_notice", text, sec)

# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.echo:
			get_viewport().set_input_as_handled()
			return
		_handle_key(k)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _showing_result or _park_open:
			return   # let the buttons work
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var local: Vector2 = _play_rect.get_global_transform_with_canvas().affine_inverse() * mb.position
		var gp: Vector2 = local / float(_scale)
		var inside: bool = Rect2(Vector2.ZERO, GameScript.PLAY_SIZE).has_point(gp)
		if mb.pressed and inside:
			game.call("pointer_down", gp)
			get_viewport().set_input_as_handled()
		elif not mb.pressed:
			game.call("pointer_up", gp)
			if inside:
				get_viewport().set_input_as_handled()

func _handle_key(k: InputEventKey) -> void:
	var code: Key = k.keycode
	if _showing_result:
		if k.pressed and code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			serve()
		return
	if _park_open:
		if k.pressed:
			match code:
				KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_close_park_prompt()
				KEY_P:
					park()
				KEY_L:
					leave()
		return
	match code:
		KEY_ESCAPE:
			if k.pressed:
				_open_park_prompt()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if k.pressed:
				game.call("primary_down")
			else:
				game.call("primary_up")
		KEY_P, KEY_E:
			if k.pressed:
				game.call("pet_key_down")
			else:
				game.call("pet_key_up")
		KEY_A:
			if k.pressed:
				game.call("assist")

func _open_park_prompt() -> void:
	if game == null or not bool(game.call("can_park")):
		return
	game.call("primary_up")
	game.call("pet_key_up")
	_park_open = true
	_park.visible = true
	game.process_mode = Node.PROCESS_MODE_DISABLED

func _close_park_prompt() -> void:
	_park_open = false
	_park.visible = false
	if game != null:
		game.process_mode = Node.PROCESS_MODE_INHERIT

# ------------------------------------------------------------------ game signals

func _on_scored(result: Dictionary) -> void:
	last_result = result
	_showing_result = true
	_fill_result(result)
	_result.visible = true
	_place_result.call_deferred()
	_stamp.set("pop", 1.6)
	var tw := _stamp.create_tween()
	tw.tween_method(func(v: float) -> void:
		_stamp.set("pop", v)
		_stamp.queue_redraw(), 1.6, 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_serve_btn.grab_focus()

func _on_popup(pos: Vector2, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", col.darkened(0.15))
	l.add_theme_color_override("font_outline_color", Art.CREAM)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# shared text rule (D: 1px outline, E: + cream halo, F: 2px outline + drop shadow)
	if not Art.text_rule().is_empty():
		l.add_theme_color_override("font_color", col.lightened(0.3))
		Art.apply_text_rule(l, POPUP_TEXT_UNIT)
	_popups.add_child(l)
	l.reset_size()
	var p: Vector2 = pos * float(_scale) - Vector2(l.size.x * 0.5, l.size.y)
	p.x = clampf(p.x, 4.0, _popups.size.x - l.size.x - 4.0)
	p.y = clampf(p.y, 2.0, _popups.size.y - l.size.y)
	l.position = p
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", p.y - 30.0, 1.1)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.7)
	tw.tween_callback(l.queue_free)

# ------------------------------------------------------------------ per-frame HUD

func _process(_delta: float) -> void:
	if not is_open or game == null:
		return
	var info: Dictionary = game.call("get_hud_info")
	_title.text = str(info.get("title", "")).to_upper()
	_diff.text = str(info.get("difficulty", ""))
	_update_ticket(info.get("steps", []))
	_update_cats(info.get("cats", []))
	var el: float = float(info.get("elapsed_sec", 0.0))
	var par: float = float(info.get("par_sec", 20.0))
	_timer_lbl.text = "%s  /  par %s" % [_mmss(el), _mmss(par)]
	_timer_bar.set_meta("el", el)
	_timer_bar.set_meta("par", par)
	_timer_bar.queue_redraw()
	_hint.text = str(info.get("hint", ""))
	var alert: String = str(info.get("alert", ""))
	_alert.text = alert
	_alert.visible = alert != ""
	_alert_icon.visible = alert != ""
	if bool(info.get("telegraph", false)):
		_alert_icon.modulate = Color(1, 1, 1, 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 90.0)))
	else:
		_alert_icon.modulate = Color.WHITE
	var hold: String = "tap" if bool(context.get("toggle", false)) else "hold"
	_keys.text = "Space/click: cook   P or %s on cat: pet   Esc: park" % hold

func _mmss(t: float) -> String:
	var s: int = int(floor(t))
	return "%d:%02d" % [s / 60, s % 60]

func _update_ticket(list: Array) -> void:
	var key: String = str(list)
	if _hud_cache.get("ticket", "") == key:
		return
	_hud_cache["ticket"] = key
	for c in _ticket.get_children():
		c.queue_free()
	for i in range(list.size()):
		var s: Dictionary = list[i]
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		sb.set_border_width_all(2)
		var active: bool = false
		var txt: String = "%d %s" % [i + 1, s["label"]]
		var fc: Color = Art.TEXT
		match str(s["state"]):
			"done":
				var acc: float = float(s["acc"])
				sb.bg_color = Color("#DDEFE1") if acc >= 0.85 else (Color("#F8E7C2") if acc >= 0.55 else Color("#EFE3D6"))
				sb.border_color = Art.SAGE
				txt += "  " + ("*" if acc >= 0.99 else "") + ("ok" if acc < 0.55 else ("good" if acc < 0.85 else "great"))
				if acc >= 0.99:
					txt = "%d %s  perfect" % [i + 1, s["label"]]
			"active":
				sb.bg_color = Color("#FFE9B8")
				sb.border_color = Art.AMBER
				sb.set_border_width_all(3)
				active = true
			"next":
				sb.bg_color = Art.CREAM
				sb.border_color = Art.AMBER
			_:
				sb.bg_color = Color("#F7EDE0")
				sb.border_color = Color("#E2CDB4")
				fc = Art.MUTED
		if Art.is_a():
			chip.add_theme_stylebox_override("panel", sb)
		else:
			chip.add_theme_stylebox_override("panel", Art.chrome_box(sb.bg_color, sb.border_color, 3 if active else 2, 8, Vector4(10, 3, 10, 3)))
		var l := Label.new()
		l.text = txt
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", fc)
		chip.add_child(l)
		_ticket.add_child(chip)

func _update_cats(list: Array) -> void:
	var key: String = str(list)
	if _hud_cache.get("cats", "") == key:
		return
	_hud_cache["cats"] = key
	for c in _cat_box.get_children():
		c.queue_free()
	if list.is_empty():
		var l0 := Label.new()
		l0.text = "No counter cat today"
		l0.add_theme_font_size_override("font_size", 15)
		l0.add_theme_color_override("font_color", Art.MUTED)
		_cat_box.add_child(l0)
		return
	for c in list:
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(14)
		sb.bg_color = Color("#FBEFE0")
		sb.border_color = Art.GOLD if bool(c.get("helper", false)) else Art.OAK
		sb.set_border_width_all(2)
		sb.content_margin_left = 8
		sb.content_margin_right = 10
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		if Art.is_a():
			chip.add_theme_stylebox_override("panel", sb)
		else:
			chip.add_theme_stylebox_override("panel", Art.chrome_box(sb.bg_color, sb.border_color, 2, 12, Vector4(8, 2, 10, 2)))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		chip.add_child(hb)
		var icon := TextureRect.new()
		icon.texture = Art.paw(Art.OAK_DARK, "paw_oak")
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(26, 20)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hb.add_child(icon)
		var mood: String = str(c.get("mood", "calm"))
		var mood_col: Color = Art.SAGE_DARK if mood == "calm" else (Art.AMBER.darkened(0.2) if mood == "fizzy" else Art.ORANGE)
		var name_l := Label.new()
		name_l.text = str(c.get("name", "Cat"))
		name_l.add_theme_font_size_override("font_size", 16)
		hb.add_child(name_l)
		var mood_l := Label.new()
		var tag: String = mood
		if bool(c.get("helper", false)):
			tag = "helper"
			mood_col = Art.GOLD.darkened(0.35)
		elif bool(c.get("shy", false)):
			tag += ", shy"
		mood_l.text = tag
		mood_l.add_theme_font_size_override("font_size", 14)
		mood_l.add_theme_color_override("font_color", mood_col)
		hb.add_child(mood_l)
		var trust_l := Label.new()
		trust_l.text = "trust %d" % int(round(float(c.get("trust", 0.0))))
		trust_l.add_theme_font_size_override("font_size", 14)
		trust_l.add_theme_color_override("font_color", Art.MUTED)
		hb.add_child(trust_l)
		if int(c.get("pets", 0)) > 0:
			var pets_l := Label.new()
			pets_l.text = "pets x%d" % int(c["pets"])
			pets_l.add_theme_font_size_override("font_size", 14)
			pets_l.add_theme_color_override("font_color", Art.PINK.darkened(0.25))
			hb.add_child(pets_l)
		_cat_box.add_child(chip)

func _fill_result(res: Dictionary) -> void:
	_stamp.call("set_grade", str(res.get("grade", "C")))
	_res_title.text = str(res.get("grade_text", ""))
	_res_title.add_theme_color_override("font_color", Art.GRADE_COLORS.get(str(res.get("grade", "C")), Art.TEXT).darkened(0.2))
	for c in _res_lines.get_children():
		c.queue_free()
	_add_line("%s served!" % res.get("recipe_name", ""), 20, Art.TEXT)
	_add_line("Time %s  (par %s)" % [_mmss(float(res.get("elapsed", 0.0))), _mmss(float(res.get("par", 0.0)))], 17, Art.TEXT)
	_add_line("Precision %d / 70    Speed %d / 30" % [int(round(float(res.get("precision", 0.0)))), int(round(float(res.get("speed", 0.0))))], 16, Art.MUTED)
	var any_pet: bool = false
	for c in res.get("cats", []):
		var pets: int = int(c.get("pets", 0))
		var d: Dictionary = c.get("delta", {})
		if pets > 0:
			any_pet = true
			_add_line("Cat care: %s petted x%d  (overstim %d, trust +%d)" % [c["name"], pets, int(round(float(d.get("overstim", 0.0)))), int(round(float(d.get("trust", 0.0))))], 17, Art.PINK.darkened(0.3))
		if int(c.get("assists", 0)) > 0:
			_add_line("%s lent a paw! (+1 trust)" % c["name"], 16, Art.GOLD.darkened(0.3))
		if int(c.get("booped", 0)) > 0:
			_add_line("You booped %s's nose. Achoo!" % c["name"], 16, Art.MUTED)
	if not any_pet and not (res.get("cats", []) as Array).is_empty():
		_add_line("Cat care: no pets this time - that's okay!", 16, Art.MUTED)
	if bool(res.get("sticker", false)):
		_add_line("Paw-print sticker: Cat-Approved!", 16, Art.PINK.darkened(0.3))
	if int(res.get("catches", 0)) > 0:
		_add_line("Nice catch x%d" % int(res["catches"]), 16, Art.GOLD.darkened(0.3))
	_add_line("+$%d" % int(res.get("money", 0)), 26, Art.SAGE_DARK)

func _add_line(t: String, fs: int, col: Color) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	_res_lines.add_child(l)

# ------------------------------------------------------------------ build

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(THEME_PATH):
		_root.theme = Art.ui_theme(THEME_PATH)
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = DIM
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_window = PanelContainer.new()
	_window.name = "KitchenWindow"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Art.CREAM
	sb.border_color = Art.OAK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0.09, 0.05, 0.03, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	_window.add_theme_stylebox_override("panel", sb)
	_root.add_child(_window)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_window.add_child(vb)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vb.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	header.add_child(_title)
	_diff = Label.new()
	_diff.add_theme_font_size_override("font_size", 15)
	_diff.add_theme_color_override("font_color", Art.MUTED)
	header.add_child(_diff)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	_cat_box = HBoxContainer.new()
	_cat_box.add_theme_constant_override("separation", 8)
	header.add_child(_cat_box)
	var esc_btn := Button.new()
	esc_btn.text = "Esc"
	esc_btn.focus_mode = Control.FOCUS_NONE
	esc_btn.tooltip_text = "Park or leave the order (no loss)"
	esc_btn.pressed.connect(_open_park_prompt)
	header.add_child(esc_btn)

	var tick_row := HBoxContainer.new()
	tick_row.add_theme_constant_override("separation", 8)
	vb.add_child(tick_row)
	_ticket = HBoxContainer.new()
	_ticket.add_theme_constant_override("separation", 6)
	tick_row.add_child(_ticket)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tick_row.add_child(sp2)
	_timer_lbl = Label.new()
	_timer_lbl.add_theme_font_size_override("font_size", 16)
	_timer_lbl.add_theme_color_override("font_color", Art.MUTED)
	tick_row.add_child(_timer_lbl)
	_timer_bar = Control.new()
	_timer_bar.custom_minimum_size = Vector2(150, 14)
	_timer_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_timer_bar.draw.connect(_draw_timer_bar)
	tick_row.add_child(_timer_bar)

	_play_holder = Control.new()
	_play_holder.name = "PlayHolder"
	_play_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(_play_holder)
	var frame := Panel.new()
	_frame = frame
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Art.OUTLINE
	fsb.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = -3
	frame.offset_top = -3
	frame.offset_right = 3
	frame.offset_bottom = 3
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_holder.add_child(frame)
	_vp = SubViewport.new()
	_vp.name = "PlayViewport"
	_vp.size = Vector2i(320, 180)
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	_vp.snap_2d_transforms_to_pixel = true
	_vp.snap_2d_vertices_to_pixel = true
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_play_rect = TextureRect.new()
	_play_rect.name = "Play"
	_play_rect.texture = _vp.get_texture()
	_play_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_play_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_play_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_play_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_play_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_holder.add_child(_play_rect)
	_popups = Control.new()
	_popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_holder.add_child(_popups)

	var prompt := HBoxContainer.new()
	prompt.add_theme_constant_override("separation", 10)
	prompt.custom_minimum_size = Vector2(0, 30)
	vb.add_child(prompt)
	_alert_icon = TextureRect.new()
	_alert_icon.texture = Art.bang()
	_alert_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_alert_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_alert_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_alert_icon.custom_minimum_size = Vector2(28, 28)
	prompt.add_child(_alert_icon)
	_alert = Label.new()
	_alert.add_theme_font_size_override("font_size", 17)
	_alert.add_theme_color_override("font_color", Art.ORANGE.darkened(0.25))
	prompt.add_child(_alert)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prompt.add_child(_hint)
	_keys = Label.new()
	_keys.add_theme_font_size_override("font_size", 14)
	_keys.add_theme_color_override("font_color", Art.MUTED)
	vb.add_child(_keys)

	_build_result()
	_build_park()
	get_viewport().size_changed.connect(_layout)
	_style_rev = Art.style_rev
	if not Art.is_a():
		_style_rev = -1
		_restyle()

## Re-apply window chrome for the current art style (cc_art.gd STYLES). Style A
## keeps exactly the panels built above; B-F swap in pixel panels, the bolder
## theme, a thicker play-area frame and the restyled alert icon.
func _restyle() -> void:
	if _style_rev == Art.style_rev:
		return
	_style_rev = Art.style_rev
	_hud_cache.clear()
	if ResourceLoader.exists(THEME_PATH):
		_root.theme = Art.ui_theme(THEME_PATH)
	_alert_icon.texture = Art.bang()
	if Art.is_a():
		var sb := StyleBoxFlat.new()
		sb.bg_color = Art.CREAM
		sb.border_color = Art.OAK
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		sb.shadow_color = Color(0.09, 0.05, 0.03, 0.35)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 4)
		_window.add_theme_stylebox_override("panel", sb)
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = Art.OUTLINE
		fsb.set_corner_radius_all(4)
		_frame.add_theme_stylebox_override("panel", fsb)
		_set_frame_offset(3)
		var rsb: StyleBoxFlat = _cream_panel()
		rsb.content_margin_top = 10
		rsb.content_margin_bottom = 10
		_result.add_theme_stylebox_override("panel", rsb)
		_park.add_theme_stylebox_override("panel", _cream_panel())
	else:
		_window.add_theme_stylebox_override("panel", Art.chrome_box(Art.CREAM, Art.OAK, 3, 15, Vector4(20, 12, 20, 12)))
		var cp: int = int(Art.st()["chrome_px"])
		var fr: StyleBox = Art.chrome_box(Art.OUTLINE, Color(0, 0, 0, 0), 0, 3, Vector4.ZERO)
		_frame.add_theme_stylebox_override("panel", fr)
		_set_frame_offset(cp + 1)
		_result.add_theme_stylebox_override("panel", Art.chrome_box(Art.CREAM, Art.OAK, 3, 15, Vector4(26, 12, 26, 12)))
		_park.add_theme_stylebox_override("panel", Art.chrome_box(Art.CREAM, Art.OAK, 3, 15, Vector4(26, 18, 26, 18)))
	_timer_bar.queue_redraw()
	if _stamp != null:
		_stamp.queue_redraw()

func _set_frame_offset(px: int) -> void:
	_frame.offset_left = -px
	_frame.offset_top = -px
	_frame.offset_right = px
	_frame.offset_bottom = px

func _cream_panel(border: Color = Art.OAK) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Art.CREAM
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	sb.shadow_color = Color(0.09, 0.05, 0.03, 0.35)
	sb.shadow_size = 12
	return sb

func _build_result() -> void:
	_result = PanelContainer.new()
	_result.name = "ResultCard"
	var rsb: StyleBoxFlat = _cream_panel()
	rsb.content_margin_top = 10
	rsb.content_margin_bottom = 10
	_result.add_theme_stylebox_override("panel", rsb)
	_result.visible = false
	_root.add_child(_result)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	_result.add_child(hb)
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(left)
	_stamp = StampScript.new()
	_stamp.custom_minimum_size = Vector2(124, 124)
	left.add_child(_stamp)
	_res_title = Label.new()
	_res_title.add_theme_font_size_override("font_size", 28)
	_res_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_res_title)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(right)
	_res_lines = VBoxContainer.new()
	_res_lines.add_theme_constant_override("separation", 2)
	right.add_child(_res_lines)
	_serve_btn = Button.new()
	_serve_btn.text = "Serve!  (Enter)"
	_serve_btn.custom_minimum_size = Vector2(200, 44)
	_serve_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_serve_btn.pressed.connect(serve)
	right.add_child(_serve_btn)

func _build_park() -> void:
	_park = PanelContainer.new()
	_park.name = "ParkPrompt"
	_park.add_theme_stylebox_override("panel", _cream_panel())
	_park.visible = false
	_root.add_child(_park)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_park.add_child(vb)
	var t := Label.new()
	t.text = "Step away from the counter?"
	t.add_theme_font_size_override("font_size", 24)
	vb.add_child(t)
	var s := Label.new()
	s.text = "Nothing is lost either way. The cats stay comfy."
	s.add_theme_font_size_override("font_size", 16)
	s.add_theme_color_override("font_color", Art.MUTED)
	vb.add_child(s)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	for spec in [["Keep cooking (Esc)", _close_park_prompt], ["Park order (P)", park], ["Leave order (L)", leave]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		hb.add_child(b)

func _layout() -> void:
	if _window == null:
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var chrome_h: float = 168.0
	var k: int = 1
	for cand in [5, 4, 3, 2, 1]:
		if 320.0 * cand + 60.0 <= vs.x * 0.9 and 180.0 * cand + chrome_h <= vs.y * 0.86:
			k = cand
			break
	_scale = k
	_play_holder.custom_minimum_size = Vector2(320 * k, 180 * k)
	var w: float = maxf(320.0 * k + 40.0, vs.x * 0.7)
	_window.custom_minimum_size = Vector2(w, 0)
	_window.reset_size()
	_window.position = ((vs - _window.size) * 0.5).round()
	_place_result()
	_park.reset_size()
	_park.position = ((vs - _park.size) * 0.5).round()

## Result card sits over the wall so the finished dish on the counter stays visible.
func _place_result() -> void:
	_result.reset_size()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var pos: Vector2 = ((vs - _result.size) * 0.5).round()
	if _play_rect != null and _play_rect.is_inside_tree():
		var top: float = _play_rect.global_position.y + 2.0 * float(_scale)
		var counter_y: float = _play_rect.global_position.y + 82.0 * float(_scale)
		pos.y = clampf(counter_y - _result.size.y, top, pos.y)
	_result.position = pos

func _draw_timer_bar() -> void:
	var el: float = float(_timer_bar.get_meta("el", 0.0))
	var par: float = float(_timer_bar.get_meta("par", 20.0))
	var r := Rect2(Vector2.ZERO, _timer_bar.size)
	var bw: float = 2.0 if Art.is_a() else float(Art.st()["chrome_px"])
	if not Art.is_a():
		if Art.flag("shadow"):
			_timer_bar.draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Art.SHADOW)
		if Art.flag("halo"):
			_timer_bar.draw_rect(r.grow(3), Art.CREAM)
	_timer_bar.draw_rect(r, Art.OUTLINE)
	_timer_bar.draw_rect(r.grow(-bw), Color("#F3E6D3"))
	var f: float = clampf(el / (par * 2.0), 0.0, 1.0)
	var col: Color = Art.SAGE
	if el > par:
		col = Color("#F0A070")
	elif el > par * 0.8:
		col = Art.AMBER
	var inner: Rect2 = r.grow(-bw)
	_timer_bar.draw_rect(Rect2(inner.position, Vector2(inner.size.x * f, inner.size.y)), col)
	if Art.flag("rim"):
		_timer_bar.draw_rect(Rect2(inner.position, Vector2(inner.size.x * f, 2)), Art.rim_col(col))
	if Art.flag("cel"):
		_timer_bar.draw_rect(Rect2(inner.position.x, inner.end.y - 2, inner.size.x * f, 2), Art.cel_col(col))
	var px: float = inner.position.x + inner.size.x * 0.5
	var mw: float = 2.0 if Art.is_a() else bw
	_timer_bar.draw_rect(Rect2(px - mw * 0.5, 0, mw, r.size.y), Art.OUTLINE)
